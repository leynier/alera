//! Parses the scheduled task verbs (`chatOrchestrationSchedulesV1`), ported
//! from T3 Code's `schedule_task` family, and turns their `interval` and
//! `fixed_time` schedules into automation schedules.

use alera_core::runtime::{fixed_time_cron, AutomationSchedule, AUTOMATION_MIN_INTERVAL_SECONDS};
use chrono::{DateTime, Utc};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

/// The longest prompt a scheduled task stores.
pub(crate) const MAX_SCHEDULE_PROMPT_BYTES: usize = 64 * 1024;
const MAX_TITLE_CHARS: usize = 120;

/// `schedule` as T3 Code writes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ScheduleSpec {
    Interval {
        every_seconds: i64,
    },
    FixedTime {
        time_of_day: String,
        weekdays: Vec<u32>,
        timezone: Option<String>,
    },
}

/// `scheduleTask`: create, or update the task named by `scheduled_task_id`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct ScheduleTaskInput {
    pub scheduled_task_id: Option<String>,
    pub prompt: Option<String>,
    pub title: Option<String>,
    pub schedule: Option<ScheduleSpec>,
    pub enabled: Option<bool>,
    /// Default true: runs post in the calling chat. False: a new chat per run.
    pub bind_to_current_chat: Option<bool>,
    /// The chat a person schedules for; agents always use their own chat.
    pub chat_id: Option<String>,
    pub request_id: Option<String>,
}

fn text(payload: &Value, key: &str) -> HostResult<Option<String>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) => {
            Ok((!value.trim().is_empty()).then(|| value.trim().to_owned()))
        }
        Some(_) => Err(HostError::format(format!("{key} must be a string"))),
    }
}

fn flag(payload: &Value, key: &str) -> HostResult<Option<bool>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Bool(value)) => Ok(Some(*value)),
        Some(_) => Err(HostError::format(format!("{key} must be a boolean"))),
    }
}

pub(crate) fn scheduled_task_id(payload: &Value) -> HostResult<String> {
    text(payload, "scheduledTaskId")?
        .ok_or_else(|| HostError::format("scheduledTaskId is required"))
}

pub(crate) fn parse_schedule_task(payload: &Value) -> HostResult<ScheduleTaskInput> {
    let input = ScheduleTaskInput {
        scheduled_task_id: text(payload, "scheduledTaskId")?,
        prompt: text(payload, "prompt")?,
        title: text(payload, "title")?,
        schedule: match payload.get("schedule") {
            None | Some(Value::Null) => None,
            Some(value) => Some(parse_schedule(value)?),
        },
        enabled: flag(payload, "enabled")?,
        bind_to_current_chat: flag(payload, "bindToCurrentChat")?,
        chat_id: text(payload, "chatId")?,
        request_id: text(payload, "requestId")?,
    };
    if input
        .prompt
        .as_ref()
        .is_some_and(|prompt| prompt.len() > MAX_SCHEDULE_PROMPT_BYTES)
    {
        return Err(HostError::format("prompt is longer than 64 KiB"));
    }
    if input
        .title
        .as_ref()
        .is_some_and(|title| title.chars().count() > MAX_TITLE_CHARS)
    {
        return Err(HostError::format("title is longer than 120 characters"));
    }
    if input.scheduled_task_id.is_none() && (input.prompt.is_none() || input.schedule.is_none()) {
        return Err(HostError::format(
            "a new scheduled task needs prompt and schedule",
        ));
    }
    Ok(input)
}

/// `{type: interval, everyMs | everySeconds}` or `{type: fixed_time,
/// timeOfDay, weekdays?, timezone?}`; a JSON string holding one is read too.
pub(crate) fn parse_schedule(value: &Value) -> HostResult<ScheduleSpec> {
    if let Some(raw) = value.as_str() {
        let parsed: Value = serde_json::from_str(raw)
            .map_err(|_| HostError::format("schedule must be an object"))?;
        return parse_schedule(&parsed);
    }
    if !value.is_object() {
        return Err(HostError::format("schedule must be an object"));
    }
    match value["type"].as_str() {
        Some("interval") => {
            let every_seconds = match (value["everyMs"].as_i64(), value["everySeconds"].as_i64()) {
                (Some(ms), _) => ms / 1000,
                (None, Some(seconds)) => seconds,
                (None, None) => {
                    return Err(HostError::format(
                        "an interval schedule needs everyMs",
                    ))
                }
            };
            if every_seconds < AUTOMATION_MIN_INTERVAL_SECONDS {
                return Err(HostError::format(
                    "an interval schedule repeats at least every 60000 ms",
                ));
            }
            Ok(ScheduleSpec::Interval { every_seconds })
        }
        Some("fixed_time") => {
            let time_of_day = text(value, "timeOfDay")?
                .ok_or_else(|| HostError::format("a fixed_time schedule needs timeOfDay"))?;
            let weekdays = match value.get("weekdays") {
                None | Some(Value::Null) => Vec::new(),
                Some(Value::Array(days)) => days
                    .iter()
                    .map(|day| {
                        day.as_u64()
                            .filter(|day| *day <= 6)
                            .map(|day| day as u32)
                            .ok_or_else(|| HostError::format("weekdays are 0 (Sunday) to 6"))
                    })
                    .collect::<HostResult<_>>()?,
                Some(_) => return Err(HostError::format("weekdays must be a list")),
            };
            fixed_time_cron(&time_of_day, &weekdays).map_err(HostError::format)?;
            Ok(ScheduleSpec::FixedTime {
                time_of_day,
                weekdays,
                timezone: text(value, "timezone")?,
            })
        }
        Some("webhook") => Err(HostError::format(
            "Alera has no inbound webhook path, so a webhook schedule is not available; use interval or fixed_time",
        )),
        _ => Err(HostError::format(
            "schedule.type must be interval or fixed_time",
        )),
    }
}

/// The automation schedule for `spec`, anchored at `now`.
pub(crate) fn automation_schedule(
    spec: &ScheduleSpec,
    now: DateTime<Utc>,
) -> HostResult<AutomationSchedule> {
    match spec {
        ScheduleSpec::Interval { every_seconds } => Ok(AutomationSchedule::Interval {
            every_seconds: *every_seconds,
            anchor: now,
        }),
        ScheduleSpec::FixedTime {
            time_of_day,
            weekdays,
            timezone,
        } => Ok(AutomationSchedule::Recurring {
            cron: fixed_time_cron(time_of_day, weekdays).map_err(HostError::format)?,
            timezone: timezone.clone().unwrap_or_else(local_timezone),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        }),
    }
}

/// Whether `name` is an IANA time zone the scheduler accepts.
pub(crate) fn is_timezone(name: &str) -> bool {
    alera_core::runtime::validate_schedule(&AutomationSchedule::Recurring {
        cron: "0 0 * * *".into(),
        timezone: name.into(),
        start_at: None,
        end_at: None,
        max_scheduled_runs: None,
    })
    .is_ok()
}

/// This computer's IANA time zone: `TZ`, then the `/etc/localtime` link,
/// then UTC.
pub(crate) fn local_timezone() -> String {
    let valid = |name: &str| is_timezone(name);
    if let Ok(zone) = std::env::var("TZ") {
        let zone = zone.trim_start_matches(':').trim();
        if valid(zone) {
            return zone.to_owned();
        }
    }
    if let Ok(target) = std::fs::read_link("/etc/localtime") {
        let target = target.to_string_lossy().into_owned();
        if let Some((_, zone)) = target.split_once("zoneinfo/") {
            if valid(zone) {
                return zone.to_owned();
            }
        }
    }
    "UTC".into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn schedules_parse_like_t3_code() {
        assert_eq!(
            parse_schedule(&json!({"type": "interval", "everyMs": 900_000})).unwrap(),
            ScheduleSpec::Interval { every_seconds: 900 }
        );
        assert_eq!(
            parse_schedule(&json!("{\"type\":\"interval\",\"everySeconds\":60}")).unwrap(),
            ScheduleSpec::Interval { every_seconds: 60 }
        );
        assert!(parse_schedule(&json!({"type": "interval", "everyMs": 59_999})).is_err());
        assert_eq!(
            parse_schedule(
                &json!({"type": "fixed_time", "timeOfDay": "21:00", "weekdays": [1, 5]})
            )
            .unwrap(),
            ScheduleSpec::FixedTime {
                time_of_day: "21:00".into(),
                weekdays: vec![1, 5],
                timezone: None,
            }
        );
        assert!(parse_schedule(&json!({"type": "fixed_time", "timeOfDay": "25:00"})).is_err());
        assert!(parse_schedule(
            &json!({"type": "fixed_time", "timeOfDay": "9:00", "weekdays": [7]})
        )
        .is_err());
        let webhook = parse_schedule(&json!({"type": "webhook"})).unwrap_err();
        assert!(webhook.wire_message().contains("no inbound webhook"));
    }

    #[test]
    fn a_new_task_needs_a_prompt_and_a_schedule() {
        assert!(parse_schedule_task(&json!({"prompt": "Check"})).is_err());
        assert!(parse_schedule_task(&json!({"scheduledTaskId": "a", "enabled": false})).is_ok());
        let input = parse_schedule_task(&json!({
            "prompt": "Check", "schedule": {"type": "interval", "everyMs": 60_000},
            "bindToCurrentChat": false, "title": "Nightly"
        }))
        .unwrap();
        assert_eq!(input.bind_to_current_chat, Some(false));
        assert_eq!(input.title.as_deref(), Some("Nightly"));
    }

    #[test]
    fn fixed_time_becomes_a_recurring_cron_in_the_given_zone() {
        let now = Utc::now();
        let schedule = automation_schedule(
            &ScheduleSpec::FixedTime {
                time_of_day: "07:30".into(),
                weekdays: vec![0, 6],
                timezone: Some("Europe/Madrid".into()),
            },
            now,
        )
        .unwrap();
        assert_eq!(
            schedule,
            AutomationSchedule::Recurring {
                cron: "30 7 * * 0,6".into(),
                timezone: "Europe/Madrid".into(),
                start_at: None,
                end_at: None,
                max_scheduled_runs: None,
            }
        );
        assert_eq!(
            automation_schedule(&ScheduleSpec::Interval { every_seconds: 120 }, now).unwrap(),
            AutomationSchedule::Interval {
                every_seconds: 120,
                anchor: now,
            }
        );
        assert!(is_timezone(&local_timezone()));
        assert!(!is_timezone("Mars/Olympus"));
    }
}
