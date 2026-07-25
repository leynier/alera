//! Audited administrative actions. Recovery, ownership transfer, dispatch
//! interruption, and policy decisions all leave a row here with a reason.

use anyhow::Result;

use super::orchestration_message_store::orchestration_id;
use super::RuntimeStore;

impl RuntimeStore {
    pub async fn insert_orchestration_audit_event(
        &self,
        actor_handle: Option<&str>,
        action: &str,
        target_id: &str,
        reason: &str,
    ) -> Result<()> {
        let id = orchestration_id("audit");
        sqlx::query(
            "INSERT INTO orchestrationAuditEvents (id, actor_handle, action, target_id, reason) \
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(id)
        .bind(actor_handle)
        .bind(action)
        .bind(target_id)
        .bind(reason)
        .execute(self.pool())
        .await?;
        Ok(())
    }
}
