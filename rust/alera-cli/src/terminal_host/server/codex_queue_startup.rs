//! Native queue recovery must not delay the runtime's request loop.

use super::codex_queue::store_error;
use super::codex_requests::codex_requests_catalogue::resumable_codex_cwd;
use super::codex_requests::codex_thread_sessions::thread_resume_params;
use super::codex_server_startup::CodexServerStartup;
use super::codex_state::{active_turn_id, snapshot, tab_thread_id, CodexTurnHistoryPage};
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;
use alera_core::runtime::{CodexChatDeliveryState, Workspace, WorkspaceTabRecord};
use serde_json::{json, Value};

pub(crate) struct CodexQueueStartupJob {
    tab: WorkspaceTabRecord,
    revision: u64,
    history_revision: u64,
    thread_id: String,
    cwd: String,
    workspaces: Vec<Workspace>,
    startup: CodexServerStartup,
}

pub(crate) struct CodexQueueResume {
    response: Value,
    history: Option<CodexTurnHistoryPage>,
    replace_history: bool,
}

enum CodexQueueStartupMode {
    Resume,
    Reconcile,
    Rollback(Value),
}

impl ServerActor {
    pub(super) async fn restore_codex_queues(&mut self) -> HostResult<()> {
        for mut state in self
            .runtime_store
            .list_codex_chat_states()
            .await
            .map_err(store_error)?
        {
            let Ok(tab) = self.codex_tab(&state.tab_id).await else {
                continue;
            };
            if tab_thread_id(&tab).as_deref() != Some(&state.thread_id) {
                continue;
            }
            let uncertain = state
                .messages
                .iter()
                .any(|entry| matches!(entry.status.as_str(), "sending" | "uncertain"));
            if uncertain || state.history_locked() {
                state.paused = true;
                for operation in &mut state.operations {
                    if operation.kind == "edit"
                        && matches!(
                            operation.phase.as_str(),
                            "interrupting" | "rollingBack" | "resending"
                        )
                    {
                        operation.payload["uncertainPhase"] = json!(operation.phase);
                        operation.phase = "uncertain".into();
                    }
                }
                for entry in &mut state.messages {
                    if entry.status == "sending" {
                        entry.status = "uncertain".into();
                    }
                }
                self.save_codex_delivery(&mut state).await?;
                let recovering_edit = state.operations.iter().rev().find(|op| {
                    op.kind == "edit" && op.phase != "completed" && op.phase != "failed"
                });
                if uncertain || recovering_edit.is_some_and(|op| op.phase == "uncertain") {
                    if let Err(error) = self
                        .defer_codex_queue_startup(&state, CodexQueueStartupMode::Reconcile)
                        .await
                    {
                        tracing::warn!("Codex recovery could not start: {error}");
                    }
                } else if let Some(response) = recovering_edit.and_then(|op| op.result.as_ref()) {
                    if let Err(error) = self
                        .defer_codex_queue_startup(
                            &state,
                            CodexQueueStartupMode::Rollback(response.clone()),
                        )
                        .await
                    {
                        tracing::warn!("Codex edit recovery could not replace history: {error}");
                    }
                }
            } else if !state.paused && state.has_pending() {
                if let Err(error) = self
                    .defer_codex_queue_startup(&state, CodexQueueStartupMode::Resume)
                    .await
                {
                    self.fail_codex_queue_startup(&mut state, &error).await?;
                }
            }
        }
        Ok(())
    }

    async fn defer_codex_queue_startup(
        &mut self,
        state: &CodexChatDeliveryState,
        mode: CodexQueueStartupMode,
    ) -> HostResult<()> {
        if self.codex_history_scans.contains(&state.tab_id) {
            return Ok(());
        }
        self.handle_codex_force_flush(&state.tab_id).await;
        let tab = self.codex_tab(&state.tab_id).await?;
        let workspaces = self.codex_workspaces(None).await?;
        let workspace = workspaces
            .iter()
            .find(|workspace| workspace.id == tab.workspace_id)
            .ok_or_else(|| HostError::state("The conversation workspace is unavailable."))?;
        let (cwd, _) = resumable_codex_cwd(&tab, workspace, &workspaces)?;
        let startup = self.codex_server_startup(Some(&cwd));
        let job = CodexQueueStartupJob {
            tab,
            revision: state.revision,
            history_revision: state.history_revision,
            thread_id: state.thread_id.clone(),
            cwd,
            workspaces,
            startup,
        };
        self.codex_history_scans.insert(state.tab_id.clone());
        self.codex_delivery_active.insert(state.tab_id.clone());
        self.cancel_shutdown_timer();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = async {
                let server = job.startup.clone().await?;
                let (response, replace_history) = match mode {
                    CodexQueueStartupMode::Reconcile => return Ok(None),
                    CodexQueueStartupMode::Resume => (
                        server
                            .request(
                                "thread/resume",
                                thread_resume_params(&job.thread_id, &job.cwd, 20),
                            )
                            .await?,
                        false,
                    ),
                    CodexQueueStartupMode::Rollback(response) => {
                        server.thread_history.lock().await.remove(&job.thread_id);
                        (response, true)
                    }
                };
                if response
                    .pointer("/thread/id")
                    .or_else(|| response.get("threadId"))
                    .and_then(Value::as_str)
                    .is_some_and(|id| id != job.thread_id)
                {
                    return Err(HostError::state("Codex resumed a different conversation."));
                }
                let history = server
                    .project_resumed_thread_history(&job.thread_id, &response, 20)
                    .await?;
                Ok(Some(CodexQueueResume {
                    response,
                    history,
                    replace_history,
                }))
            }
            .await;
            let _ = inbox.send(ServerCommand::CodexQueueStartupFinished {
                job: Box::new(job),
                result,
            });
        });
        Ok(())
    }

    pub(super) async fn finish_codex_queue_startup(
        &mut self,
        job: CodexQueueStartupJob,
        result: HostResult<Option<CodexQueueResume>>,
    ) {
        self.codex_history_scans.remove(&job.tab.id);
        let failed = self.apply_codex_queue_startup(&job, result).await.err();
        if let Some(error) = &failed {
            tracing::warn!(tab_id = job.tab.id, "Codex queue recovery failed: {error}");
        }
        if let Ok(tab) = self.codex_tab(&job.tab.id).await {
            if let Ok(state) = self.codex_delivery_state(&tab).await {
                // A live event can invalidate the captured snapshot without
                // canceling pending delivery. Re-read it off the actor too.
                if failed.is_some() && !state.paused && state.has_pending() {
                    if let Err(error) = self
                        .defer_codex_queue_startup(&state, CodexQueueStartupMode::Resume)
                        .await
                    {
                        tracing::warn!("Codex queue recovery could not restart: {error}");
                    }
                }
                self.refresh_codex_delivery_activity(
                    &state,
                    active_turn_id(&snapshot(&tab)).is_some(),
                );
            }
        } else {
            self.codex_delivery_active.remove(&job.tab.id);
        }
        self.schedule_shutdown_if_idle();
    }

    async fn apply_codex_queue_startup(
        &mut self,
        job: &CodexQueueStartupJob,
        result: HostResult<Option<CodexQueueResume>>,
    ) -> HostResult<()> {
        let startup_result = job
            .startup
            .peek()
            .cloned()
            .ok_or_else(|| HostError::state("Codex startup is not ready."))?;
        let server = self.adopt_codex_startup(&job.startup, startup_result);
        self.handle_codex_force_flush(&job.tab.id).await;
        let tab = self.codex_tab(&job.tab.id).await?;
        let mut state = self.codex_delivery_state(&tab).await?;
        if tab_thread_id(&tab).as_deref() != Some(&job.thread_id)
            || state.revision != job.revision
            || state.history_revision != job.history_revision
            || snapshot(&tab) != snapshot(&job.tab)
        {
            return Err(HostError::state(
                "The conversation changed during startup recovery.",
            ));
        }
        let (server, resumed) =
            match server.and_then(|server| result.map(|resumed| (server, resumed))) {
                Ok(value) => value,
                Err(error) => {
                    self.fail_codex_queue_startup(&mut state, &error).await?;
                    return Err(error);
                }
            };
        if let Some(resumed) = resumed {
            if resumed.replace_history {
                let page = resumed.history.ok_or_else(|| {
                    HostError::state("The conversation history could not be loaded.")
                })?;
                return self
                    .install_codex_history_page(&state, &resumed.response, page, false)
                    .await;
            }
            let opened = self
                .install_resumed_codex_thread(
                    tab,
                    job.cwd.clone(),
                    &job.workspaces,
                    &server,
                    resumed.response,
                    resumed.history,
                )
                .await?;
            self.broadcast_authenticated(event("codexThreadChanged", json!({
                "tabId":job.tab.id,"threadId":job.thread_id,"historyRevision":job.history_revision,
                "snapshot":opened["snapshot"],"historyNextCursor":opened["historyNextCursor"],
            })));
            self.schedule_codex_queue(&job.tab.id);
        } else {
            self.start_codex_history_scan(None, "recovery", json!({"tabId":job.tab.id}))
                .await?;
        }
        Ok(())
    }

    async fn fail_codex_queue_startup(
        &mut self,
        state: &mut CodexChatDeliveryState,
        error: &HostError,
    ) -> HostResult<()> {
        state.paused = true;
        if let Some(entry) = state
            .messages
            .iter_mut()
            .find(|entry| entry.status == "queued")
        {
            entry.status = "failed".into();
            entry.error = Some(error.wire_message());
        }
        self.save_codex_delivery(state).await
    }
}
