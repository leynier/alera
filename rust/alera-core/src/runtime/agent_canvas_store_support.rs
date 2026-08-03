#[derive(Debug, Clone)]
pub struct AgentCanvasDecisionInput {
    pub id: Option<String>,
    pub question: String,
    pub options: Value,
    pub expires_at: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AgentCanvasPublishResult {
    pub canvas: AgentCanvas,
    pub changed: bool,
}

fn require_identity(workspace_id: &str, terminal_session_id: &str) -> Result<()> {
    normalize_text(workspace_id, 256, "workspace id")?;
    normalize_text(terminal_session_id, 256, "terminal session id")?;
    Ok(())
}

fn normalize_text(value: &str, max_bytes: usize, label: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        bail!(RuntimeStoreError::Message(format!("{label} is required.")));
    }
    if value.len() > max_bytes {
        bail!(RuntimeStoreError::Message(format!(
            "{label} exceeds the {max_bytes}-byte limit."
        )));
    }
    Ok(value.to_string())
}

fn validate_document(document: &Value) -> Result<()> {
    let bytes = serde_json::to_vec(document)?;
    if bytes.len() > AGENT_CANVAS_MAX_DOCUMENT_BYTES {
        bail!(RuntimeStoreError::Message(format!(
            "Agent Canvas document exceeds the {}-byte limit.",
            AGENT_CANVAS_MAX_DOCUMENT_BYTES
        )));
    }
    let object = document.as_object().ok_or_else(|| {
        RuntimeStoreError::Message("Agent Canvas document must be a JSON object.".to_string())
    })?;
    if let Some(version) = object.get("version").and_then(Value::as_i64) {
        if version != AGENT_CANVAS_PROTOCOL_VERSION {
            bail!(RuntimeStoreError::Message(format!(
                "unsupported Agent Canvas document version: {version}."
            )));
        }
    }
    let components = object
        .get("components")
        .and_then(Value::as_array)
        .ok_or_else(|| {
            RuntimeStoreError::Message(
                "Agent Canvas document must contain a components array.".to_string(),
            )
        })?;
    if components.len() > AGENT_CANVAS_MAX_COMPONENTS {
        bail!(RuntimeStoreError::Message(format!(
            "Agent Canvas supports at most {AGENT_CANVAS_MAX_COMPONENTS} components."
        )));
    }
    for component in components {
        let component = component.as_object().ok_or_else(|| {
            RuntimeStoreError::Message("Agent Canvas components must be JSON objects.".to_string())
        })?;
        let kind = component
            .get("type")
            .or_else(|| component.get("component"))
            .and_then(Value::as_str)
            .ok_or_else(|| {
                RuntimeStoreError::Message("Agent Canvas components require a type.".to_string())
            })?;
        if !AGENT_CANVAS_COMPONENTS.contains(&kind) {
            bail!(RuntimeStoreError::Message(format!(
                "unsupported Agent Canvas component: {kind}."
            )));
        }
    }
    Ok(())
}

async fn delete_canvas_children(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    canvas_id: &str,
) -> Result<()> {
    for table in [
        "agentCanvasRevisions",
        "agentCanvasDecisions",
        "agentCanvasEvents",
    ] {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "DELETE FROM {table} WHERE canvasId = ?"
        )))
        .bind(canvas_id)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

fn decision_from_row(row: sqlx::sqlite::SqliteRow) -> Result<AgentCanvasDecision> {
    let state_raw: String = row.try_get("state")?;
    Ok(AgentCanvasDecision {
        id: row.try_get("id")?,
        canvas_id: row.try_get("canvasId")?,
        revision: row.try_get("revision")?,
        question: row.try_get("question")?,
        options: serde_json::from_str(&row.try_get::<String, _>("optionsJson")?)
            .unwrap_or_else(|_| json!([])),
        state: AgentCanvasDecisionState::parse(&state_raw)
            .ok_or_else(|| anyhow!("invalid Agent Canvas decision state: {state_raw}"))?,
        resolution: row
            .try_get::<Option<String>, _>("resolutionJson")?
            .and_then(|value| serde_json::from_str(&value).ok()),
        created_at: row.try_get("createdAt")?,
        resolved_at: row.try_get("resolvedAt")?,
        expires_at: row.try_get("expiresAt")?,
    })
}

fn event_from_row(row: sqlx::sqlite::SqliteRow) -> Result<AgentCanvasEvent> {
    Ok(AgentCanvasEvent {
        sequence: row.try_get("sequence")?,
        canvas_id: row.try_get("canvasId")?,
        workspace_id: row.try_get("workspaceId")?,
        event_type: row.try_get("eventType")?,
        payload: serde_json::from_str(&row.try_get::<String, _>("payloadJson")?)
            .unwrap_or_else(|_| json!({})),
        created_at: row.try_get("createdAt")?,
    })
}

impl RuntimeStore {
    async fn append_event(
        &self,
        canvas_id: &str,
        workspace_id: &str,
        event_type: &str,
        payload: Value,
    ) -> Result<()> {
        sqlx::query("INSERT INTO agentCanvasEvents (canvasId, workspaceId, eventType, payloadJson, createdAt) VALUES (?, ?, ?, ?, ?)")
            .bind(canvas_id).bind(workspace_id).bind(event_type).bind(serde_json::to_string(&payload)?).bind(format_timestamp(Utc::now())).execute(self.pool()).await?;
        sqlx::query("DELETE FROM agentCanvasEvents WHERE canvasId = ? AND sequence NOT IN (SELECT sequence FROM agentCanvasEvents WHERE canvasId = ? ORDER BY sequence DESC LIMIT ?)")
            .bind(canvas_id).bind(canvas_id).bind(AGENT_CANVAS_MAX_EVENTS).execute(self.pool()).await?;
        Ok(())
    }

    async fn canvas_workspace_id(&self, canvas_id: &str) -> Result<String> {
        sqlx::query_scalar("SELECT workspaceId FROM agentCanvases WHERE id = ?")
            .bind(canvas_id)
            .fetch_one(self.pool())
            .await
            .map_err(Into::into)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    async fn store() -> (TempDir, RuntimeStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        (dir, store)
    }

    #[tokio::test]
    async fn identity_is_unique_and_revisions_are_conflict_checked() {
        let (_dir, store) = store().await;
        let first = store
            .upsert_agent_canvas_identity("w", "s", Some("t"), "codex", "Run")
            .await
            .unwrap();
        let second = store
            .upsert_agent_canvas_identity("w", "s", Some("t"), "claude", "Other")
            .await
            .unwrap();
        assert_eq!(first.id, second.id);
        let published = store
            .publish_agent_canvas(
                &first.id,
                json!({"components": []}),
                Some(0),
                None,
                None,
                &[],
            )
            .await
            .unwrap();
        assert!(published.changed);
        let coalesced = store
            .publish_agent_canvas(
                &first.id,
                json!({"components": []}),
                Some(1),
                None,
                None,
                &[],
            )
            .await
            .unwrap();
        assert!(!coalesced.changed);
        let conflict = store
            .publish_agent_canvas(
                &first.id,
                json!({"components": [{"type": "Notice"}]}),
                Some(0),
                None,
                None,
                &[],
            )
            .await;
        assert!(conflict.is_err());
    }

    #[tokio::test]
    async fn completed_canvas_is_frozen_and_pinned_close_is_retained() {
        let (_dir, store) = store().await;
        let canvas = store
            .upsert_agent_canvas_identity("w", "s", None, "codex", "Run")
            .await
            .unwrap();
        let completed = store.complete_agent_canvas(&canvas.id).await.unwrap();
        assert!(completed.frozen);
        assert_eq!(completed.state, AgentCanvasState::Completed);
        store
            .set_agent_canvas_pinned(&completed.id, true)
            .await
            .unwrap();
        let closed = store.close_agent_canvas(&completed.id).await.unwrap();
        assert!(closed.expires_at.is_none());
    }

    #[tokio::test]
    async fn invalid_documents_preserve_the_last_valid_revision() {
        let (_dir, store) = store().await;
        let canvas = store
            .upsert_agent_canvas_identity("w", "s", None, "codex", "Run")
            .await
            .unwrap();
        let unsupported = store
            .publish_agent_canvas(
                &canvas.id,
                json!({"version": 1, "components": [{"type": "Unknown"}]}),
                Some(0),
                None,
                None,
                &[],
            )
            .await;
        assert!(unsupported.is_err());
        let wrong_version = store
            .publish_agent_canvas(
                &canvas.id,
                json!({"version": 2, "components": []}),
                Some(0),
                None,
                None,
                &[],
            )
            .await;
        assert!(wrong_version.is_err());
        let current = store.find_agent_canvas(&canvas.id).await.unwrap().unwrap();
        assert_eq!(current.revision, 0);
        assert_eq!(current.document, json!({}));
    }

    #[tokio::test]
    async fn session_exit_orphans_active_canvases_and_retains_history() {
        let (_dir, store) = store().await;
        let canvas = store
            .upsert_agent_canvas_identity("w", "s", None, "codex", "Run")
            .await
            .unwrap();
        let orphaned = store.orphan_agent_canvas_for_session("s").await.unwrap();
        assert_eq!(orphaned.len(), 1);
        assert_eq!(orphaned[0].state, AgentCanvasState::Orphaned);
        assert!(orphaned[0].frozen);
        assert!(orphaned[0].expires_at.is_some());
        let history = store.list_agent_canvases("w", true).await.unwrap();
        assert_eq!(history[0].id, canvas.id);
    }
}
