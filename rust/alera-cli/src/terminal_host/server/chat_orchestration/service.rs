use std::sync::Arc;

use alera_core::runtime::RuntimeStore;
use async_trait::async_trait;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::ConfigureInput;
use crate::terminal_host::server::agent_chat_runtime::AgentChatRuntime;

use super::authorization::{authorize_request, modes_at_or_below, BoundChat, OrchestrationCaller};
use super::capability_models::{shorten_models, CallerModel};
use super::credentials::ChatCredentialLaunchHook;
use super::job_lifecycle::{OrchestrationJobs, RequestJob};
use super::models::OrchestrationRequest;
use super::request_admission::RequestAdmission;
use super::runtime::{ChatOrchestrationRuntime, LocalChatOrchestrationRuntime};
use super::targets::ChatTargetResolver;
use super::task_next::{add_next, add_wait_next};
use super::wake_pump::WakePump;

pub(super) const TASK_ORIGIN: &str = "chatMessage";

#[async_trait]
pub(crate) trait OrchestrationEventSink: Send + Sync + 'static {
    async fn changed(&self, change: Value);
}

pub(crate) struct NullOrchestrationEventSink;

#[async_trait]
impl OrchestrationEventSink for NullOrchestrationEventSink {
    async fn changed(&self, _change: Value) {}
}

#[derive(Clone)]
pub(crate) struct ChatOrchestrationService {
    pub(super) store: RuntimeStore,
    pub(super) runtime: Arc<dyn ChatOrchestrationRuntime>,
    pub(super) targets: Arc<dyn ChatTargetResolver>,
    pub(super) credentials: Arc<ChatCredentialLaunchHook>,
    pub(super) events: Arc<dyn OrchestrationEventSink>,
    pub(super) admission: Arc<RequestAdmission>,
    pub(super) jobs: Arc<OrchestrationJobs>,
    pub(super) wake_pump: Arc<WakePump>,
    /// Tasks a monitor follows, so a re-armed task never gets two.
    pub(super) monitored: Arc<std::sync::Mutex<std::collections::HashSet<String>>>,
    /// How long one delegated task may take to stop when its parent stops.
    pub(super) child_stop_deadline: std::time::Duration,
    /// Secret requests (`agentChatSecretRequestsV1`); off without a store.
    pub(super) secrets: Option<Arc<super::secrets::ChatSecretBroker>>,
    /// Scheduled tasks (`chatOrchestrationSchedulesV1`); off without a host.
    pub(super) schedules: Option<Arc<dyn super::schedules::ScheduleHost>>,
}

impl ChatOrchestrationService {
    pub(crate) fn new(
        store: RuntimeStore,
        runtime: AgentChatRuntime,
        targets: Arc<dyn ChatTargetResolver>,
        credentials: Arc<ChatCredentialLaunchHook>,
    ) -> Self {
        Self {
            runtime: LocalChatOrchestrationRuntime::new(store.clone(), runtime),
            store,
            targets,
            credentials,
            events: Arc::new(NullOrchestrationEventSink),
            admission: Arc::new(RequestAdmission::default()),
            jobs: Arc::default(),
            wake_pump: Arc::default(),
            monitored: Arc::default(),
            child_stop_deadline: super::stop::CHILD_STOP_DEADLINE,
            secrets: None,
            schedules: None,
        }
    }

    pub(crate) fn with_schedules(mut self, host: Arc<dyn super::schedules::ScheduleHost>) -> Self {
        self.schedules = Some(host);
        self
    }

    pub(crate) fn with_secrets(mut self, secrets: Arc<super::secrets::ChatSecretBroker>) -> Self {
        self.secrets = Some(secrets);
        self
    }

    /// Deletes expired secret refs and files.
    pub(crate) async fn sweep_secrets(&self) {
        if let Some(secrets) = &self.secrets {
            secrets.vault.sweep().await;
        }
    }

    #[cfg(test)]
    pub(crate) fn with_child_stop_deadline(mut self, deadline: std::time::Duration) -> Self {
        self.child_stop_deadline = deadline;
        self
    }

    pub(crate) fn with_runtime(mut self, runtime: Arc<dyn ChatOrchestrationRuntime>) -> Self {
        self.runtime = runtime;
        self
    }

    pub(crate) fn with_events(mut self, events: Arc<dyn OrchestrationEventSink>) -> Self {
        self.events = events;
        self
    }

    /// Stops orchestration requests, monitors and their inline wake delivery.
    /// A false result requires another attempt before shutting down chat actors.
    pub(crate) async fn shutdown(&self) -> bool {
        self.jobs.shutdown().await
    }

    #[cfg(test)]
    pub(crate) fn credential_hook(&self) -> Arc<ChatCredentialLaunchHook> {
        self.credentials.clone()
    }

    /// Verifies the token and the current chat generation before a connection
    /// is bound. The caller still needs `require_bound_turn` for every call.
    pub(crate) async fn bind_credential(&self, token: &str) -> HostResult<BoundChat> {
        let binding = self.credentials.verify(token).await?;
        let current = BoundChat {
            chat_id: binding.chat_id.clone(),
            generation: binding.generation,
            runtime_mode: "approval-required".into(),
            credential_hash: binding.credential_hash.clone(),
            origin_host_id: None,
        };
        let snapshot = self.runtime.validate_binding(&current).await.map_err(|_| {
            HostError::conflict(
                "chat_credential_invalid",
                "The chat credential is invalid or expired.",
                json!({}),
            )
        })?;
        let archived = snapshot
            .get("archived")
            .and_then(Value::as_bool)
            .unwrap_or(true);
        let generation = snapshot
            .get("session")
            .and_then(|session| session.get("generation"))
            .and_then(Value::as_i64)
            .unwrap_or_default();
        if archived || generation != binding.generation {
            return Err(HostError::conflict(
                "chat_credential_invalid",
                "The chat credential is invalid or expired.",
                json!({}),
            ));
        }
        let runtime_mode = snapshot
            .get("session")
            .and_then(|session| session.get("runtimeMode"))
            .and_then(Value::as_str)
            .unwrap_or("approval-required")
            .to_owned();
        Ok(BoundChat {
            chat_id: binding.chat_id,
            generation: binding.generation,
            runtime_mode,
            credential_hash: binding.credential_hash,
            origin_host_id: None,
        })
    }

    pub(crate) async fn handle(
        &self,
        verb: &str,
        payload: &Value,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let service = self.clone();
        let verb = verb.to_owned();
        let payload = payload.clone();
        let caller = caller.clone();
        let (sender, receiver) = tokio::sync::oneshot::channel();
        let Some(_request) = self
            .jobs
            .spawn(async move {
                let response = service.handle_admitted(&verb, &payload, &caller).await;
                let _ = sender.send(response);
            })
            .map(RequestJob)
        else {
            return Err(shutdown_error());
        };
        receiver.await.unwrap_or_else(|_| Err(shutdown_error()))
    }

    async fn handle_admitted(
        &self,
        verb: &str,
        payload: &Value,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let request = OrchestrationRequest::parse(verb, payload)?;
        let _admission = if let Some(request_id) = payload
            .get("requestId")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|id| !id.is_empty())
        {
            Some(
                self.admission
                    .enter(&caller.ctx.scope, verb, request_id)
                    .await,
            )
        } else {
            None
        };
        let current_caller =
            authorize_request(caller, &self.store, self.runtime.as_ref(), &request).await?;
        let caller = &current_caller;
        if let Some(response) = self
            .route_to_chat_owner(verb, payload, &request, caller)
            .await?
        {
            return Ok(response);
        }
        match request {
            OrchestrationRequest::Capabilities {
                workspace_id,
                host_id,
                search,
            } => {
                self.capabilities(workspace_id, host_id, search, caller)
                    .await
            }
            OrchestrationRequest::Delegate(input) => self.delegate(*input, caller).await,
            OrchestrationRequest::Send(input) => self.send(input, caller).await,
            OrchestrationRequest::Task {
                task_id,
                acknowledge,
                request_id,
            } => {
                let mut response = self
                    .task_request(&task_id, acknowledge, request_id.as_deref(), caller)
                    .await?;
                if !acknowledge {
                    if let Ok(Some(task)) = self.store.chat_orchestration_task(&task_id).await {
                        add_next(&mut response, &task, caller);
                    }
                }
                Ok(response)
            }
            OrchestrationRequest::TasksList(input) => self.tasks_list(input, caller).await,
            OrchestrationRequest::Wait(input) => {
                let task_ids = input.task_ids.clone();
                let mut response = self.wait(input, caller).await?;
                let mut tasks = Vec::with_capacity(task_ids.len());
                for task_id in &task_ids {
                    if let Ok(Some(task)) = self.store.chat_orchestration_task(task_id).await {
                        tasks.push(task);
                    }
                }
                add_wait_next(&mut response, &tasks, caller);
                Ok(response)
            }
            OrchestrationRequest::Cancel {
                task_id,
                request_id,
                reason,
            } => {
                self.cancel(task_id, request_id, reason, payload, caller)
                    .await
            }
            OrchestrationRequest::Interrupt {
                chat_id,
                turn_id,
                request_id,
            } => {
                self.interrupt(chat_id, turn_id, request_id, payload, caller)
                    .await
            }
            OrchestrationRequest::BackgroundWait {
                task_ids,
                waiting,
                request_id,
            } => {
                self.background_wait(task_ids, waiting, request_id, payload, caller)
                    .await
            }
            OrchestrationRequest::Requests { task_id, chat_id } => {
                self.requests(task_id, chat_id, caller).await
            }
            OrchestrationRequest::Respond {
                chat_id,
                runtime_request_id,
                response,
                request_id,
            } => {
                self.respond(
                    chat_id,
                    runtime_request_id,
                    response,
                    request_id,
                    payload,
                    caller,
                )
                .await
            }
            OrchestrationRequest::Configure {
                chat_id,
                request_id,
                provider,
                provider_instance_id,
                model,
                reasoning_effort,
                runtime_mode,
                interaction_mode,
            } => {
                self.configure(
                    chat_id,
                    request_id,
                    ConfigureInput {
                        provider,
                        provider_instance_id,
                        model,
                        reasoning_effort,
                        runtime_mode,
                        interaction_mode,
                    },
                    payload,
                    caller,
                )
                .await
            }
            OrchestrationRequest::Read { chat_id, limit } => self.read(chat_id, limit).await,
            OrchestrationRequest::Transfers { chat_id } => self.transfers(chat_id, caller).await,
            OrchestrationRequest::RequestSecret {
                secret_request_id,
                label,
                reason,
                placeholder,
                delivery,
            } => {
                self.request_secret(
                    super::secrets::SecretAsk {
                        request_id: secret_request_id,
                        label,
                        reason,
                        placeholder,
                        delivery,
                    },
                    caller,
                )
                .await
            }
            OrchestrationRequest::ReadSecret { secret_ref } => {
                self.read_secret(&secret_ref, caller).await
            }
            OrchestrationRequest::ScheduleTask(input) => self.schedule_task(*input, caller).await,
            OrchestrationRequest::ListScheduledTasks {
                chat_id,
                project_id,
            } => self.list_scheduled_tasks(chat_id, project_id, caller).await,
            OrchestrationRequest::DeleteScheduledTask {
                scheduled_task_id, ..
            } => self.delete_scheduled_task(&scheduled_task_id, caller).await,
            OrchestrationRequest::RunScheduledTaskNow {
                scheduled_task_id, ..
            } => {
                self.run_scheduled_task_now(&scheduled_task_id, caller)
                    .await
            }
            OrchestrationRequest::PullRequest {
                action,
                chat_id,
                url,
            } => {
                use super::models::PullRequestAction as Action;
                let url = url.unwrap_or_default();
                match action {
                    Action::Link => self.link_pull_request(chat_id, &url, caller).await,
                    Action::Unlink => self.unlink_pull_request(chat_id, &url, caller).await,
                    Action::List => self.list_pull_requests(chat_id, caller).await,
                    Action::Watch => self.watch_pull_request(chat_id, &url, true, caller).await,
                    Action::Unwatch => self.watch_pull_request(chat_id, &url, false, caller).await,
                }
            }
            OrchestrationRequest::UpdateTitle {
                chat_id,
                request_id,
                title,
            } => {
                self.update_title(chat_id, request_id, title, payload, caller)
                    .await
            }
            OrchestrationRequest::ListChats {
                workspace_id,
                project_id,
                host_id,
                include_archived,
            } => {
                self.list_chats(workspace_id, project_id, host_id, include_archived)
                    .await
            }
        }
    }

    async fn capabilities(
        &self,
        workspace_id: Option<String>,
        host_id: Option<String>,
        search: Option<String>,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let mut value = self
            .runtime
            .providers_for_host(workspace_id.as_deref(), host_id.as_deref(), false)
            .await?;
        if let Some(providers) = value.get_mut("providers").and_then(Value::as_array_mut) {
            for provider in providers {
                let supported = provider
                    .get("capabilities")
                    .and_then(|caps| caps.get("mcpInjection"))
                    .and_then(|mcp| mcp.get("stdio"))
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                provider["orchestration"] = json!({
                    "supported": supported,
                    "reason": (!supported).then_some("provider cannot receive the orchestration MCP server"),
                });
            }
        }
        value["maxWaitSeconds"] = json!(super::MAX_WAIT_SECONDS);
        value["runtimeModes"] = json!([
            "approval-required",
            "auto-accept-edits",
            "auto",
            "full-access"
        ]);
        value["ceilingRuntimeModes"] = json!(caller
            .bound
            .as_ref()
            .map(|bound| modes_at_or_below(&bound.runtime_mode))
            .unwrap_or_else(|| vec![
                "approval-required",
                "auto-accept-edits",
                "auto",
                "full-access"
            ]));
        let mut own = None;
        if let Some(bound) = &caller.bound {
            value["caller"] = json!({
                "chatId": bound.chat_id,
                "runtimeMode": bound.runtime_mode,
            });
            if let Ok(snapshot) = self.runtime.snapshot(&bound.chat_id).await {
                value["caller"]["providerInstanceId"] = snapshot["providerInstanceId"].clone();
                value["caller"]["model"] = snapshot["session"]["model"].clone();
                value["caller"]["reasoningEffort"] = snapshot["session"]["reasoningEffort"].clone();
                own = Some(snapshot);
            }
        }
        // Agents get a short list per provider; a person keeps the full
        // catalog the delegate dialog needs unless they search.
        if caller.bound.is_some() || search.is_some() {
            let preferences = self
                .store
                .agent_chat_preferences()
                .await
                .unwrap_or(Value::Null);
            let caller_model = own.as_ref().map(|snapshot| CallerModel {
                provider_instance_id: snapshot["providerInstanceId"].as_str().unwrap_or_default(),
                model: snapshot["session"]["model"].as_str(),
            });
            if let Some(providers) = value.get_mut("providers").and_then(Value::as_array_mut) {
                shorten_models(
                    providers,
                    &preferences,
                    caller_model.as_ref(),
                    search.as_deref(),
                );
            }
        }
        Ok(value)
    }
}

fn shutdown_error() -> HostError {
    HostError::conflict(
        "chat_orchestration_shutdown",
        "Chat orchestration is shutting down. Retry after the runtime restarts.",
        json!({}),
    )
}
