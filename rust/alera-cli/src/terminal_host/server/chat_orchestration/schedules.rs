//! Scheduled tasks (`chatOrchestrationSchedulesV1`), ported from T3 Code's
//! `schedule_task`, `list_scheduled_tasks`, `delete_scheduled_task` and
//! `run_scheduled_task_now`. A scheduled task is an Alera automation with an
//! `agentChat` target: by default every run posts its prompt into the chat
//! that scheduled it, capped at that chat's runtime mode. Alera has no
//! inbound path, so there are no webhook triggers. Saving, trashing and
//! running go through the host actor ([`ScheduleHost`]), which owns
//! automation readiness, the scheduler and dispatch.

use alera_core::runtime::{
    automation_from_input, AutomationActor, AutomationActorKind, AutomationDefinition,
    AutomationState, AutomationTarget,
};
use async_trait::async_trait;
use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::authorization::{mode_rank, OrchestrationCaller};
use super::schedule_input::{automation_schedule, ScheduleTaskInput};
use super::service::ChatOrchestrationService;

/// What the host does for a scheduled task verb.
#[derive(Debug)]
pub(crate) enum ScheduleOp {
    /// Validates and stores a definition; answers the saved definition.
    Save {
        definition: Box<AutomationDefinition>,
        actor: AutomationActor,
    },
    /// Moves the automation to the trash; answers the trashed definition.
    Trash { id: String, actor: AutomationActor },
    /// Starts a manual run; answers the run.
    RunNow { id: String, actor: AutomationActor },
}

#[async_trait]
pub(crate) trait ScheduleHost: Send + Sync + 'static {
    async fn apply(&self, op: ScheduleOp) -> HostResult<Value>;
}

pub(crate) const CHILD_CANNOT_SCHEDULE: &str = "This chat is a delegated child, so it may only list scheduled tasks. Its parent chat owns scheduling: report back instead.";

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

/// The lower of two runtime modes.
fn lower_mode<'a>(left: &'a str, right: Option<&'a str>) -> &'a str {
    match right {
        Some(right) if mode_rank(right).unwrap_or(0) < mode_rank(left).unwrap_or(0) => right,
        _ => left,
    }
}

fn actor(caller: &OrchestrationCaller) -> AutomationActor {
    match &caller.bound {
        Some(bound) => AutomationActor {
            kind: AutomationActorKind::ManagedAgent,
            id: Some(format!("chat:{}", bound.chat_id)),
            label: Some("Agent chat".into()),
        },
        None => AutomationActor {
            kind: AutomationActorKind::LocalCli,
            id: Some(caller.ctx.actor.clone()),
            label: Some("Alera CLI".into()),
        },
    }
}

/// The task's title: given, or the prompt's first line.
fn title_for(title: Option<&str>, prompt: &str) -> String {
    if let Some(title) = title {
        return title.to_owned();
    }
    let line = prompt.lines().next().unwrap_or("Scheduled task").trim();
    let mut title: String = line.chars().take(60).collect();
    if line.chars().count() > 60 {
        title.push_str("...");
    }
    if title.is_empty() {
        "Scheduled task".into()
    } else {
        title
    }
}

impl ChatOrchestrationService {
    pub(super) fn schedule_host(&self) -> HostResult<&dyn ScheduleHost> {
        self.schedules.as_deref().ok_or_else(|| {
            HostError::conflict(
                "unsupported",
                "Scheduled tasks are unavailable on this runtime.",
                json!({}),
            )
        })
    }

    /// The chat a verb acts for: the bound chat, or the one a person names.
    fn calling_chat(caller: &OrchestrationCaller, chat_id: Option<&str>) -> HostResult<String> {
        match (&caller.bound, chat_id) {
            (Some(bound), _) => Ok(bound.chat_id.clone()),
            (None, Some(chat_id)) => Ok(chat_id.to_owned()),
            (None, None) => Err(HostError::format(
                "chatId is required outside an agent chat",
            )),
        }
    }

    pub(super) async fn require_not_child(&self, caller: &OrchestrationCaller) -> HostResult<()> {
        let Some(bound) = &caller.bound else {
            return Ok(());
        };
        if self.is_child_chat(&bound.chat_id).await? {
            return Err(HostError::conflict(
                "childCannotSchedule",
                CHILD_CANNOT_SCHEDULE,
                json!({}),
            ));
        }
        Ok(())
    }

    /// The project of a chat's workspace.
    pub(super) async fn chat_project(&self, workspace_id: &str) -> HostResult<Option<String>> {
        Ok(self
            .store
            .find_workspace(workspace_id)
            .await
            .map_err(state_error)?
            .map(|workspace| workspace.project_id))
    }

    /// A scheduled task the caller may change: an agent chat automation, in
    /// the bound chat's project.
    pub(super) async fn caller_scheduled_task(
        &self,
        id: &str,
        caller: &OrchestrationCaller,
    ) -> HostResult<AutomationDefinition> {
        let definition = self
            .store
            .find_automation(id)
            .await
            .map_err(state_error)?
            .filter(|definition| {
                definition.target.agent_chat().is_some()
                    && definition.state != AutomationState::Trashed
            })
            .ok_or_else(|| {
                HostError::conflict(
                    "scheduledTaskNotFound",
                    "No scheduled task has this scheduledTaskId.",
                    json!({"scheduledTaskId": id}),
                )
            })?;
        if let Some(bound) = &caller.bound {
            let snapshot = self.runtime.snapshot(&bound.chat_id).await?;
            let project = self
                .chat_project(snapshot["workspaceId"].as_str().unwrap_or_default())
                .await?;
            if project.is_none() || definition.project_id != project {
                return Err(HostError::conflict(
                    "scheduledTaskNotFound",
                    "No scheduled task with this scheduledTaskId belongs to this chat's project.",
                    json!({"scheduledTaskId": id}),
                ));
            }
        }
        Ok(definition)
    }

    pub(super) async fn schedule_task(
        &self,
        input: ScheduleTaskInput,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let host = self.schedule_host()?;
        self.require_not_child(caller).await?;
        let chat_id = Self::calling_chat(caller, input.chat_id.as_deref())?;
        let snapshot = self.runtime.snapshot(&chat_id).await?;
        let workspace_id = snapshot["workspaceId"]
            .as_str()
            .ok_or_else(|| HostError::state("The calling chat has no workspace."))?
            .to_owned();
        let chat_mode = snapshot["session"]["runtimeMode"]
            .as_str()
            .unwrap_or("approval-required");
        let ceiling = lower_mode(
            chat_mode,
            caller
                .bound
                .as_ref()
                .map(|bound| bound.runtime_mode.as_str()),
        )
        .to_owned();
        let target = |bind: bool| AutomationTarget::AgentChat {
            chat_id: bind.then(|| chat_id.clone()),
            workspace_id: workspace_id.clone(),
            runtime_mode_ceiling: Some(ceiling.clone()),
            provider: snapshot["provider"].as_str().map(str::to_owned),
            provider_instance_id: snapshot["providerInstanceId"].as_str().map(str::to_owned),
            model: snapshot["session"]["model"].as_str().map(str::to_owned),
            reasoning_effort: snapshot["session"]["reasoningEffort"]
                .as_str()
                .map(str::to_owned),
        };
        let now = Utc::now();
        let actor = actor(caller);
        let definition = match &input.scheduled_task_id {
            Some(id) => {
                let mut definition = self.caller_scheduled_task(id, caller).await?;
                if !definition.state.is_editable() {
                    return Err(HostError::state(
                        "This scheduled task is finished; schedule a new one",
                    ));
                }
                if let Some(prompt) = &input.prompt {
                    definition.prompt_template = prompt.clone();
                }
                if let Some(title) = &input.title {
                    definition.name = title.clone();
                }
                if let Some(schedule) = &input.schedule {
                    definition.schedule = automation_schedule(schedule, now)?;
                    definition.schedule_cursor_at = Some(now);
                }
                if let Some(enabled) = input.enabled {
                    definition.state = if enabled {
                        AutomationState::Active
                    } else {
                        AutomationState::Paused
                    };
                }
                if let Some(bind) = input.bind_to_current_chat {
                    definition.target = target(bind);
                } else if let AutomationTarget::AgentChat {
                    runtime_mode_ceiling,
                    ..
                } = &mut definition.target
                {
                    // An update never raises the ceiling past the updater's mode.
                    let lowered = lower_mode(&ceiling, runtime_mode_ceiling.as_deref()).to_owned();
                    *runtime_mode_ceiling = Some(lowered);
                }
                definition
            }
            None => {
                let prompt = input.prompt.clone().unwrap_or_default();
                let schedule = automation_schedule(
                    input.schedule.as_ref().expect("parser requires a schedule"),
                    now,
                )?;
                let request_key = input
                    .request_id
                    .as_ref()
                    .map(|request_id| format!("chat-schedule:{chat_id}:{request_id}"));
                if let Some(key) = &request_key {
                    if let Some(saved) = self
                        .store
                        .automation_by_request_key(key)
                        .await
                        .map_err(state_error)?
                    {
                        return self.scheduled_task_view(&saved).await;
                    }
                }
                let state = if input.enabled == Some(false) {
                    "paused"
                } else {
                    "active"
                };
                let mut definition = automation_from_input(
                    &json!({
                        "name": title_for(input.title.as_deref(), &prompt),
                        "description": "Scheduled from an agent chat.",
                        "projectId": self.chat_project(&workspace_id).await?,
                        "promptTemplate": prompt,
                        "schedule": schedule,
                        "target": target(input.bind_to_current_chat != Some(false)),
                        "state": state,
                        "originWorkspaceId": workspace_id,
                    }),
                    actor.clone(),
                )
                .map_err(|error| HostError::format(error.to_string()))?;
                definition.creation_request_key = request_key;
                definition
            }
        };
        let saved = host
            .apply(ScheduleOp::Save {
                definition: Box::new(definition),
                actor,
            })
            .await?;
        let saved: AutomationDefinition = serde_json::from_value(saved).map_err(state_error)?;
        self.scheduled_task_view(&saved).await
    }

    pub(super) async fn delete_scheduled_task(
        &self,
        id: &str,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let host = self.schedule_host()?;
        self.require_not_child(caller).await?;
        self.caller_scheduled_task(id, caller).await?;
        host.apply(ScheduleOp::Trash {
            id: id.to_owned(),
            actor: actor(caller),
        })
        .await?;
        Ok(json!({"scheduledTaskId": id, "deleted": true, "state": "trashed"}))
    }

    /// Starts a run now and answers its chat. For a task that opens a new
    /// chat per run, the chat id appears once the post lands, so this waits
    /// a few seconds for it.
    pub(super) async fn run_scheduled_task_now(
        &self,
        id: &str,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let host = self.schedule_host()?;
        self.require_not_child(caller).await?;
        let definition = self.caller_scheduled_task(id, caller).await?;
        let run = host
            .apply(ScheduleOp::RunNow {
                id: id.to_owned(),
                actor: actor(caller),
            })
            .await?;
        let run_id = run["id"].as_str().unwrap_or_default().to_owned();
        let mut current = run;
        for _ in 0..40 {
            if current["chatId"].is_string() || current["status"] != "dispatching" {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
            match self.store.find_automation_run(&run_id).await {
                Ok(Some(run)) => current = serde_json::to_value(run).map_err(state_error)?,
                _ => break,
            }
        }
        let chat_id = current["chatId"].as_str().map(str::to_owned).or_else(|| {
            definition
                .target
                .agent_chat()
                .and_then(|spec| spec.chat_id.map(str::to_owned))
        });
        let view = self.scheduled_task_view(&definition).await?;
        Ok(json!({
            "scheduledTaskId": id,
            "runId": run_id,
            "runNumber": current["number"],
            "status": current["status"],
            "chatId": chat_id,
            "lastRunStatus": view["lastRunStatus"],
            "nextRunAt": view["nextRunAt"],
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_lower_mode_wins_and_titles_come_from_the_prompt() {
        assert_eq!(
            lower_mode("full-access", Some("auto-accept-edits")),
            "auto-accept-edits"
        );
        assert_eq!(
            lower_mode("approval-required", Some("full-access")),
            "approval-required"
        );
        assert_eq!(lower_mode("auto", None), "auto");
        assert_eq!(
            title_for(None, "Check the deploy\nthen report"),
            "Check the deploy"
        );
        assert_eq!(title_for(Some("Nightly"), "x"), "Nightly");
        assert!(title_for(None, &"a".repeat(80)).ends_with("..."));
    }
}
