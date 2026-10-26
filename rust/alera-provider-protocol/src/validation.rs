use crate::{
    error::nonempty, ContentDeltaPayload, EventKind, ItemLifecyclePayload, ProviderError,
    ProviderEvent, ProviderGoalUpdate, ProviderSkillsUpdate, ProviderSlashCommandsUpdate,
    RequestKind, TurnStatus, UsageLimitsUpdate, UserInputQuestion,
};

impl ProviderEvent {
    /// Validate the shared envelope and core payload invariants without rejecting native extension fields.
    pub fn validate(&self) -> Result<(), ProviderError> {
        self.native_task()?;
        nonempty(&self.event_id, "eventId")?;
        nonempty(&self.provider_instance_id, "providerInstanceId")?;
        nonempty(&self.thread_id, "threadId")?;
        nonempty(self.provider.as_str(), "provider")?;
        nonempty(self.kind.as_str(), "type")?;
        chrono::DateTime::parse_from_rfc3339(&self.created_at)
            .map_err(|_| ProviderError::Validation("createdAt must be an ISO timestamp".into()))?;
        for (value, name) in [
            (&self.turn_id, "turnId"),
            (&self.item_id, "itemId"),
            (&self.request_id, "requestId"),
        ] {
            if let Some(value) = value {
                nonempty(value, name)?;
            }
        }
        if let Some(refs) = &self.provider_refs {
            for (value, name) in [
                (&refs.provider_turn_id, "providerTurnId"),
                (&refs.provider_item_id, "providerItemId"),
                (&refs.provider_request_id, "providerRequestId"),
            ] {
                if let Some(value) = value {
                    nonempty(value, name)?;
                }
            }
        }
        if let Some(raw) = &self.raw {
            nonempty(&raw.source, "raw source")?;
            if let Some(method) = &raw.method {
                nonempty(method, "raw method")?;
            }
            if let Some(message_type) = &raw.message_type {
                nonempty(message_type, "raw messageType")?;
            }
        }
        match &self.kind {
            EventKind::ContentDelta => {
                decode::<ContentDeltaPayload>(&self.payload, "content.delta")?;
            }
            EventKind::ItemStarted | EventKind::ItemUpdated | EventKind::ItemCompleted => {
                decode::<ItemLifecyclePayload>(&self.payload, "item lifecycle")?;
            }
            EventKind::RuntimeWarning | EventKind::RuntimeError => {
                nonempty(
                    self.payload["message"].as_str().unwrap_or_default(),
                    "runtime message",
                )?;
                if self.kind == EventKind::RuntimeError {
                    validate_failure_class(&self.payload)?;
                }
            }
            EventKind::RequestOpened | EventKind::RequestResolved => {
                decode::<RequestKind>(&self.payload["requestType"], "requestType")?;
            }
            EventKind::UserInputRequested => {
                let questions =
                    decode::<Vec<UserInputQuestion>>(&self.payload["questions"], "questions")?;
                for question in questions {
                    nonempty(&question.id, "question id")?;
                    nonempty(&question.header, "question header")?;
                    nonempty(&question.question, "question text")?;
                }
            }
            EventKind::TaskStarted
            | EventKind::TaskProgress
            | EventKind::TaskUpdated
            | EventKind::TaskCompleted => {
                nonempty(
                    self.payload["taskId"].as_str().unwrap_or_default(),
                    "taskId",
                )?;
                if let Some(parent) = self.payload.get("parentTaskId") {
                    nonempty(parent.as_str().unwrap_or_default(), "parentTaskId")?;
                }
                only_true(&self.payload, "awaited")?;
                only_true(&self.payload, "wakesParent")?;
                if self.kind != EventKind::TaskCompleted && self.task_wakes_parent() {
                    return Err(ProviderError::Validation(
                        "wakesParent describes a completed task".into(),
                    ));
                }
            }
            EventKind::SessionConfigured => {
                if !self.payload["config"].is_object() {
                    return Err(ProviderError::Validation(
                        "session.configured requires config".into(),
                    ));
                }
            }
            EventKind::SessionCommandsUpdated => {
                let update =
                    decode::<ProviderSlashCommandsUpdate>(&self.payload, "session commands")?;
                for command in update.commands {
                    nonempty(&command.name, "command name")?;
                }
            }
            EventKind::SessionSkillsUpdated => {
                let update = decode::<ProviderSkillsUpdate>(&self.payload, "session skills")?;
                for skill in update.skills {
                    nonempty(&skill.name, "skill name")?;
                    nonempty(&skill.path, "skill path")?;
                }
            }
            EventKind::SessionGoalUpdated => {
                let update = decode::<ProviderGoalUpdate>(&self.payload, "session goal")?;
                if let Some(goal) = update.goal {
                    nonempty(&goal.objective, "goal objective")?;
                }
            }
            EventKind::AccountRateLimitsUpdated => {
                let limits = decode::<UsageLimitsUpdate>(&self.payload["limits"], "limits")?;
                for window in limits.windows {
                    nonempty(&window.id, "usage window id")?;
                    nonempty(&window.label, "usage window label")?;
                    if !window.used_percent.is_finite()
                        || !(0.0..=100.0).contains(&window.used_percent)
                    {
                        return Err(ProviderError::Validation(
                            "usage window percentage must be between 0 and 100".into(),
                        ));
                    }
                    if let Some(resets_at) = window.resets_at {
                        chrono::DateTime::parse_from_rfc3339(&resets_at).map_err(|_| {
                            ProviderError::Validation(
                                "usage window resetsAt must be an ISO timestamp".into(),
                            )
                        })?;
                    }
                }
            }
            EventKind::TurnCompleted => {
                let state = serde_json::from_value::<TurnStatus>(self.payload["state"].clone())
                    .map_err(|_| {
                        ProviderError::Validation("turn.completed requires a terminal state".into())
                    })?;
                validate_failure_class(&self.payload)?;
                only_true(&self.payload, "childTurnsContinue")?;
                if state != TurnStatus::Failed
                    && (self.payload.get("failureClass").is_some() || self.child_turns_continue())
                {
                    return Err(ProviderError::Validation(
                        "failureClass and childTurnsContinue describe a failed turn".into(),
                    ));
                }
                if let Some(usage) = self.payload.get("tokenUsage") {
                    validate_token_usage(usage)?;
                }
            }
            EventKind::TurnAborted => {
                let reason = self.payload["reason"].as_str().unwrap_or_default();
                nonempty(reason, "turn.aborted reason")?;
                if let Some(usage) = self.payload.get("tokenUsage") {
                    validate_token_usage(usage)?;
                }
            }
            _ => {}
        }
        if let Some(request) = &self.runtime_request {
            nonempty(&request.thread_id, "runtime request threadId")?;
            if request.thread_id != self.thread_id
                || self.request_id.as_deref() != Some(request.request_id.to_string().as_str())
            {
                return Err(ProviderError::Validation(
                    "runtime request identity does not match its event".into(),
                ));
            }
        }
        Ok(())
    }
}

fn decode<T: serde::de::DeserializeOwned>(
    value: &serde_json::Value,
    name: &str,
) -> Result<T, ProviderError> {
    serde_json::from_value(value.clone())
        .map_err(|error| ProviderError::Validation(format!("invalid {name} payload: {error}")))
}

fn validate_failure_class(payload: &serde_json::Value) -> Result<(), ProviderError> {
    match payload.get("failureClass") {
        Some(class) if !class.is_string() => Err(ProviderError::Validation(
            "failureClass must be a string".into(),
        )),
        _ => Ok(()),
    }
}

/// Optional flags are present only when true, so absence keeps its meaning.
fn only_true(payload: &serde_json::Value, field: &str) -> Result<(), ProviderError> {
    match payload.get(field) {
        Some(value) if value != &serde_json::Value::Bool(true) => Err(ProviderError::Validation(
            format!("{field} is either true or absent"),
        )),
        _ => Ok(()),
    }
}

fn validate_token_usage(usage: &serde_json::Value) -> Result<(), ProviderError> {
    if usage["usageScope"] != "main_agent" || !usage["hasSubagents"].is_boolean() {
        return Err(ProviderError::Validation(
            "tokenUsage requires main_agent scope and hasSubagents".into(),
        ));
    }
    let complete = match usage["usageStatus"].as_str() {
        Some("complete") => true,
        Some("partial" | "unavailable") => false,
        _ => {
            return Err(ProviderError::Validation(
                "invalid tokenUsage usageStatus".into(),
            ))
        }
    };
    for field in [
        "inputTokens",
        "outputTokens",
        "cachedInputTokens",
        "cacheCreationTokens",
        "reasoningTokens",
    ] {
        match usage.get(field) {
            Some(value) if value.as_u64().is_none() => {
                return Err(ProviderError::Validation(format!(
                    "tokenUsage {field} must be a nonnegative integer"
                )))
            }
            None if complete && matches!(field, "inputTokens" | "outputTokens") => {
                return Err(ProviderError::Validation(format!(
                    "complete tokenUsage requires {field}"
                )))
            }
            _ => {}
        }
    }
    Ok(())
}
