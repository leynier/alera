//! How a scheduled task (`chatOrchestrationSchedulesV1`) reads to an agent:
//! T3 Code's task shape over an Alera automation with an `agentChat` target.

use alera_core::runtime::{
    automation_cursor, next_occurrence, AutomationDefinition, AutomationRunStatus,
    AutomationSchedule, AutomationState,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::authorization::OrchestrationCaller;
use super::service::ChatOrchestrationService;

/// The most tasks one list answers.
const LIST_LIMIT: usize = 100;

/// `schedule` as T3 Code reads it. A cron that is a time of day on some
/// weekdays reads back as `fixed_time`; any other cron as `cron`.
pub(crate) fn schedule_view(schedule: &AutomationSchedule) -> Value {
    match schedule {
        AutomationSchedule::Interval {
            every_seconds,
            anchor,
        } => json!({
            "type": "interval",
            "everyMs": every_seconds * 1000,
            "anchor": anchor,
        }),
        AutomationSchedule::Recurring { cron, timezone, .. } => fixed_time_view(cron, timezone)
            .unwrap_or_else(|| json!({"type": "cron", "cron": cron, "timezone": timezone})),
        AutomationSchedule::OneTime { at, timezone } => {
            json!({"type": "once", "at": at, "timezone": timezone})
        }
    }
}

fn fixed_time_view(cron: &str, timezone: &str) -> Option<Value> {
    let fields: Vec<&str> = cron.split_whitespace().collect();
    let [minute, hour, "*", "*", days] = fields.as_slice() else {
        return None;
    };
    let minute: u32 = minute.parse().ok().filter(|minute| *minute < 60)?;
    let hour: u32 = hour.parse().ok().filter(|hour| *hour < 24)?;
    let mut view = json!({
        "type": "fixed_time",
        "timeOfDay": format!("{hour:02}:{minute:02}"),
        "timezone": timezone,
    });
    if *days != "*" {
        let weekdays = days
            .split(',')
            .map(|day| day.parse::<u32>().ok().filter(|day| *day <= 6))
            .collect::<Option<Vec<_>>>()?;
        view["weekdays"] = json!(weekdays);
    }
    Some(view)
}

fn last_run_status(status: Option<AutomationRunStatus>) -> &'static str {
    match status {
        None => "never",
        Some(status) if !status.is_final() => "running",
        Some(AutomationRunStatus::Success) => "succeeded",
        Some(
            AutomationRunStatus::PrecheckSkipped
            | AutomationRunStatus::MisfireSkipped
            | AutomationRunStatus::OverlapSkipped
            | AutomationRunStatus::QueueLimitSkipped,
        ) => "skipped",
        Some(AutomationRunStatus::Cancelled) => "cancelled",
        Some(_) => "failed",
    }
}

impl ChatOrchestrationService {
    pub(super) async fn scheduled_task_view(
        &self,
        definition: &AutomationDefinition,
    ) -> HostResult<Value> {
        let state_error = |error: anyhow::Error| HostError::state(error.to_string());
        let spec = definition.target.agent_chat();
        let last = self
            .store
            .list_automation_runs(Some(&definition.id), 1)
            .await
            .map_err(state_error)?
            .into_iter()
            .next();
        let next_run_at = if definition.state == AutomationState::Active {
            let latest = self
                .store
                .latest_automation_occurrence(&definition.id)
                .await
                .map_err(state_error)?;
            next_occurrence(
                &definition.id,
                &definition.schedule,
                automation_cursor(definition, latest),
            )
            .ok()
            .flatten()
            .map(|occurrence| occurrence.scheduled_at)
        } else {
            None
        };
        Ok(json!({
            "scheduledTaskId": definition.id,
            "title": definition.name,
            "prompt": definition.prompt_template,
            "enabled": definition.state == AutomationState::Active,
            "state": definition.state.as_str(),
            "projectId": definition.project_id,
            "workspaceId": spec.map(|spec| spec.workspace_id),
            "boundChatId": spec.and_then(|spec| spec.chat_id),
            "runtimeModeCeiling": spec.and_then(|spec| spec.runtime_mode_ceiling),
            "schedule": schedule_view(&definition.schedule),
            "nextRunAt": next_run_at,
            "lastRunStatus": last_run_status(last.as_ref().map(|run| run.status)),
            "lastRunChatId": last.as_ref().and_then(|run| run.chat_id.clone()),
        }))
    }

    /// The scheduled tasks of the bound chat's project, or for a person of
    /// the named chat's project, the named project, or every project.
    pub(super) async fn list_scheduled_tasks(
        &self,
        chat_id: Option<String>,
        project_id: Option<String>,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let chat = caller
            .bound
            .as_ref()
            .map(|bound| bound.chat_id.clone())
            .or(chat_id);
        let project = match chat {
            Some(chat_id) => {
                let snapshot = self.runtime.snapshot(&chat_id).await?;
                self.chat_project(snapshot["workspaceId"].as_str().unwrap_or_default())
                    .await?
            }
            None => project_id,
        };
        if caller.bound.is_some() && project.is_none() {
            return Ok(json!({"tasks": []}));
        }
        let definitions = self
            .store
            .list_automations(false)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let mut tasks = Vec::new();
        for definition in definitions.iter().filter(|definition| {
            definition.target.agent_chat().is_some()
                && definition.state != AutomationState::Trashed
                && (project.is_none() || definition.project_id == project)
        }) {
            if tasks.len() == LIST_LIMIT {
                break;
            }
            tasks.push(self.scheduled_task_view(definition).await?);
        }
        Ok(json!({"tasks": tasks}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn schedules_read_back_in_t3_code_shape() {
        let anchor = Utc::now();
        assert_eq!(
            schedule_view(&AutomationSchedule::Interval {
                every_seconds: 900,
                anchor,
            })["everyMs"],
            900_000
        );
        let recurring = |cron: &str| AutomationSchedule::Recurring {
            cron: cron.into(),
            timezone: "UTC".into(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        };
        assert_eq!(
            schedule_view(&recurring("5 9 * * 1,5")),
            json!({"type": "fixed_time", "timeOfDay": "09:05", "weekdays": [1, 5], "timezone": "UTC"})
        );
        assert_eq!(
            schedule_view(&recurring("0 21 * * *")),
            json!({"type": "fixed_time", "timeOfDay": "21:00", "timezone": "UTC"})
        );
        assert_eq!(schedule_view(&recurring("*/5 * * * *"))["type"], "cron");
        assert_eq!(last_run_status(None), "never");
        assert_eq!(
            last_run_status(Some(AutomationRunStatus::Dispatched)),
            "running"
        );
        assert_eq!(
            last_run_status(Some(AutomationRunStatus::Success)),
            "succeeded"
        );
        assert_eq!(
            last_run_status(Some(AutomationRunStatus::Timeout)),
            "failed"
        );
    }
}
