#[derive(Clone, Copy)]
enum CanvasStateChange {
    Complete,
    Close,
}

fn capabilities_payload() -> HostResult<Value> {
    Ok(json!({
        "supported": true,
        "capabilities": AgentCanvasCapabilities::default(),
    }))
}

fn decision_inputs(
    value: Option<&Value>,
    document: &Value,
) -> HostResult<Vec<AgentCanvasDecisionInput>> {
    let explicit = value.and_then(Value::as_array);
    let components = document.get("components").and_then(Value::as_array);
    let source = explicit.or(components);
    let Some(items) = source else {
        return Ok(Vec::new());
    };
    let mut result = Vec::new();
    for item in items {
        let object = item
            .as_object()
            .ok_or_else(|| HostError::format("canvas components must be JSON objects."))?;
        let component_type = object
            .get("type")
            .or_else(|| object.get("component"))
            .and_then(Value::as_str);
        if value.is_none() && component_type != Some("DecisionRequest") {
            continue;
        }
        let props = object
            .get("props")
            .and_then(Value::as_object)
            .unwrap_or(object);
        let question = props
            .get("question")
            .or_else(|| props.get("title"))
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::format("DecisionRequest question is required."))?;
        result.push(AgentCanvasDecisionInput {
            id: props.get("id").and_then(Value::as_str).map(str::to_string),
            question: question.to_string(),
            options: props.get("options").cloned().unwrap_or_else(|| json!([])),
            expires_at: props
                .get("timeoutSeconds")
                .and_then(Value::as_i64)
                .filter(|seconds| *seconds > 0)
                .map(|seconds| (Utc::now() + Duration::seconds(seconds.min(86_400))).to_rfc3339()),
        });
    }
    Ok(result)
}

async fn enforce_publish_rate(store: &RuntimeStore, canvas_id: &str) -> HostResult<()> {
    let cutoff = (Utc::now() - Duration::minutes(1)).to_rfc3339();
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM agentCanvasEvents WHERE canvasId = ? AND eventType IN ('revision', 'decisionRequest') AND createdAt >= ?",
    )
    .bind(canvas_id)
    .bind(cutoff)
    .fetch_one(store.pool())
    .await
    .map_err(state_error)?;
    if count >= 60 {
        return Err(HostError::state(
            "Agent Canvas publish rate limit exceeded. Retry shortly.",
        ));
    }
    Ok(())
}

fn validate_typed_action(action: &Map<String, Value>, canvas: &AgentCanvas) -> HostResult<()> {
    let kind = action
        .get("kind")
        .and_then(Value::as_str)
        .ok_or_else(|| HostError::format("action.kind is required."))?;
    reject_untrusted_keys(action)?;
    const IMMEDIATE: [&str; 8] = [
        "openFile",
        "openDiff",
        "openSearch",
        "focusTerminal",
        "openPullRequest",
        "openArtifact",
        "copyText",
        "switchContextPanel",
    ];
    const CONTROLLED: [&str; 5] = [
        "resolveDecision",
        "approveExecutionPlan",
        "rejectExecutionPlan",
        "editPullRequestComment",
        "rerunValidation",
    ];
    const DESTRUCTIVE: [&str; 9] = [
        "stage",
        "unstage",
        "discard",
        "commit",
        "pull",
        "push",
        "mergePullRequest",
        "terminateTerminal",
        "deleteArtifact",
    ];
    if IMMEDIATE.contains(&kind) {
        validate_immediate_action(kind, action, canvas)?;
        return Ok(());
    }
    if CONTROLLED.contains(&kind) {
        if action.get("confirmed") != Some(&Value::Bool(true)) {
            return Err(HostError::state(
                "This Agent Canvas action requires explicit confirmation.",
            ));
        }
        if kind == "resolveDecision" {
            required_string_from_map(action, "decisionId")?;
        }
        return Ok(());
    }
    if DESTRUCTIVE.contains(&kind) {
        if action.get("confirmed") != Some(&Value::Bool(true)) {
            return Err(HostError::state(
                "Destructive Agent Canvas actions require strong confirmation.",
            ));
        }
        if kind == "terminateTerminal"
            && action.get("terminalSessionId").and_then(Value::as_str)
                != Some(canvas.terminal_session_id.as_str())
        {
            return Err(HostError::state(
                "Agent Canvas may terminate only its owning terminal tree.",
            ));
        }
        if kind == "deleteArtifact" {
            let artifact_id = required_string_from_map(action, "artifactId")?;
            require_registered_artifact(canvas, &artifact_id)?;
        }
        if let Some(path) = action.get("relativePath").and_then(Value::as_str) {
            validate_relative_path(path)?;
        }
        return Ok(());
    }
    Err(HostError::state(format!(
        "Unsupported Agent Canvas action: {kind}"
    )))
}

fn validate_immediate_action(
    kind: &str,
    action: &Map<String, Value>,
    canvas: &AgentCanvas,
) -> HostResult<()> {
    match kind {
        "openFile" | "openDiff" => {
            validate_relative_path(required_string_from_map(action, "relativePath")?.as_str())?
        }
        "openSearch" => {
            if let Some(query) = action.get("query") {
                let query = query
                    .as_str()
                    .ok_or_else(|| HostError::format("action.query must be text."))?;
                if query.len() > 4_096 {
                    return Err(HostError::format(
                        "openSearch query exceeds the 4096-byte limit.",
                    ));
                }
            }
        }
        "openArtifact" => {
            let artifact_id = required_string_from_map(action, "artifactId")?;
            require_registered_artifact(canvas, &artifact_id)?;
        }
        "copyText" => {
            let text = required_string_from_map(action, "text")?;
            if text.len() > 65_536 {
                return Err(HostError::format("copyText exceeds the 65536-byte limit."));
            }
        }
        "focusTerminal" => {
            if let Some(session_id) = action.get("terminalSessionId").and_then(Value::as_str) {
                if session_id != canvas.terminal_session_id {
                    return Err(HostError::state(
                        "Agent Canvas may focus only its owning terminal.",
                    ));
                }
            }
        }
        "switchContextPanel" => {
            let panel = required_string_from_map(action, "panel")?;
            if ![
                "agentCanvas",
                "explorer",
                "search",
                "gitDiff",
                "pullRequests",
            ]
            .contains(&panel.as_str())
            {
                return Err(HostError::format("unsupported context panel."));
            }
        }
        _ => {}
    }
    Ok(())
}

fn reject_untrusted_keys(action: &Map<String, Value>) -> HostResult<()> {
    const FORBIDDEN: [&str; 8] = [
        "command", "shell", "function", "code", "source", "url", "request", "path",
    ];
    if let Some(key) = action.keys().find(|key| FORBIDDEN.contains(&key.as_str())) {
        return Err(HostError::state(format!(
            "Agent Canvas actions cannot carry arbitrary {key} values."
        )));
    }
    Ok(())
}

fn require_registered_artifact(canvas: &AgentCanvas, artifact_id: &str) -> HostResult<()> {
    let registered = canvas
        .document
        .get("components")
        .and_then(Value::as_array)
        .is_some_and(|components| {
            components.iter().any(|component| {
                let Some(component) = component.as_object() else {
                    return false;
                };
                let kind = component
                    .get("type")
                    .or_else(|| component.get("component"))
                    .and_then(Value::as_str);
                if kind != Some("ArtifactCard") {
                    return false;
                }
                let props = component
                    .get("props")
                    .and_then(Value::as_object)
                    .unwrap_or(component);
                props.get("artifactId").and_then(Value::as_str) == Some(artifact_id)
            })
        });
    if registered {
        Ok(())
    } else {
        Err(HostError::state(
            "Agent Canvas artifact is not registered by the current document.",
        ))
    }
}

fn validate_relative_path(path: &str) -> HostResult<()> {
    if path.trim().is_empty() || Path::new(path).is_absolute() || path.contains('\\') {
        return Err(HostError::state(
            "Agent Canvas paths must be workspace-local relative paths.",
        ));
    }
    if path
        .split('/')
        .any(|part| part.is_empty() || part == ".." || part == ".")
    {
        return Err(HostError::state(
            "Agent Canvas paths cannot escape the workspace.",
        ));
    }
    Ok(())
}

fn required_string(payload: &Value, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::format(format!("{key} is required.")))
}

fn required_string_from_map(payload: &Map<String, Value>, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::format(format!("action.{key} is required.")))
}

fn optional_string(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn canvas() -> AgentCanvas {
        AgentCanvas {
            id: "canvas".to_string(),
            workspace_id: "workspace".to_string(),
            terminal_session_id: "session".to_string(),
            tab_id: None,
            agent_type: "codex".to_string(),
            title: "Run".to_string(),
            state: AgentCanvasState::Live,
            pinned: false,
            frozen: false,
            revision: 1,
            final_revision: None,
            document: json!({}),
            decisions: Vec::new(),
            created_at: String::new(),
            updated_at: String::new(),
            completed_at: None,
            expires_at: None,
        }
    }

    #[test]
    fn arbitrary_process_actions_are_rejected() {
        let error = validate_typed_action(
            &serde_json::from_value(json!({"kind": "openFile", "command": "rm -rf"})).unwrap(),
            &canvas(),
        )
        .unwrap_err();
        assert!(error.to_string().contains("arbitrary"));
    }

    #[test]
    fn terminal_termination_is_scoped_to_the_canvas_owner() {
        let error = validate_typed_action(
            &serde_json::from_value(json!({
                "kind": "terminateTerminal",
                "terminalSessionId": "other",
                "confirmed": true
            }))
            .unwrap(),
            &canvas(),
        )
        .unwrap_err();
        assert!(error.to_string().contains("owning terminal"));
    }

    #[test]
    fn workspace_paths_reject_traversal_and_absolute_locations() {
        for path in ["../outside.txt", "/tmp/outside.txt", "folder/../file.txt"] {
            assert!(validate_relative_path(path).is_err(), "accepted path: {path}");
        }
    }

    #[test]
    fn controlled_actions_require_confirmation() {
        let error = validate_typed_action(
            &serde_json::from_value(json!({"kind": "rerunValidation"})).unwrap(),
            &canvas(),
        )
        .unwrap_err();
        assert!(error.to_string().contains("confirmation"));
    }

    #[test]
    fn open_search_does_not_require_a_file_path() {
        validate_typed_action(
            &serde_json::from_value(json!({"kind": "openSearch"})).unwrap(),
            &canvas(),
        )
        .unwrap();
    }

    #[test]
    fn artifact_actions_require_a_registered_artifact() {
        let mut canvas = canvas();
        canvas.document = json!({
            "components": [{
                "type": "ArtifactCard",
                "props": {"artifactId": "artifact-1"}
            }]
        });
        validate_typed_action(
            &serde_json::from_value(json!({
                "kind": "openArtifact",
                "artifactId": "artifact-1"
            }))
            .unwrap(),
            &canvas,
        )
        .unwrap();
        let error = validate_typed_action(
            &serde_json::from_value(json!({
                "kind": "openArtifact",
                "artifactId": "artifact-2"
            }))
            .unwrap(),
            &canvas,
        )
        .unwrap_err();
        assert!(error.to_string().contains("not registered"));
    }
}
