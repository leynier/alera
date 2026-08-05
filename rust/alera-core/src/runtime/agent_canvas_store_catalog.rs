impl RuntimeStore {
    pub async fn cleanup_agent_canvases(&self) -> Result<u64> {
        let now = format_timestamp(Utc::now());
        let ids = sqlx::query(
            "SELECT id FROM agentCanvases WHERE pinned = 0 AND expiresAt IS NOT NULL AND expiresAt <= ?",
        )
        .bind(&now)
        .fetch_all(self.pool())
        .await?;
        if ids.is_empty() {
            return Ok(0);
        }
        let mut tx = self.pool().begin().await?;
        let count = ids.len() as u64;
        for row in ids {
            let id: String = row.try_get("id")?;
            delete_canvas_children(&mut tx, &id).await?;
            sqlx::query("DELETE FROM agentCanvases WHERE id = ?")
                .bind(id)
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await?;
        Ok(count)
    }

    pub async fn list_agent_canvases(
        &self,
        workspace_id: &str,
        include_history: bool,
    ) -> Result<Vec<AgentCanvas>> {
        self.cleanup_agent_canvases().await?;
        let query = if include_history {
            format!("SELECT {CANVAS_COLUMNS} FROM agentCanvases WHERE workspaceId = ? ORDER BY pinned DESC, CASE state WHEN 'waiting' THEN 0 WHEN 'live' THEN 1 ELSE 2 END, updatedAt DESC")
        } else {
            format!("SELECT {CANVAS_COLUMNS} FROM agentCanvases WHERE workspaceId = ? AND state IN ('waiting', 'live') ORDER BY pinned DESC, updatedAt DESC")
        };
        let rows = sqlx::query(sqlx::AssertSqlSafe(query))
            .bind(workspace_id)
            .fetch_all(self.pool())
            .await?;
        let mut canvases = Vec::with_capacity(rows.len());
        for row in rows {
            canvases.push(self.canvas_from_row(row).await?);
        }
        Ok(canvases)
    }

    pub async fn find_agent_canvas(&self, canvas_id: &str) -> Result<Option<AgentCanvas>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {CANVAS_COLUMNS} FROM agentCanvases WHERE id = ?"
        )))
        .bind(canvas_id)
        .fetch_optional(self.pool())
        .await?;
        match row {
            Some(row) => Ok(Some(self.canvas_from_row(row).await?)),
            None => Ok(None),
        }
    }

    pub async fn find_agent_canvas_by_identity(
        &self,
        workspace_id: &str,
        terminal_session_id: &str,
    ) -> Result<Option<AgentCanvas>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {CANVAS_COLUMNS} FROM agentCanvases WHERE workspaceId = ? AND terminalSessionId = ?"
        )))
        .bind(workspace_id)
        .bind(terminal_session_id)
        .fetch_optional(self.pool())
        .await?;
        match row {
            Some(row) => Ok(Some(self.canvas_from_row(row).await?)),
            None => Ok(None),
        }
    }

    async fn canvas_from_row(&self, row: sqlx::sqlite::SqliteRow) -> Result<AgentCanvas> {
        let id: String = row.try_get("id")?;
        let state_raw: String = row.try_get("state")?;
        let state = AgentCanvasState::parse(&state_raw)
            .ok_or_else(|| anyhow!("invalid Agent Canvas state: {state_raw}"))?;
        let document_json: String = row.try_get("documentJson")?;
        let decisions = sqlx::query("SELECT id, canvasId, revision, question, optionsJson, state, resolutionJson, createdAt, resolvedAt, expiresAt FROM agentCanvasDecisions WHERE canvasId = ? ORDER BY createdAt ASC")
            .bind(&id).fetch_all(self.pool()).await?.into_iter().map(decision_from_row).collect::<Result<Vec<_>>>()?;
        Ok(AgentCanvas {
            id,
            workspace_id: row.try_get("workspaceId")?,
            terminal_session_id: row.try_get("terminalSessionId")?,
            tab_id: row.try_get("tabId")?,
            agent_type: row.try_get("agentType")?,
            title: row.try_get("title")?,
            state,
            pinned: row.try_get::<i64, _>("pinned")? != 0,
            frozen: row.try_get::<i64, _>("frozen")? != 0,
            revision: row.try_get("revision")?,
            final_revision: row.try_get("finalRevision")?,
            document: serde_json::from_str(&document_json).unwrap_or_else(|_| json!({})),
            decisions,
            created_at: row.try_get("createdAt")?,
            updated_at: row.try_get("updatedAt")?,
            completed_at: row.try_get("completedAt")?,
            expires_at: row.try_get("expiresAt")?,
        })
    }
}
