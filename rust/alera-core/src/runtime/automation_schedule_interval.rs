//! Interval schedules and T3 Code's `fixed_time` schedules, which become a
//! recurring cron schedule.

use chrono::{DateTime, Duration, Utc};

use super::AutomationOccurrence;

/// The shortest interval a schedule may repeat at.
pub const AUTOMATION_MIN_INTERVAL_SECONDS: i64 = 60;
/// The longest interval: one year.
const MAX_INTERVAL_SECONDS: i64 = 366 * 24 * 60 * 60;

pub(super) fn validate_interval(every_seconds: i64) -> Result<(), String> {
    if every_seconds < AUTOMATION_MIN_INTERVAL_SECONDS {
        return Err(format!(
            "interval schedule must repeat at least {AUTOMATION_MIN_INTERVAL_SECONDS} seconds apart"
        ));
    }
    if every_seconds > MAX_INTERVAL_SECONDS {
        return Err("interval schedule must repeat at most once a year".to_string());
    }
    Ok(())
}

/// The first `anchor + k * every` (k >= 1) strictly after `after`.
pub(super) fn next_interval(
    automation_id: &str,
    every_seconds: i64,
    anchor: DateTime<Utc>,
    after: DateTime<Utc>,
) -> Result<AutomationOccurrence, String> {
    validate_interval(every_seconds)?;
    let elapsed = after.signed_duration_since(anchor).num_seconds();
    let steps = if elapsed < every_seconds {
        1
    } else {
        elapsed / every_seconds + 1
    };
    let mut scheduled_at = anchor + Duration::seconds(steps * every_seconds);
    // Sub-second parts of `after` can leave the candidate equal to it.
    while scheduled_at <= after {
        scheduled_at += Duration::seconds(every_seconds);
    }
    Ok(AutomationOccurrence {
        automation_id: automation_id.to_string(),
        key: format!("interval|{}", scheduled_at.to_rfc3339()),
        scheduled_at,
        local_time: scheduled_at.format("%Y-%m-%dT%H:%M:%S").to_string(),
    })
}

/// The cron expression for a `fixed_time` schedule: `HH:MM` local time on
/// the given weekdays (0 is Sunday), every day when none are given.
pub fn fixed_time_cron(time_of_day: &str, weekdays: &[u32]) -> Result<String, String> {
    let invalid = || format!("timeOfDay must be HH:MM, got {time_of_day:?}");
    let (hour, minute) = time_of_day.trim().split_once(':').ok_or_else(invalid)?;
    if hour.is_empty() || hour.len() > 2 || minute.len() != 2 {
        return Err(invalid());
    }
    let hour: u32 = hour.parse().map_err(|_| invalid())?;
    let minute: u32 = minute.parse().map_err(|_| invalid())?;
    if hour > 23 || minute > 59 {
        return Err(invalid());
    }
    if let Some(day) = weekdays.iter().find(|day| **day > 6) {
        return Err(format!(
            "weekdays run from 0 (Sunday) to 6 (Saturday), got {day}"
        ));
    }
    let mut days: Vec<u32> = weekdays.to_vec();
    days.sort_unstable();
    days.dedup();
    let day_field = if days.is_empty() || days.len() == 7 {
        "*".to_string()
    } else {
        days.iter()
            .map(u32::to_string)
            .collect::<Vec<_>>()
            .join(",")
    };
    Ok(format!("{minute} {hour} * * {day_field}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::{next_occurrence, validate_schedule, AutomationSchedule};

    fn utc(value: &str) -> DateTime<Utc> {
        value.parse().unwrap()
    }

    fn interval(every_seconds: i64) -> AutomationSchedule {
        AutomationSchedule::Interval {
            every_seconds,
            anchor: utc("2026-11-03T10:00:00Z"),
        }
    }

    #[test]
    fn interval_runs_one_interval_after_the_anchor_and_then_on_its_grid() {
        let schedule = interval(15 * 60);
        let first = next_occurrence("a", &schedule, utc("2026-11-03T10:00:00Z"))
            .unwrap()
            .unwrap();
        assert_eq!(first.scheduled_at, utc("2026-11-03T10:15:00Z"));
        let before_anchor = next_occurrence("a", &schedule, utc("2026-11-03T09:00:00Z"))
            .unwrap()
            .unwrap();
        assert_eq!(before_anchor.scheduled_at, utc("2026-11-03T10:15:00Z"));
        let later = next_occurrence("a", &schedule, utc("2026-11-03T11:07:30Z"))
            .unwrap()
            .unwrap();
        assert_eq!(later.scheduled_at, utc("2026-11-03T11:15:00Z"));
        let on_grid = next_occurrence("a", &schedule, later.scheduled_at)
            .unwrap()
            .unwrap();
        assert_eq!(on_grid.scheduled_at, utc("2026-11-03T11:30:00Z"));
        assert_ne!(later.key, on_grid.key);
        assert_eq!(schedule.timezone(), "UTC");
        assert_eq!(schedule.max_scheduled_runs(), None);
    }

    #[test]
    fn interval_schedules_repeat_at_least_a_minute_apart() {
        assert!(validate_schedule(&interval(59)).is_err());
        assert!(validate_schedule(&interval(60)).is_ok());
        assert!(validate_schedule(&interval(400 * 24 * 60 * 60)).is_err());
        assert!(next_occurrence("a", &interval(10), utc("2026-11-03T10:00:00Z")).is_err());
    }

    #[test]
    fn interval_schedule_round_trips_in_camel_case() {
        let schedule: AutomationSchedule = serde_json::from_value(serde_json::json!({
            "interval": {"everySeconds": 900, "anchor": "2026-11-03T10:00:00Z"}
        }))
        .unwrap();
        assert_eq!(schedule, interval(900));
        assert_eq!(
            serde_json::to_value(&schedule).unwrap()["interval"]["everySeconds"],
            900
        );
    }

    #[test]
    fn fixed_time_becomes_a_daily_or_weekday_cron() {
        assert_eq!(fixed_time_cron("21:00", &[]).unwrap(), "0 21 * * *");
        assert_eq!(fixed_time_cron("9:05", &[5, 1, 1]).unwrap(), "5 9 * * 1,5");
        assert_eq!(
            fixed_time_cron("07:30", &[0, 1, 2, 3, 4, 5, 6]).unwrap(),
            "30 7 * * *"
        );
        for bad in ["24:00", "12:60", "noon", "1:5", "", "123:00"] {
            assert!(fixed_time_cron(bad, &[]).is_err(), "{bad}");
        }
        assert!(fixed_time_cron("10:00", &[7]).is_err());
    }

    #[test]
    fn fixed_time_cron_next_runs_follow_the_weekdays_in_the_timezone() {
        let schedule = AutomationSchedule::Recurring {
            cron: fixed_time_cron("23:00", &[0]).unwrap(),
            timezone: "America/Los_Angeles".into(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        };
        // Saturday 2026-10-24 10:00 PDT.
        let next = next_occurrence("a", &schedule, utc("2026-10-24T17:00:00Z"))
            .unwrap()
            .unwrap();
        assert_eq!(next.local_time, "2026-10-25T23:00");
        assert_eq!(next.scheduled_at, utc("2026-10-26T06:00:00Z"));
        let weekdays = AutomationSchedule::Recurring {
            cron: fixed_time_cron("09:30", &[1, 3]).unwrap(),
            timezone: "UTC".into(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        };
        // Tuesday 2026-11-03 12:00 UTC: Wednesday is next.
        let next = next_occurrence("a", &weekdays, utc("2026-11-03T12:00:00Z"))
            .unwrap()
            .unwrap();
        assert_eq!(next.scheduled_at, utc("2026-11-04T09:30:00Z"));
    }
}
