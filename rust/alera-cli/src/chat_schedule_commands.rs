//! `alera chat schedule save|list|delete|run`: scheduled tasks that post
//! into an agent chat (`chatOrchestrationSchedulesV1`), ported from T3 Code.
//! Alera has no inbound path, so there are no webhook schedules.

use anyhow::{bail, Result};
use clap::{Args, Subcommand};
use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;

pub(crate) const SCHEDULES_CAPABILITY: &str = "chatOrchestrationSchedulesV1";

#[derive(Debug, Args)]
pub struct ChatScheduleArgs {
    #[command(subcommand)]
    pub action: ChatScheduleAction,
}

#[derive(Debug, Subcommand)]
pub enum ChatScheduleAction {
    /// Create a scheduled task, or update one with --id.
    Save(ChatScheduleSave),
    /// List scheduled tasks of the chat's project.
    List(ChatScheduleList),
    /// Move a scheduled task to the automation trash.
    Delete(ChatScheduleTask),
    /// Start one run now; answers its chat.
    Run(ChatScheduleTask),
}

#[derive(Debug, Args)]
pub struct ChatScheduleSave {
    /// The task to update; a new task when omitted.
    #[arg(long = "id")]
    pub id: Option<String>,
    #[arg(long)]
    pub prompt: Option<String>,
    #[arg(long)]
    pub title: Option<String>,
    /// The schedule as JSON: {"type":"interval","everyMs":N} or
    /// {"type":"fixed_time","timeOfDay":"HH:MM","weekdays":[0-6],"timezone":"Area/City"}.
    #[arg(long, conflicts_with_all = ["every_ms", "time_of_day"])]
    pub schedule: Option<String>,
    /// Repeat every N milliseconds (at least 60000).
    #[arg(long = "every-ms", conflicts_with = "time_of_day")]
    pub every_ms: Option<u64>,
    /// Run at HH:MM local time.
    #[arg(long = "time-of-day")]
    pub time_of_day: Option<String>,
    /// Comma-separated weekdays for --time-of-day, 0 (Sunday) to 6.
    #[arg(long, value_delimiter = ',', requires = "time_of_day")]
    pub weekdays: Vec<u32>,
    /// IANA time zone for --time-of-day; this computer's when omitted.
    #[arg(long, requires = "time_of_day")]
    pub timezone: Option<String>,
    /// true or false; false pauses the task.
    #[arg(long)]
    pub enabled: Option<bool>,
    /// true (default) posts runs into the chat; false opens a new chat per run.
    #[arg(long = "bind-to-current-chat")]
    pub bind_to_current_chat: Option<bool>,
    /// The chat runs post into, for a person; agents use their own chat.
    #[arg(long = "chat-id")]
    pub chat_id: Option<String>,
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct ChatScheduleList {
    #[arg(long = "chat-id")]
    pub chat_id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct ChatScheduleTask {
    #[arg(long = "id")]
    pub id: String,
    /// The task's chat, for a person reaching a task on another host.
    #[arg(long = "chat-id")]
    pub chat_id: Option<String>,
}

fn trimmed(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

pub(crate) fn save_payload(args: ChatScheduleSave) -> Result<Value> {
    let schedule = match (args.schedule, args.every_ms, args.time_of_day) {
        (Some(raw), _, _) => Some(
            serde_json::from_str::<Value>(&raw)
                .map_err(|error| anyhow::anyhow!("--schedule must be a JSON object: {error}"))?,
        ),
        (None, Some(every_ms), _) => Some(json!({"type": "interval", "everyMs": every_ms})),
        (None, None, Some(time_of_day)) => {
            let mut schedule = json!({"type": "fixed_time", "timeOfDay": time_of_day});
            if !args.weekdays.is_empty() {
                schedule["weekdays"] = json!(args.weekdays);
            }
            if let Some(timezone) = trimmed(args.timezone) {
                schedule["timezone"] = json!(timezone);
            }
            Some(schedule)
        }
        (None, None, None) => None,
    };
    if args.id.is_none() && (args.prompt.is_none() || schedule.is_none()) {
        bail!("a new scheduled task needs --prompt and a schedule");
    }
    let mut payload = json!({});
    let fields = [
        ("scheduledTaskId", trimmed(args.id).map(Value::from)),
        ("prompt", args.prompt.map(Value::from)),
        ("title", trimmed(args.title).map(Value::from)),
        ("schedule", schedule),
        ("enabled", args.enabled.map(Value::from)),
        (
            "bindToCurrentChat",
            args.bind_to_current_chat.map(Value::from),
        ),
        ("chatId", trimmed(args.chat_id).map(Value::from)),
        ("requestId", trimmed(args.request_id).map(Value::from)),
    ];
    for (key, value) in fields {
        if let Some(value) = value {
            payload[key] = value;
        }
    }
    Ok(payload)
}

fn task_payload(task: ChatScheduleTask) -> Value {
    let mut payload = json!({"scheduledTaskId": task.id.trim()});
    if let Some(chat_id) = trimmed(task.chat_id) {
        payload["chatId"] = json!(chat_id);
    }
    payload
}

pub(crate) async fn run(runtime: &RuntimeDirArgs, args: ChatScheduleArgs) -> Result<Value> {
    let (verb, payload) = match args.action {
        ChatScheduleAction::Save(save) => ("scheduleTask", save_payload(save)?),
        ChatScheduleAction::List(list) => (
            "listScheduledTasks",
            json!({"chatId": trimmed(list.chat_id), "projectId": trimmed(list.project_id)}),
        ),
        ChatScheduleAction::Delete(task) => ("deleteScheduledTask", task_payload(task)),
        ChatScheduleAction::Run(task) => ("runScheduledTaskNow", task_payload(task)),
    };
    crate::chat_orchestration_request::request(
        runtime,
        &format!("chatOrchestration.{verb}"),
        payload,
        None,
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn save() -> ChatScheduleSave {
        ChatScheduleSave {
            id: None,
            prompt: Some("Check the deploy".into()),
            title: None,
            schedule: None,
            every_ms: None,
            time_of_day: None,
            weekdays: Vec::new(),
            timezone: None,
            enabled: None,
            bind_to_current_chat: None,
            chat_id: None,
            request_id: None,
        }
    }

    #[test]
    fn flags_become_t3_code_schedules() {
        let mut interval = save();
        interval.every_ms = Some(900_000);
        assert_eq!(
            save_payload(interval).unwrap(),
            json!({"prompt": "Check the deploy", "schedule": {"type": "interval", "everyMs": 900_000}})
        );
        let mut fixed = save();
        fixed.time_of_day = Some("21:00".into());
        fixed.weekdays = vec![1, 5];
        fixed.bind_to_current_chat = Some(false);
        let payload = save_payload(fixed).unwrap();
        assert_eq!(
            payload["schedule"],
            json!({"type": "fixed_time", "timeOfDay": "21:00", "weekdays": [1, 5]})
        );
        assert_eq!(payload["bindToCurrentChat"], false);
        assert!(save_payload(save()).is_err());
        let update = ChatScheduleSave {
            id: Some("task".into()),
            prompt: None,
            enabled: Some(false),
            ..save()
        };
        assert_eq!(
            save_payload(update).unwrap(),
            json!({"scheduledTaskId": "task", "enabled": false})
        );
    }
}
