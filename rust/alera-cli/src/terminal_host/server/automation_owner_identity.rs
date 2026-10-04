use super::ServerActor;
use crate::process_identity::{ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe};
use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::{json, Value};

impl ServerActor {
    pub(super) async fn bind_automation_terminal_before_spawn(
        &self,
        tab: &alera_core::runtime::WorkspaceTabRecord,
    ) -> HostResult<()> {
        if tab.payload["automationOwned"] != true {
            return Ok(());
        }
        let Some(profile) = super::terminal_startup_commands::agent_profile_id(tab) else {
            return Ok(());
        };
        let Some(id) = tab.payload["automationRunId"].as_str() else {
            return Ok(());
        };
        let mut run = self
            .runtime_store
            .find_automation_run(id)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .ok_or_else(|| HostError::state("Automation run is missing"))?;
        if run.status.is_final()
            || run.attempt_id.as_deref() != tab.payload["automationAttemptId"].as_str()
        {
            return Err(HostError::state("Automation launch was superseded"));
        }
        let session =
            super::requests::terminal_session_id_from_tab(tab).unwrap_or_else(|| tab.id.clone());
        run.workspace_id = Some(tab.workspace_id.clone());
        run.tab_id = Some(tab.id.clone());
        run.session_id = Some(session.clone());
        run.owned_tab = true;
        run.actor_kind = Some(alera_core::runtime::AutomationActorKind::ManagedAgent);
        run.actor_id = Some(profile.into());
        run.target_identity = Some(alera_core::runtime::AutomationTargetIdentity {
            workspace_id: run.workspace_id.clone(),
            tab_id: run.tab_id.clone(),
            session_id: run.session_id.clone(),
            profile_id: run.actor_id.clone(),
            conversation_id: tab.payload["conversationId"].as_str().map(str::to_string),
            terminal_handle: Some(session),
        });
        self.runtime_store
            .save_automation_run(&run)
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        self.runtime_store
            .bind_automation_attempt(&run, "initial")
            .await
            .map_err(|e| HostError::state(e.to_string()))
    }

    pub(super) async fn automation_target_is_reserved(
        &self,
        definition: &alera_core::runtime::AutomationDefinition,
        except_run: &str,
    ) -> bool {
        let Ok(location) = self.automation_target_location(definition).await else {
            return false;
        };
        for run in self
            .runtime_store
            .reserved_automation_runs()
            .await
            .unwrap_or_default()
        {
            if run.id == except_run || run.taken_over {
                continue;
            }
            if let Some(workspace) = run.workspace_id.as_deref() {
                if self
                    .runtime_store
                    .find_workspace(workspace)
                    .await
                    .ok()
                    .flatten()
                    .is_some_and(|w| w.host_id == location.host_id && w.path == location.path)
                {
                    return true;
                }
            }
            if let Some(snapshot) = run.definition_snapshot.as_ref() {
                if self
                    .automation_target_location(snapshot)
                    .await
                    .ok()
                    .is_some_and(|owner| {
                        owner.host_id == location.host_id && owner.path == location.path
                    })
                {
                    return true;
                }
            }
        }
        false
    }

    pub(super) async fn record_terminal_owner_intent(
        &self,
        session: &str,
        workspace: &str,
        tab: &str,
    ) -> HostResult<()> {
        let boot = tokio::task::spawn_blocking(crate::relocation_setup_process::current_boot_id)
            .await
            .ok()
            .and_then(Result::ok)
            .flatten();
        self.runtime_store
            .set_metadata(
                &format!("automation.owner.{session}"),
                &json!({"workspaceId":workspace,"tabId":tab,"bootId":boot,"launching":true})
                    .to_string(),
            )
            .await
            .map_err(|e| HostError::state(e.to_string()))
    }

    pub(super) async fn record_terminal_owner_process(&self, session_id: &str) {
        let Some(session) = self.sessions.get(session_id) else {
            return;
        };
        let Some(pid) = session.shell().map(|s| s.pid) else {
            return;
        };
        let identity =
            tokio::task::spawn_blocking(move || match SystemProcessIdentityProbe.lookup(pid) {
                ProcessLookup::Live(id) => Some(id),
                _ => None,
            })
            .await
            .ok()
            .flatten();
        let key = format!("automation.owner.{session_id}");
        let Some(mut record) = self
            .runtime_store
            .get_metadata(&key)
            .await
            .ok()
            .flatten()
            .and_then(|s| serde_json::from_str::<Value>(&s).ok())
        else {
            return;
        };
        record["pid"] = json!(identity.as_ref().map(|i| i.pid));
        record["startMarker"] = json!(identity.map(|i| i.start_marker));
        record["launching"] = json!(false);
        let _ = self
            .runtime_store
            .set_metadata(&key, &record.to_string())
            .await;
    }

    pub(super) async fn automation_owner_status(&self, payload: &Value) -> HostResult<Value> {
        let session_id = super::requests::require_string_key(payload, "sessionId")?;
        let workspace = super::requests::require_string_key(payload, "workspaceId")?;
        let tab = super::requests::require_string_key(payload, "tabId")?;
        if let Some(session) = self.sessions.get(&session_id) {
            if session.workspace_id != workspace || session.tab_id != tab {
                return Err(HostError::state("Owner identity changed"));
            }
            return Ok(json!({"state":if session.running() {"running"} else {"exited"}}));
        }
        let record = self
            .runtime_store
            .get_metadata(&format!("automation.owner.{session_id}"))
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .and_then(|s| serde_json::from_str::<Value>(&s).ok());
        let Some(record) = record else {
            return Ok(json!({"state":"unknown"}));
        };
        if record["workspaceId"] != workspace || record["tabId"] != tab {
            return Err(HostError::state("Persisted owner identity changed"));
        }
        let state = tokio::task::spawn_blocking(move || {
            let boot = crate::relocation_setup_process::current_boot_id()
                .ok()
                .flatten();
            if record["bootId"]
                .as_str()
                .zip(boot.as_deref())
                .is_some_and(|(old, new)| old != new)
            {
                return "exited";
            }
            let Some((pid, marker)) = record["pid"].as_u64().zip(record["startMarker"].as_u64())
            else {
                return "unknown";
            };
            match SystemProcessIdentityProbe.lookup(pid as u32) {
                ProcessLookup::Live(id) if id.start_marker == marker => "running",
                ProcessLookup::Live(_) | ProcessLookup::Exited => "exited",
                ProcessLookup::Unknown(_) => "unknown",
            }
        })
        .await
        .unwrap_or("unknown");
        Ok(json!({"state":state}))
    }
}
