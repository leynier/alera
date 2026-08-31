use alera_core::runtime::{
    ProjectCloneJob, ProjectCloneJobPhase, ProjectCloneJobStatus, ProjectConfig,
};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::project_management::{
    effective_project_config, host_directory_roots, list_host_directory, register_project,
    rename_project, validate_clone_destination,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::{ServerActor, ServerCommand};
use super::project_clone_job::{run_clone_job, sanitized_clone_source};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectRegisterRequest {
    path: String,
    name: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectRenameRequest {
    id: String,
    name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectCloneStartRequest {
    url: String,
    parent_path: String,
    directory_name: String,
    name: Option<String>,
}

impl ServerActor {
    pub(super) async fn project_register_request(&mut self, payload: &Value) -> HostResult<Value> {
        let request: ProjectRegisterRequest = parse(payload)?;
        let result = register_project(&self.runtime_store, &request.path, request.name.as_deref())
            .await
            .map_err(state_error)?;
        self.broadcast_project_state_changed();
        serde_json::to_value(result).map_err(state_error)
    }

    pub(super) async fn project_rename_request(&mut self, payload: &Value) -> HostResult<Value> {
        let request: ProjectRenameRequest = parse(payload)?;
        let project = rename_project(&self.runtime_store, &request.id, &request.name)
            .await
            .map_err(state_error)?;
        self.broadcast_authenticated(event("projectsChanged", json!({})));
        serde_json::to_value(project).map_err(state_error)
    }

    pub(super) async fn project_remove_preview_request(
        &self,
        payload: &Value,
    ) -> HostResult<Value> {
        let id = string_key(payload, "id")?;
        let workspaces = self
            .runtime_store
            .list_workspaces(&id)
            .await
            .map_err(state_error)?;
        let mut tab_count = 0usize;
        let mut session_count = 0usize;
        for workspace in &workspaces {
            tab_count += self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(state_error)?
                .len();
            session_count += self
                .sessions
                .values()
                .filter(|session| session.workspace_id() == workspace.id)
                .count();
        }
        let has_config_override = self
            .runtime_store
            .find_project_config(&id)
            .await
            .map_err(state_error)?
            .is_some();
        Ok(json!({
            "projectId": id,
            "workspaceCount": workspaces.len(),
            "tabCount": tab_count,
            "activeSessionCount": session_count,
            "hasConfigOverride": has_config_override,
        }))
    }

    pub(super) async fn project_effective_config_request(
        &self,
        payload: &Value,
    ) -> HostResult<Value> {
        let project_id = string_key(payload, "projectId")?;
        let result = effective_project_config(&self.runtime_store, &project_id)
            .await
            .map_err(state_error)?;
        serde_json::to_value(result).map_err(state_error)
    }

    pub(super) fn host_directory_roots_request(&self) -> HostResult<Value> {
        Ok(json!({ "roots": host_directory_roots() }))
    }

    pub(super) fn host_directory_list_request(&self, payload: &Value) -> HostResult<Value> {
        let path = string_key(payload, "path")?;
        serde_json::to_value(list_host_directory(&path).map_err(state_error)?).map_err(state_error)
    }

    pub(super) async fn project_clone_start_request(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let request: ProjectCloneStartRequest = parse(payload)?;
        let url = request.url.trim();
        if url.is_empty() {
            return Err(HostError::state("Clone URL cannot be empty."));
        }
        let destination = validate_clone_destination(&request.parent_path, &request.directory_name)
            .map_err(state_error)?;
        let parent_path = destination
            .parent()
            .expect("validated clone destination has a parent")
            .to_string_lossy()
            .to_string();
        let destination_path = destination.to_string_lossy().to_string();
        let now = Utc::now();
        let job = ProjectCloneJob {
            id: Uuid::new_v4().to_string(),
            source: sanitized_clone_source(url),
            parent_path,
            directory_name: request.directory_name.trim().to_string(),
            destination_path,
            project_name: request.name.filter(|name| !name.trim().is_empty()),
            status: ProjectCloneJobStatus::Queued,
            phase: ProjectCloneJobPhase::Cloning,
            progress_percent: None,
            message: Some("Waiting To Clone".to_string()),
            error: None,
            project_id: None,
            workspace_id: None,
            created_at: now,
            updated_at: now,
            finished_at: None,
        };
        self.runtime_store
            .insert_project_clone_job(job.clone())
            .await
            .map_err(state_error)?;
        let (cancel_tx, cancel_rx) = oneshot::channel();
        self.project_clone_jobs.insert(job.id.clone(), Some(cancel_tx));
        self.cancel_shutdown_timer();
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let raw_url = url.to_string();
        let task_job = job.clone();
        tokio::spawn(async move {
            run_clone_job(store, inbox.clone(), task_job.clone(), raw_url, cancel_rx).await;
            let _ = inbox.send(ServerCommand::ProjectCloneFinished {
                job_id: task_job.id,
            });
        });
        self.broadcast_authenticated(event("projectCloneJobsChanged", json!({ "id": job.id })));
        serde_json::to_value(job).map_err(state_error)
    }

    pub(super) async fn project_clone_list_request(&self) -> HostResult<Value> {
        serde_json::to_value(
            self.runtime_store
                .list_project_clone_jobs()
                .await
                .map_err(state_error)?,
        )
        .map_err(state_error)
    }

    pub(super) async fn project_clone_cancel_request(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let id = string_key(payload, "id")?;
        let Some(cancel) = self.project_clone_jobs.get_mut(&id).and_then(Option::take) else {
            if self.project_clone_jobs.contains_key(&id) {
                return Ok(json!({ "id": id, "cancelling": true }));
            }
            let job = self
                .runtime_store
                .find_project_clone_job(&id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| HostError::state(format!("Clone job not found: {id}")))?;
            if job.status.is_terminal() {
                return serde_json::to_value(job).map_err(state_error);
            }
            return Err(HostError::state(
                "Clone job is not running on this runtime.",
            ));
        };
        let _ = cancel.send(());
        Ok(json!({ "id": id, "cancelling": true }))
    }

    pub(super) async fn reconcile_interrupted_project_clones(&mut self) {
        let jobs = match self
            .runtime_store
            .list_interrupted_project_clone_jobs()
            .await
        {
            Ok(jobs) => jobs,
            Err(error) => {
                tracing::warn!("alera project clone recovery unavailable: {error}");
                return;
            }
        };
        for job in jobs {
            let cleanup = crate::project_clone_staging::cleanup_clone_staging(&job.parent_path, &job.id).await;
            let error = match cleanup {
                Ok(()) => "Runtime restarted during clone; final destination was preserved.".to_string(),
                Err(error) => format!("Runtime restarted during clone; final destination was preserved. Cleanup failed: {error}"),
            };
            let _ = self
                .runtime_store
                .update_project_clone_job(
                    &job.id,
                    ProjectCloneJobStatus::Failed,
                    job.phase,
                    job.progress_percent,
                    Some("Clone Interrupted"),
                    Some(&error),
                    None,
                    None,
                )
                .await;
        }
    }

    pub(super) fn handle_project_clone_changed(&self, job_id: String) {
        self.broadcast_authenticated(event("projectCloneJobsChanged", json!({ "id": job_id })));
    }

    pub(super) async fn handle_project_clone_finished(&mut self, job_id: String) {
        self.project_clone_jobs.remove(&job_id);
        self.broadcast_authenticated(event("projectCloneJobsChanged", json!({ "id": job_id })));
        self.broadcast_project_state_changed();
        self.schedule_shutdown_if_idle();
    }

    fn broadcast_project_state_changed(&self) {
        self.broadcast_authenticated(event("projectsChanged", json!({})));
        self.broadcast_workspaces_changed(None);
        self.broadcast_workspace_tabs_changed(None);
    }
}

fn parse<T: for<'de> Deserialize<'de>>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone()).map_err(state_error)
}

fn string_key(payload: &Value, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(ToString::to_string)
        .ok_or_else(|| HostError::state(format!("Missing or invalid {key}.")))
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

#[allow(dead_code)]
fn _assert_project_config_is_serializable(config: ProjectConfig) -> Value {
    serde_json::to_value(config).unwrap_or(Value::Null)
}
