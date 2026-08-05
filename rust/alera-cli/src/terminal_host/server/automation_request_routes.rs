use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

impl ServerActor {
    pub(super) async fn handle_automation_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_request_allowed(client_id, request_type)?;
        match request_type {
            "automation.list" => self.automation_list_request(payload).await,
            "automation.show" => self.automation_show_request(payload).await,
            "automation.upsert" => {
                self.automation_upsert_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.approve" => {
                self.automation_approve_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.pause" => {
                self.automation_state_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                    alera_core::runtime::AutomationState::Paused,
                )
                .await
            }
            "automation.resume" => {
                self.automation_state_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                    alera_core::runtime::AutomationState::Active,
                )
                .await
            }
            "automation.trash" => {
                self.automation_state_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                    alera_core::runtime::AutomationState::Trashed,
                )
                .await
            }
            "automation.restore" => {
                self.automation_state_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                    alera_core::runtime::AutomationState::Draft,
                )
                .await
            }
            "automation.purge" => {
                let retention_days = self
                    .runtime_store
                    .automation_settings()
                    .await
                    .map(|settings| settings.trash_retention_days)
                    .unwrap_or(30);
                let before = Utc::now() - chrono::Duration::days(retention_days.max(1));
                let purged = self
                    .runtime_store
                    .purge_trashed_automations(before)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                Ok(json!({ "purged": purged }))
            }
            "automation.runNow" => {
                self.run_automation_now(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.runs" => self.automation_runs_request(payload).await,
            "automation.runShow" => self.automation_run_show_request(payload).await,
            "automation.context" => {
                self.automation_context_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.heartbeat" => {
                self.automation_heartbeat_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.wait" => {
                self.automation_wait_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.extend" => {
                self.automation_extend_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.complete" => {
                self.automation_complete_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.cancel" => {
                self.automation_cancel_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.templates" => self.automation_templates_request(payload).await,
            "automation.tags" => {
                self.automation_tags_request(
                    client_id,
                    payload,
                    self.automation_actor(client_id, payload),
                )
                .await
            }
            "automation.export" => {
                let actor = self
                    .resolve_policy_actor(
                        client_id,
                        payload,
                        self.automation_actor(client_id, payload),
                    )
                    .await?;
                self.automation_export_request(actor).await
            }
            "automation.import" => {
                let actor = self
                    .resolve_policy_actor(
                        client_id,
                        payload,
                        self.automation_actor(client_id, payload),
                    )
                    .await?;
                self.automation_import_request(payload, actor).await
            }
            "automation.policy" => {
                self.automation_policy_request(
                    client_id,
                    payload,
                    &self.automation_actor(client_id, payload),
                )
                .await
            }
            _ => Err(HostError::state(format!(
                "Unknown terminal host request: {request_type}"
            ))),
        }
    }
}
