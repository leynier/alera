//! Agent chat automation runs (`automationAgentChatTargetV1`). A run posts
//! its prompt into an agent chat as a message with `origin.kind =
//! automation`, and ends when the chat turn that consumed the message ends,
//! matched by its client message id. There is no heartbeat: the turn is the
//! run. The chat runtime is only called away from the actor, so a send never
//! waits on the actor that handles the chat's events.
//!
//! A run whose post never reported back (the runtime stopped between saving
//! the run and the `Dispatched` event) is recovered on startup and on every
//! automation tick: once no post for it is in flight in this process and
//! [STUCK_POST_GRACE_SECONDS] have passed, the chat is searched for its
//! client message. Found, the run is dispatched and watched; missing, the
//! run fails through the usual retry policy.

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

use alera_core::runtime::{
    prompt_value_map, render_prompt_template, AutomationActor, AutomationActorKind,
    AutomationDefinition, AutomationRun, AutomationRunStatus,
};
use chrono::{Duration, Utc};
use serde_json::{json, Value};

use super::agent_chat_runtime::commands::{CallerCtx, SendInput};
use super::agent_chat_runtime::{AgentChatRuntime, CreateChatInput};
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};

/// How long a run may wait for its post to report back before recovery
/// looks for its message in the chat.
pub(super) const STUCK_POST_GRACE_SECONDS: i64 = 120;

/// Why recovery fails a run whose message never reached its chat.
pub(super) const POST_LOST_REASON: &str =
    "The runtime stopped before the scheduled message reached the chat";

/// Runs whose post is in flight in this process, so recovery never touches a
/// slow post.
fn posting() -> &'static Mutex<HashSet<String>> {
    static POSTING: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    POSTING.get_or_init(Mutex::default)
}

fn is_posting(run_id: &str) -> bool {
    posting().lock().is_ok_and(|set| set.contains(run_id))
}

fn set_posting(run_id: &str, in_flight: bool) {
    if let Ok(mut set) = posting().lock() {
        if in_flight {
            set.insert(run_id.to_owned());
        } else {
            set.remove(run_id);
        }
    }
}

/// What a spawned agent chat job reports back to the actor.
#[derive(Debug)]
pub(crate) enum AgentChatRunEvent {
    /// The prompt reached the chat (`Ok(chat id)`) or could not be posted.
    Dispatched {
        run_id: String,
        client_message_id: String,
        result: HostResult<String>,
    },
    /// The chat turn that consumed the run's message ended.
    TurnEnded {
        run_id: String,
        client_message_id: String,
        status: String,
        error: Option<String>,
    },
    /// A scheduled task verb (`chatOrchestrationSchedulesV1`) for the actor.
    Schedule {
        op: super::chat_orchestration::ScheduleOp,
        reply: tokio::sync::oneshot::Sender<HostResult<Value>>,
    },
}

impl AgentChatRunEvent {
    pub(crate) fn approximate_bytes(&self) -> usize {
        match self {
            Self::Dispatched {
                run_id,
                client_message_id,
                ..
            } => run_id.len() + client_message_id.len() + 256,
            Self::TurnEnded {
                run_id,
                client_message_id,
                status,
                error,
            } => {
                run_id.len()
                    + client_message_id.len()
                    + status.len()
                    + error.as_ref().map_or(0, String::len)
            }
            Self::Schedule { op, .. } => match op {
                super::chat_orchestration::ScheduleOp::Save { definition, .. } => {
                    serde_json::to_vec(definition).map_or(0, |bytes| bytes.len())
                }
                _ => 256,
            },
        }
    }
}

/// Whether a run belongs to an agent chat target.
pub(super) fn is_agent_chat_run(run: &AutomationRun) -> bool {
    run.client_message_id.is_some()
        || run
            .definition_snapshot
            .as_ref()
            .is_some_and(|definition| definition.target.agent_chat().is_some())
}

/// The post a run makes, built on the actor and sent from a task.
struct ChatPost {
    automation_id: String,
    automation_name: String,
    run_id: String,
    run_number: i64,
    chat_id: Option<String>,
    create: CreateChatInput,
    text: String,
    client_message_id: String,
    runtime_mode_ceiling: Option<String>,
}

impl ChatPost {
    async fn send(self, runtime: &AgentChatRuntime) -> HostResult<String> {
        let ctx = CallerCtx {
            scope: "automation".into(),
            actor: format!("automation:{}", self.automation_id),
            mobile: false,
        };
        let chat_id = match self.chat_id {
            Some(chat_id) => chat_id,
            None => runtime
                .create(self.create, CallerCtx::runtime(), None)
                .await?
                .get("chatId")
                .and_then(Value::as_str)
                .map(str::to_owned)
                .ok_or_else(|| HostError::state("The chat runtime did not return a chat id."))?,
        };
        let snapshot = runtime.snapshot(&chat_id).await?;
        if snapshot["archived"] == true {
            return Err(HostError::conflict(
                "chatArchived",
                "The scheduled task's chat is archived.",
                json!({"chatId": chat_id}),
            ));
        }
        runtime
            .send(
                &chat_id,
                SendInput {
                    client_message_id: self.client_message_id,
                    text: self.text,
                    attachments: Vec::new(),
                    delivery: "queue".into(),
                    model: None,
                    reasoning_effort: None,
                    interaction_mode: None,
                    runtime_mode_ceiling: self.runtime_mode_ceiling,
                    origin: Some(json!({
                        "kind": "automation",
                        "automationId": self.automation_id,
                        "automationName": self.automation_name,
                        "runId": self.run_id,
                        "runNumber": self.run_number,
                    })),
                },
                ctx,
            )
            .await?;
        Ok(chat_id)
    }
}

impl ServerActor {
    /// Starts an admitted agent chat run: one attempt, the rendered prompt,
    /// and the post from a task.
    pub(super) async fn dispatch_agent_chat_run(
        &mut self,
        definition: &AutomationDefinition,
        run: AutomationRun,
    ) {
        let Some(spec) = definition.target.agent_chat() else {
            return;
        };
        let Some(runtime) = self.agent_chat_runtime.clone() else {
            self.block_run(&run, "Agent chats are unavailable on this runtime")
                .await;
            return;
        };
        let location = match self.automation_target_location(definition).await {
            Ok(location) => location,
            Err(error) => {
                self.block_run(&run, &error.wire_message()).await;
                return;
            }
        };
        let mut run = match self
            .runtime_store
            .begin_automation_attempt(&run.id, definition.retry_max_attempts)
            .await
        {
            Ok(run) => run,
            Err(error) => {
                self.fail_run(&run, error.to_string()).await;
                return;
            }
        };
        let workspace = location.workspace.as_ref();
        let values = prompt_value_map(
            definition,
            &run,
            workspace.map(|w| (w.id.as_str(), w.name.as_str(), w.path.as_str())),
            Some((location.project.id.as_str(), location.project.name.as_str())),
        );
        let rendered = match render_prompt_template(definition, &values) {
            Ok(rendered) => rendered,
            Err(error) => {
                self.block_run(&run, &error).await;
                return;
            }
        };
        let client_message_id = format!(
            "automation:{}:{}",
            run.id,
            run.attempt_id.as_deref().unwrap_or("1")
        );
        run.rendered_prompt = Some(rendered.clone());
        run.client_message_id = Some(client_message_id.clone());
        run.chat_id = spec.chat_id.map(str::to_owned);
        run.workspace_id = Some(spec.workspace_id.to_owned());
        run.actor_kind
            .get_or_insert(AutomationActorKind::ManagedAgent);
        run.updated_at = Utc::now();
        if let Err(error) = self.runtime_store.save_automation_run(&run).await {
            self.fail_run(&run, error.to_string()).await;
            return;
        }
        self.broadcast_automation_run_changed(&run);
        let post = ChatPost {
            automation_id: definition.id.clone(),
            automation_name: definition.name.clone(),
            run_id: run.id.clone(),
            run_number: run.number,
            chat_id: spec.chat_id.map(str::to_owned),
            create: CreateChatInput {
                workspace_id: spec.workspace_id.to_owned(),
                provider: spec.provider.map(str::to_owned),
                provider_instance_id: spec.provider_instance_id.map(str::to_owned),
                model: spec.model.map(str::to_owned),
                reasoning_effort: spec.reasoning_effort.map(str::to_owned),
                runtime_mode: spec.runtime_mode_ceiling.map(str::to_owned),
                interaction_mode: None,
                title: Some(definition.name.clone()),
                metadata: Some(json!({
                    "originKind": "automation",
                    "automationId": definition.id,
                    "runId": run.id,
                })),
            },
            text: rendered,
            client_message_id: client_message_id.clone(),
            runtime_mode_ceiling: spec.runtime_mode_ceiling.map(str::to_owned),
        };
        let inbox = self.inbox.clone();
        let run_id = run.id.clone();
        set_posting(&run_id, true);
        tokio::spawn(async move {
            let result = post.send(&runtime).await;
            let _ = inbox
                .send_wait(ServerCommand::AutomationAgentChat(
                    AgentChatRunEvent::Dispatched {
                        run_id,
                        client_message_id,
                        result,
                    },
                ))
                .await;
        });
    }

    pub(super) async fn handle_agent_chat_run_event(&mut self, event: AgentChatRunEvent) {
        match event {
            AgentChatRunEvent::Dispatched {
                run_id,
                client_message_id,
                result,
            } => {
                set_posting(&run_id, false);
                self.finish_agent_chat_dispatch(&run_id, &client_message_id, result)
                    .await
            }
            AgentChatRunEvent::TurnEnded {
                run_id,
                client_message_id,
                status,
                error,
            } => {
                self.finish_agent_chat_run(&run_id, &client_message_id, &status, error)
                    .await
            }
            AgentChatRunEvent::Schedule { op, reply } => {
                let result = Box::pin(self.apply_schedule_op(op)).await;
                let _ = reply.send(result);
            }
        }
    }

    async fn current_agent_chat_run(
        &self,
        run_id: &str,
        client_message_id: &str,
    ) -> Option<AutomationRun> {
        self.runtime_store
            .find_automation_run(run_id)
            .await
            .ok()
            .flatten()
            .filter(|run| {
                !run.status.is_final()
                    && run.client_message_id.as_deref() == Some(client_message_id)
            })
    }

    async fn finish_agent_chat_dispatch(
        &mut self,
        run_id: &str,
        client_message_id: &str,
        result: HostResult<String>,
    ) {
        let Some(run) = self.current_agent_chat_run(run_id, client_message_id).await else {
            return;
        };
        let chat_id = match result {
            Ok(chat_id) => chat_id,
            Err(error) if refused_by_chat(&error) => {
                self.block_run(&run, &error.wire_message()).await;
                return;
            }
            Err(error) => {
                self.fail_run(&run, error.wire_message()).await;
                return;
            }
        };
        self.mark_agent_chat_run_dispatched(run, chat_id).await;
    }

    async fn mark_agent_chat_run_dispatched(&mut self, mut run: AutomationRun, chat_id: String) {
        run.chat_id = Some(chat_id.clone());
        run.status = AutomationRunStatus::Dispatched;
        if let Some(identity) = run.target_identity.as_mut() {
            identity.conversation_id = Some(chat_id);
        }
        run.updated_at = Utc::now();
        match self.runtime_store.save_automation_run(&run).await {
            Ok(saved) => {
                self.broadcast_automation_run_changed(&saved);
                self.watch_agent_chat_run(&saved);
            }
            Err(error) => tracing::warn!(
                run_id = run.id,
                "could not record agent chat dispatch: {error}"
            ),
        }
    }

    /// Picks an active agent chat run back up on startup and on every tick:
    /// a dispatched run is watched until its turn ends (also one that ended
    /// while the runtime was down), and a run whose post never reported back
    /// is resolved from the chat itself.
    pub(super) async fn reconcile_agent_chat_run(&mut self, run: AutomationRun) {
        if run.status.is_final() {
            return;
        }
        if run.status == AutomationRunStatus::Dispatched {
            self.watch_agent_chat_run(&run);
            return;
        }
        // A pending run, even one with an earlier attempt's message, waits on
        // the scheduler; only a started attempt has a post to account for.
        if run.status != AutomationRunStatus::Dispatching
            || run.started_at.is_none()
            || is_posting(&run.id)
            || Utc::now().signed_duration_since(run.updated_at)
                < Duration::seconds(STUCK_POST_GRACE_SECONDS)
        {
            return;
        }
        let found = match run.client_message_id.as_deref() {
            // The attempt began but its message was never recorded.
            None => Ok(None),
            Some(client_message_id) => {
                self.runtime_store
                    .agent_chat_holding_client_message(run.chat_id.as_deref(), client_message_id)
                    .await
            }
        };
        match found {
            Ok(Some(chat_id)) => self.mark_agent_chat_run_dispatched(run, chat_id).await,
            Ok(None) => self.fail_run(&run, POST_LOST_REASON.into()).await,
            Err(error) => tracing::warn!(
                run_id = run.id,
                "could not look up an agent chat run's message: {error}"
            ),
        }
    }

    async fn finish_agent_chat_run(
        &mut self,
        run_id: &str,
        client_message_id: &str,
        status: &str,
        error: Option<String>,
    ) {
        let Some(current) = self.current_agent_chat_run(run_id, client_message_id).await else {
            return;
        };
        let Some(definition) = current.definition_snapshot.clone().or(self
            .runtime_store
            .find_automation(&current.automation_id)
            .await
            .ok()
            .flatten())
        else {
            return;
        };
        let (status, summary) = match status {
            "completed" => (AutomationRunStatus::Success, "The chat turn completed."),
            "failed" => (AutomationRunStatus::Failure, "The chat turn failed."),
            _ => {
                let reason = error.unwrap_or_else(|| "The chat turn was stopped.".into());
                match self
                    .set_automation_run_status(run_id, AutomationRunStatus::Cancelled, Some(reason))
                    .await
                {
                    Ok(run) => self.broadcast_automation_run_changed(&run),
                    Err(error) => {
                        tracing::warn!(run_id, "could not cancel agent chat run: {error}")
                    }
                }
                return;
            }
        };
        let actor = AutomationActor {
            kind: AutomationActorKind::ManagedAgent,
            id: current.chat_id.clone(),
            label: Some("Alera agent chat".into()),
        };
        match self
            .runtime_store
            .complete_automation_run(run_id, status, Some(summary.into()), error, actor)
            .await
        {
            Ok(run) => {
                self.after_automation_run_completed(current.trigger, &definition, &run, status)
                    .await
            }
            Err(error) => tracing::warn!(run_id, "could not complete agent chat run: {error}"),
        }
    }
}

/// Whether the chat refused the post for a reason a retry cannot fix.
fn refused_by_chat(error: &HostError) -> bool {
    matches!(
        error,
        HostError::Conflict { code, .. } if matches!(
            code.as_str(),
            "chatArchived"
                | "mode_ceiling"
                | "providerRequired"
                | "providerUnavailable"
                | "chatNotFound"
                | "not_found"
        )
    )
}

#[cfg(test)]
#[path = "automation_agent_chat_runs_tests.rs"]
mod tests;
