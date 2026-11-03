//! Follows the chat turn of a dispatched agent chat automation run
//! (`automationAgentChatTargetV1`) and reports its end to the actor.

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};
use std::time::Duration as StdDuration;

use alera_core::runtime::{AutomationRun, AutomationRunStatus, RuntimeStore};
use tokio::sync::broadcast;

use super::agent_chat_runtime::events::ChatRuntimeEvent;
use super::agent_chat_runtime::AgentChatRuntime;
use super::automation_agent_chat_runs::AgentChatRunEvent;
use super::{ServerActor, ServerCommand};

/// How often a watcher re-reads the turn when no chat event arrives.
const TURN_POLL: StdDuration = StdDuration::from_secs(5);

/// Runs whose turn a watcher follows, so a reconcile never starts two.
fn watched() -> &'static Mutex<HashSet<String>> {
    static WATCHED: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    WATCHED.get_or_init(Mutex::default)
}

impl ServerActor {
    /// Follows the chat turn of a dispatched run until it ends. Called again
    /// on every automation tick, so a restart picks the run back up.
    pub(super) fn watch_agent_chat_run(&self, run: &AutomationRun) {
        let (Some(chat_id), Some(client_message_id)) =
            (run.chat_id.clone(), run.client_message_id.clone())
        else {
            return;
        };
        if !matches!(
            run.status,
            AutomationRunStatus::Dispatched | AutomationRunStatus::Dispatching
        ) || !watched()
            .lock()
            .is_ok_and(|mut set| set.insert(run.id.clone()))
        {
            return;
        }
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let events = self
            .agent_chat_runtime
            .as_ref()
            .map(AgentChatRuntime::subscribe);
        let run_id = run.id.clone();
        tokio::spawn(async move {
            let ended =
                wait_for_turn_end(&store, events, &run_id, &chat_id, &client_message_id).await;
            if let Ok(mut set) = watched().lock() {
                set.remove(&run_id);
            }
            if let Some((status, error)) = ended {
                let _ = inbox
                    .send_wait(ServerCommand::AutomationAgentChat(
                        AgentChatRunEvent::TurnEnded {
                            run_id,
                            client_message_id,
                            status,
                            error,
                        },
                    ))
                    .await;
            }
        });
    }
}

/// The end of the turn that consumed `client_message_id`: `(status, error)`,
/// or `None` once the run no longer waits on it.
pub(super) async fn wait_for_turn_end(
    store: &RuntimeStore,
    mut events: Option<broadcast::Receiver<ChatRuntimeEvent>>,
    run_id: &str,
    chat_id: &str,
    client_message_id: &str,
) -> Option<(String, Option<String>)> {
    loop {
        match store.find_automation_run(run_id).await {
            Ok(Some(run))
                if !run.status.is_final()
                    && run.client_message_id.as_deref() == Some(client_message_id) => {}
            Ok(_) => return None,
            Err(error) => tracing::debug!(run_id, "agent chat run read failed: {error}"),
        }
        if let Some(end) = turn_end(store, chat_id, client_message_id).await {
            return Some(end);
        }
        let Some(receiver) = events.as_mut() else {
            tokio::time::sleep(TURN_POLL).await;
            continue;
        };
        let _ = tokio::time::timeout(TURN_POLL, async {
            loop {
                match receiver.recv().await {
                    Ok(ChatRuntimeEvent::Changed {
                        chat_id: changed, ..
                    })
                    | Ok(ChatRuntimeEvent::Deleted {
                        chat_id: changed, ..
                    }) if changed == chat_id => return,
                    Ok(_) => {}
                    Err(broadcast::error::RecvError::Lagged(_)) => return,
                    Err(broadcast::error::RecvError::Closed) => {
                        tokio::time::sleep(TURN_POLL).await;
                        return;
                    }
                }
            }
        })
        .await;
    }
}

async fn turn_end(
    store: &RuntimeStore,
    chat_id: &str,
    client_message_id: &str,
) -> Option<(String, Option<String>)> {
    match store
        .agent_chat_turn_for_client_message(chat_id, client_message_id)
        .await
    {
        Ok(Some(turn)) => {
            let status = turn["status"].as_str().unwrap_or("running");
            if !matches!(status, "completed" | "failed" | "interrupted" | "cancelled") {
                return None;
            }
            let error = turn["errorMessage"]
                .as_str()
                .or_else(|| turn["reason"].as_str())
                .map(str::to_owned);
            Some((status.to_owned(), error))
        }
        Ok(None) => {
            if store
                .is_agent_chat_message_cancelled(chat_id, client_message_id)
                .await
                .unwrap_or(false)
            {
                return Some((
                    "cancelled".into(),
                    Some("The queued message was cancelled.".into()),
                ));
            }
            match store.agent_chat(chat_id).await {
                Ok(None) => Some(("failed".into(), Some("The chat was deleted.".into()))),
                _ => None,
            }
        }
        Err(_) => None,
    }
}
