use anyhow::Result;
use chrono::{DateTime, Utc};
use serde_json::Value;
use sqlx::Row;

use super::store::{format_timestamp, parse_timestamp};
use super::RuntimeStore;

/// One native agent conversation observed in a workspace. Tab payloads only
/// keep the conversation a tab currently resumes, and a tab record disappears
/// when it closes or its process exits, so this ledger is what still knows
/// every conversation that ran in the workspace when the workspace goes away.
#[derive(Debug, Clone, PartialEq)]
pub struct AgentNativeSessionRecord {
    pub workspace_id: String,
    pub agent_type: String,
    pub session_id: String,
    pub ccs_profile: Option<String>,
    pub cwd: Option<String>,
    pub tab_id: Option<String>,
    pub settings: Option<Value>,
    pub first_seen_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
}

impl RuntimeStore {
    pub(super) async fn migrate_agent_native_sessions(&self) -> Result<()> {
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS agentNativeSessions (\
             workspaceId TEXT NOT NULL, agentType TEXT NOT NULL, sessionId TEXT NOT NULL, \
             ccsProfile TEXT, cwd TEXT, tabId TEXT, settingsJson TEXT, \
             firstSeenAt TEXT NOT NULL, lastSeenAt TEXT NOT NULL, \
             PRIMARY KEY(workspaceId, agentType, sessionId))",
        )
        .execute(self.pool())
        .await?;
        // Tabs bound before the ledger existed seed it, so their conversations
        // are known when their workspace is removed.
        sqlx::query(
            "INSERT OR IGNORE INTO agentNativeSessions \
             (workspaceId, agentType, sessionId, ccsProfile, cwd, tabId, settingsJson, firstSeenAt, lastSeenAt) \
             SELECT workspaceId, json_extract(payloadJson, '$.agentNativeSessionAgent'), \
             json_extract(payloadJson, '$.agentNativeSessionId'), \
             json_extract(payloadJson, '$.agentNativeCcsProfile'), NULL, id, \
             json_extract(payloadJson, '$.agentNativeSessionSettings'), createdAt, updatedAt \
             FROM workspaceTabs WHERE json_valid(payloadJson) \
             AND json_type(payloadJson, '$.agentNativeSessionId') = 'text' \
             AND json_type(payloadJson, '$.agentNativeSessionAgent') = 'text'",
        )
        .execute(self.pool())
        .await?;
        Ok(())
    }

    /// Inserts or refreshes a conversation. Absent optional fields keep the
    /// stored value, because hooks report them unevenly from event to event.
    pub async fn record_agent_native_session(
        &self,
        record: &AgentNativeSessionRecord,
    ) -> Result<()> {
        let settings = record
            .settings
            .as_ref()
            .map(serde_json::to_string)
            .transpose()?;
        sqlx::query(
            "INSERT INTO agentNativeSessions \
             (workspaceId, agentType, sessionId, ccsProfile, cwd, tabId, settingsJson, firstSeenAt, lastSeenAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(workspaceId, agentType, sessionId) DO UPDATE SET \
             ccsProfile = COALESCE(excluded.ccsProfile, ccsProfile), \
             cwd = COALESCE(excluded.cwd, cwd), \
             tabId = COALESCE(excluded.tabId, tabId), \
             settingsJson = COALESCE(excluded.settingsJson, settingsJson), \
             lastSeenAt = excluded.lastSeenAt",
        )
        .bind(&record.workspace_id)
        .bind(&record.agent_type)
        .bind(&record.session_id)
        .bind(&record.ccs_profile)
        .bind(&record.cwd)
        .bind(&record.tab_id)
        .bind(settings)
        .bind(format_timestamp(record.first_seen_at))
        .bind(format_timestamp(record.last_seen_at))
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn list_agent_native_sessions(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<AgentNativeSessionRecord>> {
        let rows = sqlx::query(
            "SELECT workspaceId, agentType, sessionId, ccsProfile, cwd, tabId, settingsJson, firstSeenAt, lastSeenAt \
             FROM agentNativeSessions WHERE workspaceId = ? ORDER BY firstSeenAt, sessionId",
        )
        .bind(workspace_id)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter()
            .map(|row| {
                let settings: Option<String> = row.try_get("settingsJson")?;
                Ok(AgentNativeSessionRecord {
                    workspace_id: row.try_get("workspaceId")?,
                    agent_type: row.try_get("agentType")?,
                    session_id: row.try_get("sessionId")?,
                    ccs_profile: row.try_get("ccsProfile")?,
                    cwd: row.try_get("cwd")?,
                    tab_id: row.try_get("tabId")?,
                    settings: settings.as_deref().map(serde_json::from_str).transpose()?,
                    first_seen_at: parse_timestamp(&row.try_get::<String, _>("firstSeenAt")?),
                    last_seen_at: parse_timestamp(&row.try_get::<String, _>("lastSeenAt")?),
                })
            })
            .collect()
    }

    /// Conversations seen in any other workspace that still exists, e.g.
    /// because the user resumed one there. Those are not the removed
    /// workspace's to delete.
    pub async fn agent_native_sessions_outside(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<(String, String)>> {
        let rows = sqlx::query(
            "SELECT DISTINCT s.agentType, s.sessionId FROM agentNativeSessions s \
             JOIN workspaces w ON w.id = s.workspaceId WHERE s.workspaceId <> ?",
        )
        .bind(workspace_id)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter()
            .map(|row| Ok((row.try_get("agentType")?, row.try_get("sessionId")?)))
            .collect()
    }

    /// Drops ledger rows whose workspace no longer exists. Removal paths do
    /// not cascade into the ledger so the host can still read it after the
    /// workspace record is gone.
    pub async fn prune_orphan_agent_native_sessions(&self) -> Result<u64> {
        Ok(sqlx::query(
            "DELETE FROM agentNativeSessions WHERE workspaceId NOT IN (SELECT id FROM workspaces)",
        )
        .execute(self.pool())
        .await?
        .rows_affected())
    }
}

/// Moves ledger rows with the tabs a workspace transfer moves. Rows the
/// destination already has keep the destination's copy.
pub(super) async fn transfer_agent_native_sessions_in(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    source_workspace_id: &str,
    destination_workspace_id: &str,
) -> Result<()> {
    sqlx::query("UPDATE OR IGNORE agentNativeSessions SET workspaceId = ? WHERE workspaceId = ?")
        .bind(destination_workspace_id)
        .bind(source_workspace_id)
        .execute(&mut **tx)
        .await?;
    sqlx::query("DELETE FROM agentNativeSessions WHERE workspaceId = ?")
        .bind(source_workspace_id)
        .execute(&mut **tx)
        .await?;
    Ok(())
}
