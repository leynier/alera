//! The steps of a New Workspace from Prompt operation.
//!
//! The run calls this runtime's own requests through a local client, so each
//! step goes through the same handlers, checks, and broadcasts as the app's
//! From Prompt form: AI Assist names the workspace and picks its section,
//! `workspace.createManaged` or `workspace.createShared` creates it with the
//! setup deferred, the agent profile launches idempotently, and the setup
//! starts in a tab named "Setup".

use std::path::PathBuf;
use std::time::Duration;

use alera_core::runtime::{Project, RuntimeStore};
use serde_json::{json, Value};
use tokio::sync::oneshot;
use uuid::Uuid;

use super::hub_self_client::HubSelfClientPool;
use super::prompt_workspace_operation::{
    error_code, PromptWorkspaceOperation, CANCELLED, COMPLETED, NEEDS_INPUT,
};
use super::ServerCommand;
use crate::terminal_host::host_error::HostError;
use crate::terminal_host::ServerInbox;

pub(super) const IDENTITY_DEADLINE: Duration = Duration::from_secs(11 * 60);
const CREATE_DEADLINE: Duration = Duration::from_secs(10 * 60);
pub(super) const SHORT_DEADLINE: Duration = Duration::from_secs(60);

pub(super) enum Stop {
    Cancelled,
    Failed(HostError),
}

impl From<HostError> for Stop {
    fn from(error: HostError) -> Self {
        Self::Failed(error)
    }
}

pub(super) type Step<T> = Result<T, Stop>;

pub(super) struct PromptWorkspaceRun {
    pub(super) store: RuntimeStore,
    inbox: ServerInbox,
    runtime_dir: PathBuf,
    pub(super) operation: PromptWorkspaceOperation,
    cancel: oneshot::Receiver<()>,
    clients: HubSelfClientPool,
    /// The last status and phase written to the event journal.
    last_recorded: Option<(String, String)>,
}

impl PromptWorkspaceRun {
    pub(super) fn new(
        store: RuntimeStore,
        inbox: ServerInbox,
        runtime_dir: PathBuf,
        operation: PromptWorkspaceOperation,
        cancel: oneshot::Receiver<()>,
    ) -> Self {
        Self {
            store,
            inbox,
            runtime_dir,
            operation,
            cancel,
            clients: HubSelfClientPool::default(),
            last_recorded: None,
        }
    }

    /// Runs every step, or only the launch when the workspace already exists.
    pub(super) async fn run(mut self, launch_only: bool) {
        let outcome = if launch_only {
            self.launch_and_setup().await
        } else {
            self.create_and_launch().await
        };
        match outcome {
            Ok(()) => {}
            Err(Stop::Cancelled) => self.operation.finish(CANCELLED),
            Err(Stop::Failed(error)) => {
                let (code, retryable) = error_code(&error);
                let retryable = retryable || self.operation.workspace_id().is_some();
                self.operation.fail(code, &error.to_string(), retryable);
            }
        }
        self.save().await;
        let operation_id = self.operation.id.clone();
        let _ = self
            .inbox
            .send_wait(ServerCommand::PromptWorkspaceOperationFinished { operation_id })
            .await;
    }

    async fn create_and_launch(&mut self) -> Step<()> {
        let prompt = self.prompt()?;
        let Some((project, inferred)) = self.resolve_project(&prompt).await? else {
            self.operation.finish(NEEDS_INPUT);
            return Ok(());
        };
        self.operation.project_id = Some(project.id.clone());
        self.resolve_profile().await?;
        self.create_workspace(&project, &prompt, inferred).await?;
        self.assign_section().await;
        self.launch_and_setup().await
    }

    pub(super) fn prompt(&self) -> Step<String> {
        self.operation.prompt.clone().ok_or_else(|| {
            Stop::Failed(HostError::state(
                "The prompt of this operation is no longer available.",
            ))
        })
    }

    pub(super) async fn set_phase(&mut self, phase: &str) -> Step<()> {
        self.check_cancelled()?;
        self.operation.phase = phase.to_owned();
        self.save().await;
        Ok(())
    }

    pub(super) fn check_cancelled(&mut self) -> Step<()> {
        match self.cancel.try_recv() {
            Err(oneshot::error::TryRecvError::Empty) => Ok(()),
            _ => Err(Stop::Cancelled),
        }
    }

    pub(super) async fn save(&mut self) {
        let status = self.operation.status.clone();
        let transition = (status.clone(), self.operation.phase.clone());
        if self.last_recorded.as_ref() != Some(&transition) {
            super::runtime_event_requests::record_runtime_event(
                &self.store,
                "workspace.start.state",
                self.operation.workspace_id(),
                self.operation.project_id.as_deref(),
                &json!({
                    "operationId": self.operation.id,
                    "status": transition.0,
                    "phase": transition.1,
                }),
            )
            .await;
            self.last_recorded = Some(transition);
        }
        let data = self.operation.to_value();
        if let Err(error) = self
            .store
            .update_prompt_workspace_operation(&self.operation.id, &status, &data)
            .await
        {
            tracing::warn!("could not save prompt workspace operation: {error}");
        }
        let operation_id = self.operation.id.clone();
        let _ = self
            .inbox
            .send_wait(ServerCommand::PromptWorkspaceOperationChanged { operation_id })
            .await;
    }

    /// One request to this runtime, abandoned when the operation is cancelled.
    pub(super) async fn call(
        &mut self,
        request_type: &str,
        payload: Value,
        deadline: Duration,
    ) -> Step<Value> {
        self.check_cancelled()?;
        let key = format!("prompt-workspace:{}", self.operation.id);
        let request =
            self.clients
                .request(&self.runtime_dir, &key, request_type, payload, deadline);
        tokio::select! {
            biased;
            _ = &mut self.cancel => Err(Stop::Cancelled),
            result = request => result.map_err(Stop::Failed),
        }
    }

    /// A request that must finish once sent. Creating a workspace runs on
    /// past an abandoned call, so cancelling mid-way would leave the new
    /// workspace outside the operation and its launch retry.
    pub(super) async fn call_to_completion(
        &mut self,
        request_type: &str,
        payload: Value,
        deadline: Duration,
    ) -> Step<Value> {
        self.check_cancelled()?;
        let key = format!("prompt-workspace:{}", self.operation.id);
        self.clients
            .request(&self.runtime_dir, &key, request_type, payload, deadline)
            .await
            .map_err(Stop::Failed)
    }

    pub(super) async fn generate_identity(&mut self, payload: Value) -> Step<Value> {
        let operation_id = Uuid::new_v4().to_string();
        let mut payload = payload;
        payload["operationId"] = json!(operation_id);
        let result = self
            .call(
                "aiText.workspaceIdentity.generate",
                payload,
                IDENTITY_DEADLINE,
            )
            .await;
        if matches!(result, Err(Stop::Cancelled)) {
            // The generation runs on its own; stop it too.
            let _ = self
                .clients
                .request(
                    &self.runtime_dir,
                    &format!("prompt-workspace:{}", self.operation.id),
                    "aiText.cancel",
                    json!({ "operationId": operation_id }),
                    SHORT_DEADLINE,
                )
                .await;
        }
        result
    }

    /// The project the request names, the only registered one, or the one AI
    /// Assist recognizes in the prompt. `None` means the answer was unclear
    /// and the operation now lists candidates instead of guessing.
    async fn resolve_project(&mut self, prompt: &str) -> Step<Option<(Project, Option<Value>)>> {
        self.set_phase("resolvingProject").await?;
        if let Some(project_id) = self.operation.request.project_id.clone() {
            return Ok(Some((self.find_project(&project_id).await?, None)));
        }
        let projects = self.store.list_projects().await.map_err(state)?;
        match projects.len() {
            0 => return Err(HostError::state("No projects are registered in Alera.").into()),
            1 => return Ok(Some((projects[0].clone(), None))),
            _ => {}
        }
        self.set_phase("generatingIdentity").await?;
        let answer = self
            .generate_identity(json!({
                "prompt": prompt,
                "inferProject": true,
                "autoAssignSection": self.auto_section(),
            }))
            .await?;
        if let Some(project_id) = answer.get("projectId").and_then(Value::as_str) {
            let project = self.find_project(project_id).await?;
            return Ok(Some((project, Some(answer))));
        }
        self.operation.candidates = self.project_candidates(projects).await;
        self.operation.error = Some(json!({
            "code": "needs_input",
            "message": "The prompt does not clearly name a project. Retry with projectId set to one of the candidates.",
            "retryable": false,
        }));
        Ok(None)
    }

    async fn find_project(&self, project_id: &str) -> Step<Project> {
        self.store
            .find_project(project_id)
            .await
            .map_err(state)?
            .ok_or_else(|| HostError::state(format!("Project not found: {project_id}")).into())
    }

    /// Projects ordered by their most recent workspace activity.
    async fn project_candidates(&self, projects: Vec<Project>) -> Vec<Value> {
        let workspaces = self.store.list_all_workspaces().await.unwrap_or_default();
        let mut ranked = projects
            .into_iter()
            .map(|project| {
                let latest = workspaces
                    .iter()
                    .filter(|workspace| workspace.project_id == project.id)
                    .map(|workspace| workspace.updated_at)
                    .max()
                    .unwrap_or(project.updated_at);
                (latest, project)
            })
            .collect::<Vec<_>>();
        ranked.sort_by_key(|(latest, _)| std::cmp::Reverse(*latest));
        ranked
            .into_iter()
            .map(|(_, project)| {
                json!({ "projectId": project.id, "name": project.name, "path": project.repo_path })
            })
            .collect()
    }

    /// The named profile, else the runtime's default, else the first one, as
    /// the app's form picks it.
    async fn resolve_profile(&mut self) -> Step<()> {
        let listed = self
            .call("agentProfile.list", json!({}), SHORT_DEADLINE)
            .await?;
        let profiles = listed["items"].as_array().cloned().unwrap_or_default();
        let id_of = |profile: &Value| profile["id"].as_str().map(str::to_owned);
        let selected = match self.operation.request.profile.as_deref() {
            Some(wanted) => profiles
                .iter()
                .find(|profile| {
                    profile["id"].as_str() == Some(wanted)
                        || profile["name"]
                            .as_str()
                            .is_some_and(|name| name.eq_ignore_ascii_case(wanted))
                })
                .and_then(id_of)
                .ok_or_else(|| HostError::state(format!("Agent profile not found: {wanted}")))?,
            None => {
                let default = self.store.default_agent_profile_id().await.ok().flatten();
                default
                    .filter(|id| {
                        profiles
                            .iter()
                            .any(|profile| profile["id"].as_str() == Some(id))
                    })
                    .or_else(|| profiles.first().and_then(id_of))
                    .ok_or_else(|| HostError::state("No agent profiles are declared."))?
            }
        };
        self.operation.profile_id = Some(selected);
        Ok(())
    }

    async fn launch_and_setup(&mut self) -> Step<()> {
        let workspace_id = self
            .operation
            .workspace_id()
            .map(str::to_owned)
            .ok_or_else(|| HostError::state("The operation has no workspace to launch in."))?;
        let launch = self.launch_agent(&workspace_id).await;
        // The app opens the setup even when the launch failed.
        self.start_setup(&workspace_id).await;
        launch?;
        self.operation.finish(COMPLETED);
        Ok(())
    }

    async fn launch_agent(&mut self, workspace_id: &str) -> Step<()> {
        self.set_phase("launchingAgent").await?;
        let prompt = self.prompt()?;
        let profile_id = self
            .operation
            .profile_id
            .clone()
            .ok_or_else(|| HostError::state("The operation has no agent profile."))?;
        let payload = json!({
            "workspaceId": workspace_id,
            "profileId": profile_id,
            "prompt": prompt,
            "clientMutationId": self.operation.client_mutation_id,
        });
        let launched = match self
            .call(
                "agentProfile.launchIdempotent",
                payload.clone(),
                CREATE_DEADLINE,
            )
            .await
        {
            Err(Stop::Failed(error))
                if error.to_string().contains("Unknown terminal host request") =>
            {
                self.call("agentProfile.launch", payload, CREATE_DEADLINE)
                    .await?
            }
            other => other?,
        };
        self.operation.agent = Some(json!({
            "tabId": launched["tab"]["id"],
            "agentType": launched["agentType"],
            "profileId": launched["profileId"],
        }));
        self.save().await;
        Ok(())
    }

    pub(super) fn auto_section(&self) -> bool {
        self.operation.request.section == super::prompt_workspace_operation::SectionPolicy::Auto
    }
}

pub(super) fn state(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
