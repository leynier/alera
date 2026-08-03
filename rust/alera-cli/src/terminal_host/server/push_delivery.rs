use std::time::{Duration, Instant};

use chrono::{DateTime, Utc};
use serde_json::json;

use alera_core::runtime::{AutomationDefinition, AutomationRun, AutomationRunStatus};

use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::push_notifications::{
    grouped_events_by_category, PushEvent, PushLocation,
};

use super::{ServerActor, ServerCommand};

const PUSH_GROUP_DELAY: Duration = Duration::from_secs(3);
const PUSH_GROUP_MAX_DELAY: Duration = Duration::from_secs(10);

pub(crate) enum PushCommand {
    Flush {
        generation: u64,
    },
    DeliveryFinished {
        result: std::result::Result<usize, String>,
    },
}

impl ServerActor {
    pub(super) fn handle_push_command(&mut self, command: PushCommand) {
        match command {
            PushCommand::Flush { generation } => self.handle_push_flush(generation),
            PushCommand::DeliveryFinished { result } => self.handle_push_delivery_finished(result),
        }
    }

    pub(super) async fn queue_agent_push(
        &mut self,
        session_id: &str,
        agent_type: &str,
        state: AgentPresenceState,
        state_started_at: DateTime<Utc>,
        transitioned: bool,
    ) {
        let settings = match self.runtime_store.mobile_push_settings().await {
            Ok(settings) if settings.enabled => settings,
            _ => return,
        };
        let category_enabled = match state {
            AgentPresenceState::Waiting | AgentPresenceState::Blocked => settings.attention,
            AgentPresenceState::Done => settings.done,
            AgentPresenceState::Working => false,
        };
        if !category_enabled
            || !self.account_push.damper.should_deliver(
                session_id,
                state.as_str(),
                state_started_at,
                transitioned,
                Utc::now(),
            )
        {
            return;
        }
        let Some(location) = self.push_location_for_session(session_id).await else {
            return;
        };
        if let Some(event) =
            PushEvent::agent(agent_type, state.as_str(), location, state_started_at)
        {
            self.enqueue_push_event(event);
        }
    }

    pub(super) async fn queue_terminal_exit_push(
        &mut self,
        session_id: &str,
        exit_code: Option<i32>,
    ) {
        let settings = match self.runtime_store.mobile_push_settings().await {
            Ok(settings) if settings.enabled && settings.terminal_exit => settings,
            _ => return,
        };
        let _ = settings;
        let Some(location) = self.push_location_for_session(session_id).await else {
            return;
        };
        if !self
            .account_push
            .damper
            .should_deliver_terminal_exit(session_id, Utc::now())
        {
            return;
        }
        self.enqueue_push_event(PushEvent::terminal_exit(location, exit_code));
    }

    pub(super) async fn queue_gate_push(&mut self, task_id: &str, question: &str) {
        let settings = match self.runtime_store.mobile_push_settings().await {
            Ok(settings) if settings.enabled && settings.attention => settings,
            _ => return,
        };
        let _ = settings;
        let Some(location) = self.push_location_for_task(task_id).await else {
            return;
        };
        self.enqueue_push_event(PushEvent::decision_gate(task_id, question, location));
    }

    pub(super) async fn queue_escalation_push(&mut self, task_id: &str, subject: &str) {
        let settings = match self.runtime_store.mobile_push_settings().await {
            Ok(settings) if settings.enabled && settings.attention => settings,
            _ => return,
        };
        let _ = settings;
        let Some(location) = self.push_location_for_task(task_id).await else {
            return;
        };
        self.enqueue_push_event(PushEvent::escalation(task_id, subject, location));
    }

    pub(super) async fn queue_automation_push(
        &mut self,
        run: &AutomationRun,
        definition: &AutomationDefinition,
        status: AutomationRunStatus,
        summary: Option<&str>,
    ) {
        let settings = match self.runtime_store.mobile_push_settings().await {
            Ok(settings) if settings.enabled => settings,
            _ => return,
        };
        let attention = matches!(
            status,
            AutomationRunStatus::Failure
                | AutomationRunStatus::Blocked
                | AutomationRunStatus::Timeout
        );
        let enabled = if attention {
            settings.attention
        } else {
            status == AutomationRunStatus::Success && definition.notify_on_success && settings.done
        };
        if !enabled {
            return;
        }
        let workspace_id = run.workspace_id.clone().or_else(|| {
            run.target_identity
                .as_ref()
                .and_then(|identity| identity.workspace_id.clone())
        });
        let location = match workspace_id {
            Some(workspace_id) => self
                .push_location(run.session_id.clone(), workspace_id, run.tab_id.clone())
                .await
                .unwrap_or_else(|| PushLocation {
                    terminal_session_id: run.session_id.clone(),
                    workspace_id: None,
                    tab_id: run.tab_id.clone(),
                    project_name: None,
                    workspace_name: None,
                    tab_title: None,
                }),
            None => PushLocation {
                terminal_session_id: run.session_id.clone(),
                workspace_id: None,
                tab_id: run.tab_id.clone(),
                project_name: None,
                workspace_name: None,
                tab_title: None,
            },
        };
        let status_name = match status {
            AutomationRunStatus::Success => "success",
            AutomationRunStatus::Failure => "failure",
            AutomationRunStatus::Blocked => "blocked",
            AutomationRunStatus::Timeout => "timeout",
            _ => return,
        };
        self.enqueue_push_event(PushEvent::automation(
            &run.automation_id,
            &run.id,
            &definition.name,
            status_name,
            summary,
            location,
        ));
    }

    fn enqueue_push_event(&mut self, event: PushEvent) {
        if self.account_push.pending_events.is_empty() {
            self.account_push.batch_started = Some(Instant::now());
        }
        self.account_push.pending_events.push(event);
        self.account_push.flush_generation = self.account_push.flush_generation.wrapping_add(1);
        let generation = self.account_push.flush_generation;
        let elapsed = self
            .account_push
            .batch_started
            .map(|started| started.elapsed())
            .unwrap_or_default();
        let delay = PUSH_GROUP_DELAY.min(PUSH_GROUP_MAX_DELAY.saturating_sub(elapsed));
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            let _ = inbox.send(ServerCommand::Push(PushCommand::Flush { generation }));
        });
    }

    pub(super) fn handle_push_flush(&mut self, generation: u64) {
        if generation != self.account_push.flush_generation
            || self.account_push.pending_events.is_empty()
        {
            return;
        }
        let events =
            grouped_events_by_category(std::mem::take(&mut self.account_push.pending_events));
        self.account_push.batch_started = None;
        self.account_push.cloud_jobs += events.len();
        self.cancel_shutdown_timer();
        for event in events {
            let event = event.into_request(self.account_push.service.runtime_id());
            let service = self.account_push.service.clone();
            let inbox = self.inbox.clone();
            tokio::spawn(async move {
                let mut result = Ok(0);
                for (attempt, delay) in [
                    Duration::ZERO,
                    Duration::from_secs(1),
                    Duration::from_secs(3),
                ]
                .into_iter()
                .enumerate()
                {
                    if !delay.is_zero() {
                        tokio::time::sleep(delay).await;
                    }
                    match service.send_event(&event).await {
                        Ok(active_subscriptions) => {
                            result = Ok(active_subscriptions);
                            break;
                        }
                        Err(error) => {
                            result = Err(error);
                            if attempt == 2 {
                                break;
                            }
                        }
                    }
                }
                let _ = inbox.send(ServerCommand::Push(PushCommand::DeliveryFinished {
                    result: result.map_err(|error| error.to_string()),
                }));
            });
        }
    }

    pub(super) fn handle_push_delivery_finished(
        &mut self,
        result: std::result::Result<usize, String>,
    ) {
        self.account_push.cloud_jobs = self.account_push.cloud_jobs.saturating_sub(1);
        match result {
            Ok(active_subscriptions) => {
                self.account_push.active_subscriptions = if self.account_push.push_enabled {
                    active_subscriptions
                } else {
                    0
                };
            }
            Err(error) => {
                eprintln!("alera push delivery failed: {error}");
                self.broadcast_authenticated(crate::terminal_host::protocol::event(
                    "mobilePushDeliveryFailed",
                    json!({ "message": error }),
                ));
            }
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) fn forget_push_session(&mut self, session_id: &str) {
        self.account_push.damper.forget_session(session_id);
    }

    async fn push_location_for_session(&self, session_id: &str) -> Option<PushLocation> {
        let session = self.sessions.get(session_id)?;
        self.push_location(
            Some(session_id.to_string()),
            session.workspace_id.clone(),
            Some(session.tab_id.clone()),
        )
        .await
    }

    async fn push_location_for_task(&self, task_id: &str) -> Option<PushLocation> {
        let task = self
            .runtime_store
            .orchestration_task_by_id(task_id)
            .await
            .ok()
            .flatten()?;
        let session_id = self
            .runtime_store
            .active_orchestration_dispatch_for_task(task_id)
            .await
            .ok()
            .flatten()
            .and_then(|dispatch| dispatch.assignee_handle)
            .or(task.created_by_terminal_handle);
        let tab_id = session_id
            .as_ref()
            .and_then(|handle| self.sessions.get(handle))
            .map(|session| session.tab_id.clone());
        self.push_location(session_id, task.workspace_id, tab_id)
            .await
    }

    async fn push_location(
        &self,
        terminal_session_id: Option<String>,
        workspace_id: String,
        tab_id: Option<String>,
    ) -> Option<PushLocation> {
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .ok()
            .flatten();
        let project_name = match workspace.as_ref() {
            Some(workspace) => self
                .runtime_store
                .find_project(&workspace.project_id)
                .await
                .ok()
                .flatten()
                .map(|project| project.name),
            None => None,
        };
        let tab_title = match tab_id.as_deref() {
            Some(tab_id) => self
                .runtime_store
                .find_workspace_tab(tab_id)
                .await
                .ok()
                .flatten()
                .map(|tab| tab.title),
            None => None,
        };
        Some(PushLocation {
            terminal_session_id,
            workspace_id: Some(workspace_id),
            tab_id,
            project_name,
            workspace_name: workspace.map(|workspace| workspace.name),
            tab_title,
        })
    }
}
