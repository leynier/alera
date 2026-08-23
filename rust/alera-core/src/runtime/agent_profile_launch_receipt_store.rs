use anyhow::Result;
use chrono::{Duration, Utc};
use serde_json::Value;
use sqlx::Row;

use super::{format_timestamp, RuntimeStore, WorkspaceTabRecord};

pub const AGENT_PROFILE_LAUNCH_RECEIPT_RETENTION_DAYS: i64 = 7;
pub const AGENT_PROFILE_LAUNCH_RECEIPT_CAPACITY_PER_SCOPE_WORKSPACE: i64 = 256;
pub const AGENT_PROFILE_LAUNCH_RECEIPT_GLOBAL_CAPACITY: i64 = 4096;

#[derive(Debug, PartialEq)]
pub enum AgentProfileLaunchReceiptOutcome {
    Created,
    Replay(Value),
    Conflict,
}

impl RuntimeStore {
    pub async fn remove_workspace_tab(&self, tab_id: &str) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("DELETE FROM workspaceTabs WHERE id = ?")
            .bind(tab_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM agentProfileLaunchReceipts WHERE tabId = ?")
            .bind(tab_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn find_agent_profile_launch_receipt(
        &self,
        caller_scope: &str,
        workspace_id: &str,
        client_mutation_id: &str,
        payload_digest: &str,
    ) -> Result<Option<AgentProfileLaunchReceiptOutcome>> {
        let cutoff = format_timestamp(
            Utc::now() - Duration::days(AGENT_PROFILE_LAUNCH_RECEIPT_RETENTION_DAYS),
        );
        sqlx::query("DELETE FROM agentProfileLaunchReceipts WHERE createdAt < ?")
            .bind(cutoff)
            .execute(self.pool())
            .await?;
        let existing = sqlx::query(
            "SELECT payloadDigest, tabId, resultJson FROM agentProfileLaunchReceipts \
             WHERE callerScope = ? AND workspaceId = ? AND clientMutationId = ?",
        )
        .bind(caller_scope)
        .bind(workspace_id)
        .bind(client_mutation_id)
        .fetch_optional(self.pool())
        .await?;
        let Some(existing) = existing else {
            return Ok(None);
        };
        let tab_id: String = existing.try_get("tabId")?;
        let tab_exists: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workspaceTabs WHERE id = ?)")
                .bind(&tab_id)
                .fetch_one(self.pool())
                .await?;
        if !tab_exists {
            sqlx::query(
                "DELETE FROM agentProfileLaunchReceipts \
                 WHERE callerScope = ? AND workspaceId = ? AND clientMutationId = ?",
            )
            .bind(caller_scope)
            .bind(workspace_id)
            .bind(client_mutation_id)
            .execute(self.pool())
            .await?;
            return Ok(None);
        }
        let existing_digest: String = existing.try_get("payloadDigest")?;
        if existing_digest != payload_digest {
            return Ok(Some(AgentProfileLaunchReceiptOutcome::Conflict));
        }
        let result_json: String = existing.try_get("resultJson")?;
        Ok(Some(AgentProfileLaunchReceiptOutcome::Replay(
            serde_json::from_str(&result_json)?,
        )))
    }

    /// Atomically records both the new tab and its mutation receipt. The host
    /// may safely spawn after this commits: a crash in between is recovered by
    /// normal spawn-on-create reconciliation.
    pub async fn record_agent_profile_launch(
        &self,
        caller_scope: &str,
        workspace_id: &str,
        client_mutation_id: &str,
        payload_digest: &str,
        result: &Value,
        tab: &WorkspaceTabRecord,
    ) -> Result<AgentProfileLaunchReceiptOutcome> {
        let mut tx = self.pool().begin().await?;
        let cutoff = format_timestamp(
            Utc::now() - Duration::days(AGENT_PROFILE_LAUNCH_RECEIPT_RETENTION_DAYS),
        );
        sqlx::query("DELETE FROM agentProfileLaunchReceipts WHERE createdAt < ?")
            .bind(cutoff)
            .execute(&mut *tx)
            .await?;

        let existing = sqlx::query(
            "SELECT payloadDigest, resultJson FROM agentProfileLaunchReceipts \
             WHERE callerScope = ? AND workspaceId = ? AND clientMutationId = ?",
        )
        .bind(caller_scope)
        .bind(workspace_id)
        .bind(client_mutation_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(existing) = existing {
            let existing_digest: String = existing.try_get("payloadDigest")?;
            if existing_digest != payload_digest {
                tx.commit().await?;
                return Ok(AgentProfileLaunchReceiptOutcome::Conflict);
            }
            let result_json: String = existing.try_get("resultJson")?;
            tx.commit().await?;
            return Ok(AgentProfileLaunchReceiptOutcome::Replay(
                serde_json::from_str(&result_json)?,
            ));
        }

        sqlx::query(
            "INSERT INTO workspaceTabs (id, workspaceId, kind, title, createdAt, updatedAt, payloadJson) \
             VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&tab.id)
        .bind(&tab.workspace_id)
        .bind(&tab.kind)
        .bind(&tab.title)
        .bind(format_timestamp(tab.created_at))
        .bind(format_timestamp(tab.updated_at))
        .bind(serde_json::to_string(&tab.payload)?)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO agentProfileLaunchReceipts \
             (callerScope, workspaceId, clientMutationId, payloadDigest, tabId, resultJson, createdAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(caller_scope)
        .bind(workspace_id)
        .bind(client_mutation_id)
        .bind(payload_digest)
        .bind(&tab.id)
        .bind(serde_json::to_string(result)?)
        .bind(format_timestamp(Utc::now()))
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "DELETE FROM agentProfileLaunchReceipts WHERE rowid IN (\
               SELECT rowid FROM agentProfileLaunchReceipts \
               WHERE callerScope = ? AND workspaceId = ? \
               ORDER BY createdAt DESC, rowid DESC LIMIT -1 OFFSET ?\
             )",
        )
        .bind(caller_scope)
        .bind(workspace_id)
        .bind(AGENT_PROFILE_LAUNCH_RECEIPT_CAPACITY_PER_SCOPE_WORKSPACE)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "DELETE FROM agentProfileLaunchReceipts WHERE rowid IN (\
               SELECT rowid FROM agentProfileLaunchReceipts \
               ORDER BY createdAt DESC, rowid DESC LIMIT -1 OFFSET ?\
             )",
        )
        .bind(AGENT_PROFILE_LAUNCH_RECEIPT_GLOBAL_CAPACITY)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(AgentProfileLaunchReceiptOutcome::Created)
    }
}
