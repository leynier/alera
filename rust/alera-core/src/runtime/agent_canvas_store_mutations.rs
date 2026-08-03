impl RuntimeStore {
    pub async fn upsert_agent_canvas_identity(
        &self,
        workspace_id: &str,
        terminal_session_id: &str,
        tab_id: Option<&str>,
        agent_type: &str,
        title: &str,
    ) -> Result<AgentCanvas> {
        require_identity(workspace_id, terminal_session_id)?;
        self.cleanup_agent_canvases().await?;
        let existing = self
            .find_agent_canvas_by_identity(workspace_id, terminal_session_id)
            .await?;
        if let Some(canvas) = existing {
            return Ok(canvas);
        }
        let count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM agentCanvases WHERE workspaceId = ?")
                .bind(workspace_id)
                .fetch_one(self.pool())
                .await?;
        if count >= AGENT_CANVAS_MAX_PER_WORKSPACE {
            bail!(RuntimeStoreError::Message(format!(
                "workspace has reached the Agent Canvas limit of {AGENT_CANVAS_MAX_PER_WORKSPACE}."
            )));
        }
        let id = Uuid::new_v4().to_string();
        let now = format_timestamp(Utc::now());
        sqlx::query(
            "INSERT INTO agentCanvases (id, workspaceId, terminalSessionId, tabId, agentType, title, state, pinned, frozen, revision, documentJson, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, 'live', 0, 0, 0, '{}', ?, ?)",
        )
        .bind(&id)
        .bind(workspace_id)
        .bind(terminal_session_id)
        .bind(tab_id)
        .bind(normalize_text(agent_type, 128, "agent type")?)
        .bind(normalize_text(title, 240, "canvas title")?)
        .bind(&now)
        .bind(&now)
        .execute(self.pool())
        .await?;
        self.append_event(&id, workspace_id, "created", json!({"revision": 0}))
            .await?;
        self.find_agent_canvas(&id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas disappeared after creation"))
    }

    pub async fn publish_agent_canvas(
        &self,
        canvas_id: &str,
        document: Value,
        expected_revision: Option<i64>,
        requested_state: Option<AgentCanvasState>,
        title: Option<&str>,
        decisions: &[AgentCanvasDecisionInput],
    ) -> Result<AgentCanvasPublishResult> {
        validate_document(&document)?;
        if decisions.len() > AGENT_CANVAS_MAX_DECISIONS {
            bail!(RuntimeStoreError::Message(format!(
                "a canvas can publish at most {AGENT_CANVAS_MAX_DECISIONS} decisions per revision."
            )));
        }
        let current = self
            .find_agent_canvas(canvas_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas not found: {canvas_id}"))?;
        if current.frozen || current.state == AgentCanvasState::Completed {
            bail!(RuntimeStoreError::Message(
                "completed or frozen canvases cannot receive new revisions.".to_string(),
            ));
        }
        if let Some(expected) = expected_revision {
            if expected != current.revision {
                bail!(RuntimeStoreError::Message(format!(
                    "Agent Canvas revision conflict: expected {expected}, current {}.",
                    current.revision
                )));
            }
        }
        let document_json = serde_json::to_string(&document)?;
        if document == current.document {
            return Ok(AgentCanvasPublishResult {
                canvas: current,
                changed: false,
            });
        }
        let next_revision = current.revision.saturating_add(1);
        let state = requested_state.unwrap_or(AgentCanvasState::Live);
        if !matches!(state, AgentCanvasState::Waiting | AgentCanvasState::Live) {
            bail!(RuntimeStoreError::Message(
                "publish accepts only waiting or live canvas states.".to_string(),
            ));
        }
        let now = format_timestamp(Utc::now());
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE agentCanvases SET documentJson = ?, revision = ?, state = ?, title = COALESCE(?, title), updatedAt = ? WHERE id = ?",
        )
        .bind(&document_json)
        .bind(next_revision)
        .bind(state.as_str())
        .bind(title.map(|value| normalize_text(value, 240, "canvas title")).transpose()?)
        .bind(&now)
        .bind(canvas_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO agentCanvasRevisions (canvasId, revision, documentJson, semanticHash, createdAt) VALUES (?, ?, ?, ?, ?)",
        )
        .bind(canvas_id)
        .bind(next_revision)
        .bind(&document_json)
        .bind(&document_json)
        .bind(&now)
        .execute(&mut *tx)
        .await?;
        for decision in decisions {
            let decision_id = decision
                .id
                .clone()
                .unwrap_or_else(|| Uuid::new_v4().to_string());
            sqlx::query(
                "INSERT INTO agentCanvasDecisions (id, canvasId, revision, question, optionsJson, state, createdAt, expiresAt) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)",
            )
            .bind(&decision_id)
            .bind(canvas_id)
            .bind(next_revision)
            .bind(normalize_text(&decision.question, 2000, "decision question")?)
            .bind(serde_json::to_string(&decision.options)?)
            .bind(&now)
            .bind(decision.expires_at.as_deref())
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        self.append_event(
            canvas_id,
            &current.workspace_id,
            if decisions.is_empty() {
                "revision"
            } else {
                "decisionRequest"
            },
            json!({"revision": next_revision, "decisionCount": decisions.len()}),
        )
        .await?;
        let canvas = self
            .find_agent_canvas(canvas_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas disappeared after publish"))?;
        Ok(AgentCanvasPublishResult {
            canvas,
            changed: true,
        })
    }

    pub async fn complete_agent_canvas(&self, canvas_id: &str) -> Result<AgentCanvas> {
        let current = self
            .find_agent_canvas(canvas_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas not found: {canvas_id}"))?;
        if matches!(
            current.state,
            AgentCanvasState::Completed | AgentCanvasState::Closed
        ) {
            return Ok(current);
        }
        let now = format_timestamp(Utc::now());
        let expires = if current.pinned {
            None
        } else {
            Some(format_timestamp(
                Utc::now() + Duration::hours(AGENT_CANVAS_RETENTION_HOURS),
            ))
        };
        sqlx::query(
            "UPDATE agentCanvases SET state = 'completed', frozen = 1, finalRevision = revision, completedAt = ?, expiresAt = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(&now)
        .bind(&expires)
        .bind(&now)
        .bind(canvas_id)
        .execute(self.pool())
        .await?;
        self.append_event(
            canvas_id,
            &current.workspace_id,
            "completed",
            json!({"revision": current.revision}),
        )
        .await?;
        self.find_agent_canvas(canvas_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas disappeared after completion"))
    }

    pub async fn close_agent_canvas(&self, canvas_id: &str) -> Result<AgentCanvas> {
        let current = self
            .find_agent_canvas(canvas_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas not found: {canvas_id}"))?;
        if matches!(
            current.state,
            AgentCanvasState::Completed | AgentCanvasState::Closed
        ) {
            return Ok(current);
        }
        let now = format_timestamp(Utc::now());
        let expires = if current.pinned {
            None
        } else {
            Some(format_timestamp(
                Utc::now() + Duration::hours(AGENT_CANVAS_RETENTION_HOURS),
            ))
        };
        sqlx::query(
            "UPDATE agentCanvases SET state = 'closed', frozen = 1, expiresAt = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(&expires)
        .bind(&now)
        .bind(canvas_id)
        .execute(self.pool())
        .await?;
        self.append_event(canvas_id, &current.workspace_id, "closed", json!({}))
            .await?;
        self.find_agent_canvas(canvas_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas disappeared after close"))
    }

    pub async fn orphan_agent_canvas_for_session(
        &self,
        terminal_session_id: &str,
    ) -> Result<Vec<AgentCanvas>> {
        let now = format_timestamp(Utc::now());
        let expires = format_timestamp(Utc::now() + Duration::hours(AGENT_CANVAS_RETENTION_HOURS));
        let rows = sqlx::query(
            "SELECT id, workspaceId FROM agentCanvases WHERE terminalSessionId = ? AND state IN ('waiting', 'live')",
        )
        .bind(terminal_session_id)
        .fetch_all(self.pool())
        .await?;
        let mut orphaned = Vec::with_capacity(rows.len());
        for row in &rows {
            let id: String = row.try_get("id")?;
            let workspace_id: String = row.try_get("workspaceId")?;
            sqlx::query("UPDATE agentCanvases SET state = 'orphaned', frozen = 1, expiresAt = CASE WHEN pinned = 1 THEN NULL ELSE ? END, updatedAt = ? WHERE id = ?")
                .bind(&expires).bind(&now).bind(&id).execute(self.pool()).await?;
            self.append_event(&id, &workspace_id, "orphaned", json!({}))
                .await?;
            if let Some(canvas) = self.find_agent_canvas(&id).await? {
                orphaned.push(canvas);
            }
        }
        Ok(orphaned)
    }

    pub async fn set_agent_canvas_pinned(
        &self,
        canvas_id: &str,
        pinned: bool,
    ) -> Result<AgentCanvas> {
        let current = self
            .find_agent_canvas(canvas_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas not found: {canvas_id}"))?;
        let expires = if pinned || !current.state.is_history() {
            None
        } else {
            Some(format_timestamp(
                Utc::now() + Duration::hours(AGENT_CANVAS_RETENTION_HOURS),
            ))
        };
        sqlx::query(
            "UPDATE agentCanvases SET pinned = ?, expiresAt = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(if pinned { 1_i64 } else { 0_i64 })
        .bind(expires)
        .bind(format_timestamp(Utc::now()))
        .bind(canvas_id)
        .execute(self.pool())
        .await?;
        self.append_event(
            canvas_id,
            &current.workspace_id,
            if pinned { "pinned" } else { "unpinned" },
            json!({}),
        )
        .await?;
        self.find_agent_canvas(canvas_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas disappeared after pin update"))
    }

    pub async fn remove_agent_canvas(&self, canvas_id: &str) -> Result<bool> {
        let Some(current) = self.find_agent_canvas(canvas_id).await? else {
            return Ok(false);
        };
        if current.pinned {
            bail!(RuntimeStoreError::Message(
                "pinned Agent Canvases must be unpinned before removal.".to_string()
            ));
        }
        let mut tx = self.pool().begin().await?;
        delete_canvas_children(&mut tx, canvas_id).await?;
        let result = sqlx::query("DELETE FROM agentCanvases WHERE id = ?")
            .bind(canvas_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        self.append_event(canvas_id, &current.workspace_id, "removed", json!({}))
            .await?;
        Ok(result.rows_affected() == 1)
    }
}
