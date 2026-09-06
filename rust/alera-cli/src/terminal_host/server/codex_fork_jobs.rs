#[cfg(test)]
use super::codex_history_actions::read_turns;
use super::codex_history_actions::turn_complete;
use super::codex_history_scans::CodexHistoryScan;
use super::codex_queue::store_error;
use super::codex_server_startup::CodexServerStartup;
use super::codex_state::{active_turn_id, snapshot, tab_thread_id, CodexTurnHistoryPage};
use super::codex_tab_lifecycle::active_cwd;
use super::codex_thread_identity::ensure_expected_thread;
use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};
use alera_core::runtime::{CodexChatDeliveryState, CodexChatOperation, WorkspaceTabRecord};
use serde_json::{json, Value};
use uuid::Uuid;

pub(crate) struct CodexForkJob {
    pub(super) tab: WorkspaceTabRecord,
    pub(super) thread_id: String,
    pub(super) operation_id: String,
    history_revision: u64,
    startup: CodexServerStartup,
    client: Option<(u64, i64)>,
    params: Option<Value>,
    response: Option<Value>,
    request_sent: bool,
}

enum PreparedFork {
    Complete(Value),
    Pending(Box<CodexForkJob>),
}

impl ServerActor {
    pub(super) async fn fork_codex_history(&mut self, payload: &Value) -> HostResult<Value> {
        self.fork_codex_history_scanned(payload, None).await
    }

    pub(super) async fn fork_codex_history_scanned(
        &mut self,
        payload: &Value,
        scan: Option<&CodexHistoryScan>,
    ) -> HostResult<Value> {
        match self.prepare_codex_fork(payload, scan).await? {
            PreparedFork::Complete(value) => Ok(value),
            PreparedFork::Pending(job) => {
                #[cfg(test)]
                {
                    self.run_codex_fork_for_test(*job).await
                }
                #[cfg(not(test))]
                {
                    let _ = job;
                    Err(HostError::state("A deferred fork job is required."))
                }
            }
        }
    }

    pub(super) async fn defer_codex_fork(
        &mut self,
        client: Option<(u64, i64)>,
        payload: &Value,
        scan: Option<&CodexHistoryScan>,
    ) -> HostResult<Option<Value>> {
        match self.prepare_codex_fork(payload, scan).await? {
            PreparedFork::Complete(value) => Ok(Some(value)),
            PreparedFork::Pending(mut job) => {
                job.client = client;
                self.codex_history_scans.insert(job.tab.id.clone());
                self.codex_delivery_active.insert(job.tab.id.clone());
                self.cancel_shutdown_timer();
                let inbox = self.inbox.clone();
                tokio::spawn(async move {
                    let result = create_fork(&mut job).await;
                    let _ = inbox.send(ServerCommand::CodexForkCreated { job, result });
                });
                Ok(None)
            }
        }
    }

    async fn prepare_codex_fork(
        &mut self,
        payload: &Value,
        scan: Option<&CodexHistoryScan>,
    ) -> HostResult<PreparedFork> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        ensure_expected_thread(payload, tab_thread_id(&tab).as_deref())?;
        let mut state = self.codex_delivery_state(&tab).await?;
        let operation_id = require_string_key(payload, "operationId")?;
        let existing = state
            .operations
            .iter()
            .find(|op| op.id == operation_id)
            .cloned();
        if let Some(op) = &existing {
            if op.kind != "fork" {
                return Err(HostError::state(
                    "Operation identity belongs to another action.",
                ));
            }
            if op.phase == "completed" {
                return Ok(PreparedFork::Complete(op.result.clone().unwrap()));
            }
            if !matches!(op.phase.as_str(), "forkCreated" | "failed") {
                return Err(HostError::state(
                    op.payload["lastError"].as_str().unwrap_or(
                        "This fork's result is not confirmed. It will not be created again.",
                    ),
                ));
            }
        }
        if self.codex_history_scans.contains(&tab.id) {
            return Err(HostError::state(
                "A history operation is already in progress.",
            ));
        }
        if state.thread_id.is_empty() || state.history_locked() {
            return Err(HostError::state("This conversation cannot be forked yet."));
        }
        let response = existing
            .filter(|op| op.phase == "forkCreated")
            .map(|op| {
                op.result
                    .ok_or_else(|| HostError::state("The fork response is unavailable."))
            })
            .transpose()?;
        let params = if response.is_none() {
            let turns = if let Some(scan) = scan {
                scan.turns.clone()
            } else {
                #[cfg(test)]
                {
                    let server = self
                        .ensure_codex_server(active_cwd(&tab).as_deref())
                        .await?;
                    std::sync::Arc::new(read_turns(&server, &state.thread_id).await?)
                }
                #[cfg(not(test))]
                {
                    return Err(HostError::state(
                        "A deferred native history scan is required.",
                    ));
                }
            };
            let target = match payload.get("lastTurnId").and_then(Value::as_str) {
                Some(id) => turns.iter().find(|turn| turn["id"].as_str() == Some(id)),
                None => turns.iter().rev().find(|turn| turn_complete(turn)),
            }
            .filter(|turn| turn_complete(turn))
            .ok_or_else(|| HostError::state("Fork requires a finished turn."))?;
            let target_index = turns
                .iter()
                .position(|turn| turn["id"] == target["id"])
                .unwrap();
            let mut fork_payload = payload.clone();
            fork_payload["forkTabId"] = json!(Uuid::new_v4().to_string());
            fork_payload["forkedTurnIds"] = json!(turns[..=target_index]
                .iter()
                .filter_map(|turn| turn["id"].as_str())
                .collect::<Vec<_>>());
            state.operations.retain(|op| op.id != operation_id);
            state.operations.push(CodexChatOperation {
                id: operation_id.clone(),
                kind: "fork".into(),
                phase: "creating".into(),
                payload: fork_payload,
                result: None,
            });
            self.save_codex_delivery(&mut state).await?;
            Some(
                json!({"threadId":state.thread_id,"lastTurnId":target["id"],"cwd":active_cwd(&tab)}),
            )
        } else {
            None
        };
        let startup = self.codex_server_startup(active_cwd(&tab).as_deref());
        Ok(PreparedFork::Pending(Box::new(CodexForkJob {
            tab,
            thread_id: state.thread_id,
            operation_id,
            history_revision: state.history_revision,
            startup,
            client: None,
            params,
            response,
            request_sent: false,
        })))
    }

    pub(super) async fn finish_codex_fork_created(
        &mut self,
        mut job: CodexForkJob,
        result: HostResult<Value>,
    ) {
        match self.record_codex_fork_response(&job, result).await {
            Ok(response) => {
                job.response = Some(response);
                if let Err(error) = self.validate_codex_fork(&job).await {
                    self.finish_codex_fork_reply(&job, Err(error)).await;
                    return;
                }
                let inbox = self.inbox.clone();
                tokio::spawn(async move {
                    let result = project_fork(&job).await;
                    let _ = inbox.send(ServerCommand::CodexForkProjected {
                        job: Box::new(job),
                        result,
                    });
                });
            }
            Err(error) => self.finish_codex_fork_reply(&job, Err(error)).await,
        }
    }

    async fn record_codex_fork_response(
        &mut self,
        job: &CodexForkJob,
        result: HostResult<Value>,
    ) -> HostResult<Value> {
        let mut state = self
            .runtime_store
            .codex_chat_state(&job.thread_id)
            .await
            .map_err(store_error)?
            .ok_or_else(|| HostError::state("The fork operation no longer exists."))?;
        let op = state
            .operations
            .iter_mut()
            .find(|op| op.id == job.operation_id && op.kind == "fork")
            .ok_or_else(|| HostError::state("The fork operation no longer exists."))?;
        if job.params.is_some() {
            match &result {
                Ok(response) => {
                    op.phase = "forkCreated".into();
                    op.result = Some(response.clone());
                }
                Err(error) => {
                    op.payload["lastError"] = json!(error.wire_message());
                    op.phase = if job.request_sent
                        && super::codex_queue_delivery::delivery_is_uncertain(error)
                    {
                        "uncertain"
                    } else {
                        "failed"
                    }
                    .into();
                }
            }
            self.save_codex_delivery(&mut state).await?;
        }
        if let Some(started) = job.startup.peek().cloned() {
            // Retain a native receipt before rejecting a process replacement.
            self.adopt_codex_startup(&job.startup, started)?;
        }
        result
    }

    pub(super) async fn validate_codex_fork(
        &self,
        job: &CodexForkJob,
    ) -> HostResult<CodexChatDeliveryState> {
        let tab = self.codex_tab(&job.tab.id).await?;
        let state = self.codex_delivery_state(&tab).await?;
        let server = job.startup.peek().and_then(|result| result.as_ref().ok());
        if self.mutation_queue.has_runtime_mutations()
            || tab_thread_id(&tab).as_deref() != Some(&job.thread_id)
            || tab.workspace_id != job.tab.workspace_id
            || state.history_revision != job.history_revision
            || !server.is_some_and(|server| {
                self.codex
                    .as_ref()
                    .is_some_and(|current| current.matches_instance(&server.instance_token()))
            })
        {
            return Err(HostError::state("The conversation changed while its fork was being created. Retry to recover the saved fork."));
        }
        Ok(state)
    }

    pub(super) async fn finish_codex_fork_projected(
        &mut self,
        job: CodexForkJob,
        result: HostResult<Option<CodexTurnHistoryPage>>,
    ) {
        let result = match result {
            Ok(page) => {
                self.install_codex_fork(&job, job.response.as_ref().unwrap(), page)
                    .await
            }
            Err(error) => Err(error),
        };
        self.finish_codex_fork_reply(&job, result).await;
    }

    async fn finish_codex_fork_reply(&mut self, job: &CodexForkJob, result: HostResult<Value>) {
        self.codex_history_scans.remove(&job.tab.id);
        if let Some((client, request)) = job.client {
            self.client_write(
                client,
                match result {
                    Ok(value) => ok_response(request, value),
                    Err(error) => error_response(request, &error),
                },
            );
        }
        if let Ok(tab) = self.codex_tab(&job.tab.id).await {
            if let Ok(state) = self.codex_delivery_state(&tab).await {
                self.refresh_codex_delivery_activity(
                    &state,
                    active_turn_id(&snapshot(&tab)).is_some(),
                );
            }
            self.schedule_codex_queue(&tab.id);
        } else {
            self.codex_delivery_active.remove(&job.tab.id);
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn codex_fork_blocks_removal(
        &self,
        tab: &WorkspaceTabRecord,
    ) -> HostResult<bool> {
        Ok(self.codex_history_scans.contains(&tab.id)
            && self
                .codex_delivery_state(tab)
                .await?
                .operations
                .iter()
                .any(|op| {
                    op.kind == "fork" && matches!(op.phase.as_str(), "creating" | "forkCreated")
                }))
    }

    #[cfg(test)]
    async fn run_codex_fork_for_test(&mut self, mut job: CodexForkJob) -> HostResult<Value> {
        let result = create_fork(&mut job).await;
        let response = self.record_codex_fork_response(&job, result).await?;
        job.response = Some(response.clone());
        let page = project_fork(&job).await?;
        self.install_codex_fork(&job, &response, page).await
    }
}

async fn create_fork(job: &mut CodexForkJob) -> HostResult<Value> {
    let server = job.startup.clone().await?;
    if let Some(response) = &job.response {
        return Ok(response.clone());
    }
    job.request_sent = true;
    server
        .request("thread/fork", job.params.clone().unwrap())
        .await
}

async fn project_fork(job: &CodexForkJob) -> HostResult<Option<CodexTurnHistoryPage>> {
    let server = job.startup.clone().await?;
    let response = job.response.as_ref().unwrap();
    let thread_id = response
        .pointer("/thread/id")
        .and_then(Value::as_str)
        .ok_or_else(|| HostError::state("Codex returned no fork identity."))?;
    server
        .project_resumed_thread_history(thread_id, response, 20)
        .await
}
