//! Deferred `workspace.createManaged` and `workspace.runSetup` handling.
//!
//! Both spawn onto a task rather than running on the actor loop: creating a
//! worktree shells out to `git`, and a copy rule may name a large directory.
//! Split out of `requests.rs`, which keeps the request dispatch itself.

use serde_json::Value;

use crate::managed_workspace::{
    create_managed_workspace, measure_workspace_storage, workspace_has_active_automation_owner,
    ManagedWorkspaceCreateRequest,
};
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::protocol::{error_response, ok_response};
use crate::worktree_setup::run_workspace_setup;

use super::requests::json_result;
use super::runtime_change_broadcasts::string_scope;
use super::{ServerActor, ServerCommand};

impl ServerActor {
    pub(super) fn start_workspace_storage_measurement(
        &mut self,
        client_id: u64,
        request_id: i64,
        workspace_id: String,
        active_workspace_id: Option<String>,
    ) {
        let mut blockers = Vec::new();
        if active_workspace_id.as_deref() == Some(workspace_id.as_str()) {
            blockers.push("Workspace is active in the workbench".to_string());
        }
        if self
            .sessions
            .values()
            .any(|session| session.workspace_id == workspace_id && session.running())
        {
            blockers.push("Workspace has a live terminal session or process".to_string());
        }
        if self.browser.has_pages_for_workspace(&workspace_id) {
            blockers.push("Workspace has a live browser session".to_string());
        }
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            match workspace_has_active_automation_owner(&store, &workspace_id).await {
                Ok(true) => blockers.push("Workspace is owned by an active automation".to_string()),
                Err(error) => blockers.push(format!("Could not verify automations: {error}")),
                _ => {}
            }
            let result =
                json_result(measure_workspace_storage(&store, &workspace_id, blockers).await);
            let _ = inbox.send(ServerCommand::WorkspaceStorageMeasured {
                client_id,
                request_id,
                result,
            });
        });
    }

    pub(super) fn handle_workspace_storage_measured(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        match result {
            Ok(payload) => self.client_write(client_id, ok_response(request_id, payload)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
        self.schedule_shutdown_if_idle();
    }

    /// Where deferred setup scripts are written: next to the control file, the
    /// host's own on-disk state, so a sweep at startup can clear leftovers.
    pub(super) fn setup_script_directory(&self) -> Option<std::path::PathBuf> {
        self.control_file_path
            .parent()
            .map(std::path::Path::to_path_buf)
    }

    pub(super) fn start_workspace_setup(
        &mut self,
        client_id: u64,
        request_id: i64,
        workspace_id: String,
        copies_only: bool,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        // The copy rules are synchronous filesystem work and a rule may name a
        // large directory, so they stay off the actor loop.
        tokio::spawn(async move {
            let result = json_result(run_workspace_setup(&store, &workspace_id, copies_only).await);
            let _ = inbox.send(ServerCommand::WorkspaceSetupFinished {
                client_id,
                request_id,
                result,
            });
        });
    }

    pub(super) fn start_managed_workspace_create(
        &mut self,
        client_id: u64,
        request_id: i64,
        request: ManagedWorkspaceCreateRequest,
    ) {
        self.managed_workspace_jobs += 1;
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = json_result(create_managed_workspace(&store, request).await);
            let _ = inbox.send(ServerCommand::ManagedWorkspaceCreated {
                client_id,
                request_id,
                result,
            });
        });
    }

    /// Copy rules only touch the filesystem, so nothing in the runtime store
    /// changed and no watcher needs waking.
    pub(super) async fn handle_workspace_setup_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        match result {
            Ok(payload) => self.client_write(client_id, ok_response(request_id, payload)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn handle_managed_workspace_created(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
        match result {
            Ok(payload) => {
                let project_id = string_scope(&payload, "projectId");
                self.client_write(client_id, ok_response(request_id, payload));
                self.broadcast_workspaces_changed(project_id.as_deref());
            }
            Err(error) => {
                self.client_write(client_id, error_response(request_id, &error));
            }
        }
        self.schedule_shutdown_if_idle();
    }
}
