use serde_json::{json, Value};

use super::ServerActor;

pub(super) struct OwnedSpawnMetadata {
    pub(super) task_id: String,
    pub(super) pending_readiness: bool,
    pub(super) keep_on_failure: bool,
    pub(super) startup_failure_recorded: bool,
}

impl ServerActor {
    pub(super) async fn owned_spawn_metadata(
        &self,
        session_id: &str,
    ) -> Option<OwnedSpawnMetadata> {
        let tab_id = self
            .sessions
            .get(session_id)
            .map(|session| session.tab_id.as_str())?;
        let tab = self.runtime_store.find_workspace_tab(tab_id).await.ok()??;
        let spawn = tab.payload.get("orchestrationSpawn")?;
        if spawn.get("owned").and_then(Value::as_bool) != Some(true) {
            return None;
        }
        let task_id = spawn.get("task").and_then(Value::as_str)?.to_string();
        let pending_readiness = tab
            .payload
            .pointer("/pendingOrchestration/task")
            .and_then(Value::as_str)
            == Some(task_id.as_str());
        Some(OwnedSpawnMetadata {
            task_id,
            pending_readiness,
            keep_on_failure: spawn
                .get("keepOnFailure")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            startup_failure_recorded: spawn
                .get("startupFailureRecorded")
                .and_then(Value::as_bool)
                .unwrap_or(false),
        })
    }

    pub(super) async fn is_owned_orchestration_spawn(
        &self,
        session_id: &str,
        task_id: &str,
    ) -> bool {
        self.owned_spawn_metadata(session_id)
            .await
            .is_some_and(|metadata| metadata.task_id == task_id)
    }

    pub(super) async fn consume_owned_spawn_metadata(&mut self, session_id: &str) {
        let tab_id = self
            .sessions
            .get(session_id)
            .map(|session| session.tab_id.clone())
            .unwrap_or_else(|| session_id.to_string());
        let tab = match self.runtime_store.find_workspace_tab(&tab_id).await {
            Ok(Some(tab)) => tab,
            Ok(None) => return,
            Err(error) => {
                eprintln!(
                    "failed to inspect orchestration spawn tab {tab_id} after acceptance: {error}"
                );
                return;
            }
        };
        let owned = tab
            .payload
            .pointer("/orchestrationSpawn/owned")
            .and_then(Value::as_bool)
            == Some(true);
        if !owned {
            return;
        }
        let mut updated = tab;
        if let Some(payload) = updated.payload.as_object_mut() {
            payload.remove("initialPrompt");
            payload.remove("orchestrationSpawn");
        }
        updated.updated_at = chrono::Utc::now();
        if let Err(error) = self.runtime_store.upsert_workspace_tab(updated).await {
            eprintln!("failed to consume orchestration spawn prompt for tab {tab_id}: {error}");
            return;
        }
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "workspaceTabsChanged",
            json!({}),
        ));
    }

    pub(super) async fn should_keep_failed_owned_spawn(&self, session_id: &str) -> bool {
        let Some(metadata) = self.owned_spawn_metadata(session_id).await else {
            return false;
        };
        if !metadata.keep_on_failure {
            return false;
        }
        if metadata.startup_failure_recorded {
            return true;
        }
        let Ok(dispatch) = self
            .runtime_store
            .active_orchestration_dispatch_for_handle(session_id)
            .await
        else {
            return false;
        };
        match dispatch {
            Some(dispatch) => {
                dispatch.status
                    == alera_core::runtime::OrchestrationDispatchStatus::AwaitingAcceptance
                    && dispatch.task_id == metadata.task_id
            }
            None => metadata.pending_readiness,
        }
    }

    pub(super) async fn mark_owned_spawn_failure(
        &mut self,
        session_id: &str,
        reason: &str,
    ) -> bool {
        let Some(tab_id) = self
            .sessions
            .get(session_id)
            .map(|session| session.tab_id.clone())
        else {
            return false;
        };
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(&tab_id).await else {
            return false;
        };
        let Some(payload) = tab.payload.as_object_mut() else {
            return false;
        };
        payload.remove("pendingOrchestration");
        let Some(spawn) = payload
            .get_mut("orchestrationSpawn")
            .and_then(Value::as_object_mut)
        else {
            return false;
        };
        spawn.insert("startupFailureRecorded".to_string(), Value::Bool(true));
        spawn.insert(
            "startupFailureReason".to_string(),
            Value::String(reason.to_string()),
        );
        tab.updated_at = chrono::Utc::now();
        if let Err(error) = self.runtime_store.upsert_workspace_tab(tab).await {
            eprintln!("failed to persist orchestration spawn failure for tab {tab_id}: {error}");
            return false;
        }
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "workspaceTabsChanged",
            json!({}),
        ));
        true
    }

    pub(super) async fn make_failed_owned_spawn_inert(&mut self, session_id: &str) -> bool {
        let Some(tab_id) = self
            .sessions
            .get(session_id)
            .map(|session| session.tab_id.clone())
        else {
            return false;
        };
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(&tab_id).await else {
            return false;
        };
        let Some(payload) = tab.payload.as_object_mut() else {
            return false;
        };
        payload.insert("spawnOnCreate".to_string(), Value::Bool(false));
        payload.remove("initialPrompt");
        payload.remove("pendingOrchestration");
        payload.remove("orchestrationPreflight");
        let Some(spawn) = payload
            .get_mut("orchestrationSpawn")
            .and_then(Value::as_object_mut)
        else {
            return false;
        };
        spawn.insert("startupFailureRecorded".to_string(), Value::Bool(true));
        spawn.insert("retainedAfterFailure".to_string(), Value::Bool(true));
        tab.updated_at = chrono::Utc::now();
        if let Err(error) = self.runtime_store.upsert_workspace_tab(tab).await {
            eprintln!(
                "failed to preserve orchestration spawn diagnostics for tab {tab_id}: {error}"
            );
            return false;
        }
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "workspaceTabsChanged",
            json!({}),
        ));
        true
    }
}
