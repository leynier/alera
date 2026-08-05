impl RuntimeStore {
    pub async fn list_agent_canvas_events(
        &self,
        workspace_id: &str,
        since: i64,
        limit: i64,
    ) -> Result<Vec<AgentCanvasEvent>> {
        let limit = limit.clamp(1, AGENT_CANVAS_MAX_EVENTS);
        let rows = sqlx::query("SELECT sequence, canvasId, workspaceId, eventType, payloadJson, createdAt FROM agentCanvasEvents WHERE workspaceId = ? AND sequence > ? ORDER BY sequence ASC LIMIT ?")
            .bind(workspace_id).bind(since.max(0)).bind(limit).fetch_all(self.pool()).await?;
        rows.into_iter().map(event_from_row).collect()
    }

    pub async fn resolve_agent_canvas_decision(
        &self,
        decision_id: &str,
        resolution: Value,
    ) -> Result<AgentCanvasDecision> {
        let current = self
            .find_agent_canvas_decision(decision_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas decision not found: {decision_id}"))?;
        if current.state != AgentCanvasDecisionState::Pending {
            return Ok(current);
        }
        let now = format_timestamp(Utc::now());
        sqlx::query("UPDATE agentCanvasDecisions SET state = 'resolved', resolutionJson = ?, resolvedAt = ? WHERE id = ? AND state = 'pending'")
            .bind(serde_json::to_string(&resolution)?).bind(&now).bind(decision_id).execute(self.pool()).await?;
        self.append_event(
            &current.canvas_id,
            &self.canvas_workspace_id(&current.canvas_id).await?,
            "decisionResolved",
            json!({"decisionId": decision_id}),
        )
        .await?;
        self.find_agent_canvas_decision(decision_id)
            .await?
            .ok_or_else(|| anyhow!("Agent Canvas decision disappeared after resolve"))
    }

    pub async fn find_agent_canvas_decision(
        &self,
        decision_id: &str,
    ) -> Result<Option<AgentCanvasDecision>> {
        let row = sqlx::query("SELECT id, canvasId, revision, question, optionsJson, state, resolutionJson, createdAt, resolvedAt, expiresAt FROM agentCanvasDecisions WHERE id = ?")
            .bind(decision_id).fetch_optional(self.pool()).await?;
        row.map(decision_from_row).transpose()
    }

    pub async fn expire_agent_canvas_decisions(&self) -> Result<u64> {
        let now = format_timestamp(Utc::now());
        let rows = sqlx::query("SELECT id, canvasId FROM agentCanvasDecisions WHERE state = 'pending' AND expiresAt IS NOT NULL AND expiresAt <= ?")
            .bind(&now).fetch_all(self.pool()).await?;
        for row in &rows {
            let id: String = row.try_get("id")?;
            let canvas_id: String = row.try_get("canvasId")?;
            sqlx::query("UPDATE agentCanvasDecisions SET state = 'timeout', resolvedAt = ? WHERE id = ? AND state = 'pending'")
                .bind(&now).bind(&id).execute(self.pool()).await?;
            let workspace_id = self.canvas_workspace_id(&canvas_id).await?;
            self.append_event(
                &canvas_id,
                &workspace_id,
                "decisionTimeout",
                json!({"decisionId": id}),
            )
            .await?;
        }
        Ok(rows.len() as u64)
    }
}
