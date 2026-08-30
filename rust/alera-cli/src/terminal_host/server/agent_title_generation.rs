use alera_core::runtime::WorkspaceTabRecord;
use serde_json::{json, Value};
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::agent_title_context::{clean_terminal, codex_context, parse_title, title_prompt};
use super::agent_title_state::{is_manual, AgentTitleState};
use super::ai_assist_requests::{plan_command, run_command};
use super::{ServerActor, ServerCommand};

pub(super) struct AgentTitleJob {
    pub id: String,
    pub conversation: String,
    pub revision: Value,
    pub automatic: bool,
    pub reply: Option<(u64, i64)>,
    pub cancel: Option<oneshot::Sender<()>>,
}

impl ServerActor {
    pub(super) async fn request_agent_title(
        &mut self,
        client: u64,
        request: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let tab_id = super::requests::require_string_key(payload, "tabId")?;
        let mut tab = self
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .ok_or_else(|| HostError::state("Workspace tab not found."))?;
        if !matches!(tab.kind.as_str(), "terminal" | "codex") {
            return Err(HostError::state(
                "This tab does not contain an agent conversation.",
            ));
        }
        if payload.get("expectedConversationId") != Some(&tab.payload["agentTitleConversationId"])
            || payload.get("expectedRevision") != Some(&tab.payload["agentTitleRevision"])
        {
            return Err(HostError::state(
                "The conversation or title changed. Try again.",
            ));
        }
        let settings = self
            .runtime_store
            .effective_ai_assist_settings()
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        if !settings.enabled {
            return Err(HostError::state("AI Assist is disabled."));
        }
        if self.agent_title_jobs.contains_key(&tab_id) {
            return Err(HostError::state("Title generation is already running."));
        }
        let mut state = AgentTitleState::read(&tab).unwrap_or_else(|| AgentTitleState::new(false));
        if state.initial_prompt.is_empty() && tab.kind == "codex" {
            state.initial_prompt = super::agent_title_events::first_codex_prompt(&tab);
        }
        state.write(&mut tab);
        self.queue_agent_title(tab, state, Some((client, request)))
            .await
    }

    pub(super) async fn queue_agent_title(
        &mut self,
        mut tab: WorkspaceTabRecord,
        mut state: AgentTitleState,
        reply: Option<(u64, i64)>,
    ) -> HostResult<()> {
        if self.agent_title_jobs.contains_key(&tab.id) {
            return Ok(());
        }
        let automatic = reply.is_none();
        if automatic {
            if !state.eligible || state.attempted || is_manual(&tab) {
                return Ok(());
            }
            let settings = self
                .runtime_store
                .effective_ai_assist_settings()
                .await
                .map_err(|e| HostError::state(e.to_string()))?;
            // Do not rename an old conversation merely because the setting is enabled later.
            state.attempted = true;
            state.write(&mut tab);
            if !settings.enabled || !settings.auto_generate_agent_titles {
                self.runtime_store
                    .upsert_workspace_tab(tab)
                    .await
                    .map_err(|e| HostError::state(e.to_string()))?;
                return Ok(());
            }
        } else {
            state.attempted = true;
            state.write(&mut tab);
        }
        let id = Uuid::new_v4().to_string();
        let tab_id = tab.id.clone();
        let job = AgentTitleJob {
            id: id.clone(),
            conversation: state.conversation_id,
            revision: tab.payload["agentTitleRevision"].clone(),
            automatic,
            reply,
            cancel: None,
        };
        tab.payload["agentTitleStatus"] = json!("generating");
        let workspace_id = tab.workspace_id.clone();
        self.runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        self.agent_title_jobs.insert(tab_id.clone(), job);
        self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            if automatic {
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            }
            let _ = inbox.send(ServerCommand::AgentTitleReady { tab_id, id });
        });
        Ok(())
    }

    pub(super) async fn start_agent_title(&mut self, tab_id: String, id: String) {
        let result = self.prepare_agent_title(&tab_id, &id).await;
        if let Err(error) = result {
            self.finish_agent_title(tab_id, id, Err(error)).await;
        }
    }

    async fn prepare_agent_title(&mut self, tab_id: &str, id: &str) -> HostResult<()> {
        let Some(job) = self.agent_title_jobs.get(tab_id).filter(|job| job.id == id) else {
            return Ok(());
        };
        let tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .ok_or_else(|| HostError::state("The tab was closed."))?;
        if !job_matches(job, &tab) {
            return Err(HostError::state("The conversation or title changed."));
        }
        let settings = self
            .runtime_store
            .effective_ai_assist_settings()
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        if !settings.enabled || (job.automatic && !settings.auto_generate_agent_titles) {
            return Err(HostError::state("Title generation is disabled."));
        }
        let state = AgentTitleState::read(&tab)
            .ok_or_else(|| HostError::state("Conversation state is unavailable."))?;
        let recent = if tab.kind == "codex" {
            codex_context(&super::codex_state::snapshot(&tab))
        } else {
            let session_id = super::requests::terminal_session_id_from_tab(&tab)
                .unwrap_or_else(|| tab.id.clone());
            self.sessions
                .get(&session_id)
                .map(|session| {
                    let bytes = session.recent_output_since(state.cursor, 64 * 1024);
                    String::from_utf8_lossy(&bytes).to_string()
                })
                .unwrap_or_default()
        };
        let automatic = job.automatic;
        let initial = state.initial_prompt;
        let inbox = self.inbox.clone();
        let tab_id = tab_id.to_string();
        let id = id.to_string();
        let directory = self.runtime_dir.join("agent-title-jobs").join(&id);
        let (cancel_tx, cancel_rx) = oneshot::channel();
        self.agent_title_jobs
            .get_mut(&tab_id)
            .expect("job exists")
            .cancel = Some(cancel_tx);
        tokio::spawn(async move {
            let result = async {
                // Bounded parsing and command preparation stay off the server actor.
                let recent = if automatic && !initial.is_empty() { String::new() } else { clean_terminal(&recent) };
                let prompt = title_prompt(&initial, &recent, settings.instructions_by_operation.get("agentTitle").map(String::as_str).unwrap_or_default())?;
                let plan = plan_command(&settings, "agentTitle", &prompt)?;
                tokio::fs::create_dir_all(&directory).await.map_err(|_| HostError::state("Could not prepare title generation."))?;
                let output = run_command(plan, &directory.to_string_lossy(), settings.timeout_seconds, cancel_rx).await
                    .map_err(|_| HostError::state("AI Assist could not generate a title. Check the configured provider and try again."))?;
                parse_title(&output)
            }.await;
            let _ = tokio::fs::remove_dir_all(&directory).await;
            let _ = inbox.send(ServerCommand::AgentTitleFinished { tab_id, id, result });
        });
        Ok(())
    }

    pub(super) async fn finish_agent_title(
        &mut self,
        tab_id: String,
        id: String,
        result: HostResult<String>,
    ) {
        if self
            .agent_title_jobs
            .get(&tab_id)
            .is_none_or(|job| job.id != id)
        {
            return;
        }
        let job = self.agent_title_jobs.remove(&tab_id).expect("job exists");
        let outcome = self.apply_agent_title(&tab_id, &job, result).await;
        if let Some((client, request)) = job.reply {
            match outcome {
                Ok(value) => self.client_write(client, ok_response(request, value)),
                Err(error) => self.client_write(client, error_response(request, &error)),
            }
        } else if outcome.is_err() {
            tracing::debug!(tab_id, "automatic agent title was not applied");
        }
    }

    async fn apply_agent_title(
        &mut self,
        tab_id: &str,
        job: &AgentTitleJob,
        result: HostResult<String>,
    ) -> HostResult<Value> {
        let mut tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .ok_or_else(|| HostError::state("The tab was closed."))?;
        if !job_matches(job, &tab) {
            return Err(HostError::state(
                "The conversation or title changed. The generated title was discarded.",
            ));
        }
        let settings = self
            .runtime_store
            .effective_ai_assist_settings()
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        let result = if !settings.enabled || (job.automatic && !settings.auto_generate_agent_titles)
        {
            Err(HostError::state("Title generation is disabled."))
        } else {
            result
        };
        let title = match result {
            Ok(title) => title,
            Err(error) => {
                tab.payload["agentTitleStatus"] = json!("failed");
                let workspace_id = tab.workspace_id.clone();
                let _ = self.runtime_store.upsert_workspace_tab(tab).await;
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
                return Err(error);
            }
        };
        if tab.kind == "codex" {
            if let Some(thread_id) = super::codex_state::tab_thread_id(&tab) {
                if let Err(error) = self
                    .codex_server_request(
                        "thread/name/set",
                        json!({"threadId": thread_id, "name": title}),
                    )
                    .await
                {
                    tab.payload["agentTitleStatus"] = json!("failed");
                    let workspace_id = tab.workspace_id.clone();
                    let _ = self.runtime_store.upsert_workspace_tab(tab).await;
                    self.broadcast_workspace_tabs_changed(Some(&workspace_id));
                    return Err(error);
                }
            }
            super::codex_thread_identity::apply_manual_thread_title(&mut tab, &title);
        }
        tab.title = title.clone();
        // Older clients already honor manualTitle over OSC titles.
        tab.payload["manualTitle"] = json!(true);
        tab.payload["agentTitleSource"] = json!("generated");
        tab.payload["agentTitleStatus"] = json!("idle");
        tab.payload["agentTitleRevision"] = json!(Uuid::new_v4().to_string());
        let workspace_id = tab.workspace_id.clone();
        self.runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        Ok(json!({"title": title}))
    }

    pub(super) fn cancel_agent_title_job(&mut self, tab_id: &str) {
        if let Some(mut job) = self.agent_title_jobs.remove(tab_id) {
            if let Some(cancel) = job.cancel.take() {
                let _ = cancel.send(());
            }
            if let Some((client, request)) = job.reply {
                self.client_write(
                    client,
                    error_response(request, &HostError::state("Title generation was canceled.")),
                );
            }
        }
    }
}

pub(super) fn job_matches(job: &AgentTitleJob, tab: &WorkspaceTabRecord) -> bool {
    tab.payload["agentTitleConversationId"].as_str() == Some(job.conversation.as_str())
        && tab.payload["agentTitleRevision"] == job.revision
        && (!job.automatic || !is_manual(tab))
}
