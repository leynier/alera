use std::collections::BTreeSet;
use std::str::FromStr;

use chrono::{DateTime, Datelike, Duration, LocalResult, NaiveDateTime, TimeZone, Timelike, Utc};
use chrono_tz::Tz;

use super::{AutomationOccurrence, AutomationSchedule};

const MAX_CRON_SCAN_MINUTES: i64 = 9 * 366 * 24 * 60;
pub const AUTOMATION_CRON_MAX_BYTES: usize = 2 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
struct CronField {
    values: BTreeSet<u32>,
    min: u32,
    max: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CronExpression {
    minute: CronField,
    hour: CronField,
    day_of_month: CronField,
    month: CronField,
    day_of_week: CronField,
    day_of_month_restricted: bool,
    day_of_week_restricted: bool,
}

impl CronField {
    fn parse(
        raw: &str,
        min: u32,
        max: u32,
        field: &str,
        names: Option<&[(&str, u32)]>,
        normalize: Option<fn(u32) -> u32>,
    ) -> Result<Self, String> {
        let mut values = BTreeSet::new();
        for part in raw.split(',') {
            let part = part.trim();
            if part.is_empty() {
                return Err(format!("invalid cron {field}"));
            }
            let pieces: Vec<&str> = part.split('/').collect();
            if pieces.len() > 2 {
                return Err(format!("invalid cron {field} step"));
            }
            let step = pieces
                .get(1)
                .map(|value| value.parse::<u32>())
                .transpose()
                .map_err(|_| format!("invalid cron {field} step"))?
                .unwrap_or(1);
            if step == 0 {
                return Err(format!("invalid cron {field} step"));
            }
            let range = pieces[0];
            let (start, end) = if range == "*" {
                (min, max)
            } else if let Some((start, end)) = range.split_once('-') {
                (
                    parse_cron_number(start, names, field)?,
                    parse_cron_number(end, names, field)?,
                )
            } else {
                let value = parse_cron_number(range, names, field)?;
                (value, value)
            };
            if start < min || end > max || start > end {
                return Err(format!("invalid cron {field} range"));
            }
            let mut value = start;
            loop {
                values.insert(normalize.map_or(value, |normalize| normalize(value)));
                if end - value < step {
                    break;
                }
                value += step;
            }
        }
        if values.is_empty() {
            return Err(format!("invalid cron {field}"));
        }
        Ok(Self { values, min, max })
    }

    fn matches(&self, value: u32) -> bool {
        value >= self.min && value <= self.max && self.values.contains(&value)
    }

    fn is_unrestricted(&self) -> bool {
        if self.min == 0 && self.max == 7 {
            (0..=6).all(|value| self.values.contains(&value))
        } else {
            self.values.len() == (self.max - self.min + 1) as usize
        }
    }
}

fn parse_cron_number(raw: &str, names: Option<&[(&str, u32)]>, field: &str) -> Result<u32, String> {
    let upper = raw.to_ascii_uppercase();
    if let Some(value) = names
        .and_then(|entries| entries.iter().find(|(name, _)| *name == upper))
        .map(|(_, value)| *value)
    {
        return Ok(value);
    }
    raw.parse()
        .map_err(|_| format!("invalid cron {field} value"))
}

fn parse_expression(expression: &str) -> Result<CronExpression, String> {
    if expression.len() > AUTOMATION_CRON_MAX_BYTES {
        return Err("cron expression is too large".to_string());
    }
    let fields: Vec<&str> = expression.split_whitespace().collect();
    if fields.len() != 5 {
        return Err("cron schedule must have five fields".to_string());
    }
    let months = [
        ("JAN", 1),
        ("FEB", 2),
        ("MAR", 3),
        ("APR", 4),
        ("MAY", 5),
        ("JUN", 6),
        ("JUL", 7),
        ("AUG", 8),
        ("SEP", 9),
        ("OCT", 10),
        ("NOV", 11),
        ("DEC", 12),
    ];
    let weekdays = [
        ("SUN", 0),
        ("MON", 1),
        ("TUE", 2),
        ("WED", 3),
        ("THU", 4),
        ("FRI", 5),
        ("SAT", 6),
    ];
    let day_of_month = CronField::parse(fields[2], 1, 31, "day of month", None, None)?;
    let day_of_week = CronField::parse(
        fields[4],
        0,
        7,
        "day of week",
        Some(&weekdays),
        Some(|value| if value == 7 { 0 } else { value }),
    )?;
    Ok(CronExpression {
        minute: CronField::parse(fields[0], 0, 59, "minute", None, None)?,
        hour: CronField::parse(fields[1], 0, 23, "hour", None, None)?,
        day_of_month_restricted: !day_of_month.is_unrestricted(),
        day_of_week_restricted: !day_of_week.is_unrestricted(),
        day_of_month,
        month: CronField::parse(fields[3], 1, 12, "month", Some(&months), None)?,
        day_of_week,
    })
}

fn cron_matches(expression: &CronExpression, local: NaiveDateTime) -> bool {
    if !expression.minute.matches(local.minute())
        || !expression.hour.matches(local.hour())
        || !expression.month.matches(local.month())
    {
        return false;
    }
    let month_day = expression.day_of_month.matches(local.day());
    let week_day = expression
        .day_of_week
        .matches(local.weekday().num_days_from_sunday());
    match (
        expression.day_of_month_restricted,
        expression.day_of_week_restricted,
    ) {
        (true, true) => month_day || week_day,
        (true, false) => month_day,
        (false, true) => week_day,
        (false, false) => true,
    }
}

fn timezone(value: &str) -> Result<Tz, String> {
    Tz::from_str(value.trim()).map_err(|_| format!("unknown IANA timezone: {value}"))
}

fn occurrence_key(timezone: &str, local: NaiveDateTime) -> String {
    format!("{timezone}|{}", local.format("%Y-%m-%dT%H:%M"))
}

/// Returns the next local schedule occurrence strictly after [after]. For an
/// ambiguous DST time only the first instant is eligible. The repeated second
/// wall-clock occurrence is intentionally not represented as a second run.
pub fn next_occurrence(
    automation_id: &str,
    schedule: &AutomationSchedule,
    after: DateTime<Utc>,
) -> Result<Option<AutomationOccurrence>, String> {
    match schedule {
        AutomationSchedule::OneTime { at, timezone: zone } => {
            timezone(zone)?;
            if *at <= after {
                return Ok(None);
            }
            Ok(Some(AutomationOccurrence {
                automation_id: automation_id.to_string(),
                key: format!("oneTime|{}", at.to_rfc3339()),
                scheduled_at: *at,
                local_time: at.to_rfc3339(),
            }))
        }
        AutomationSchedule::Recurring {
            cron,
            timezone: zone,
            start_at,
            end_at,
            ..
        } => {
            let parsed = parse_expression(cron)?;
            let tz = timezone(zone)?;
            let local_after = after.with_timezone(&tz).naive_local();
            let local_minute = local_after
                .with_second(0)
                .and_then(|value| value.with_nanosecond(0))
                .ok_or_else(|| "could not normalize local time".to_string())?;
            for offset in 0..=MAX_CRON_SCAN_MINUTES {
                let local = local_minute + Duration::minutes(offset);
                if !cron_matches(&parsed, local) {
                    continue;
                }
                let instants = match tz.from_local_datetime(&local) {
                    LocalResult::None => Vec::new(),
                    LocalResult::Single(value) => vec![value],
                    LocalResult::Ambiguous(first, second) => {
                        vec![first.min(second)]
                    }
                };
                for instant in instants {
                    let utc = instant.with_timezone(&Utc);
                    if utc <= after || start_at.is_some_and(|start| utc < start) {
                        continue;
                    }
                    if end_at.is_some_and(|end| utc > end) {
                        return Ok(None);
                    }
                    return Ok(Some(AutomationOccurrence {
                        automation_id: automation_id.to_string(),
                        key: occurrence_key(zone, local),
                        scheduled_at: utc,
                        local_time: local.format("%Y-%m-%dT%H:%M").to_string(),
                    }));
                }
            }
            Err("cron schedule has no occurrence in the scan window".to_string())
        }
    }
}

pub fn validate_schedule(schedule: &AutomationSchedule) -> Result<(), String> {
    match schedule {
        AutomationSchedule::OneTime {
            at: _,
            timezone: zone,
        } => {
            timezone(zone)?;
        }
        AutomationSchedule::Recurring {
            cron,
            timezone: zone,
            start_at,
            end_at,
            max_scheduled_runs,
        } => {
            parse_expression(cron)?;
            timezone(zone)?;
            if start_at.is_some_and(|start| end_at.is_some_and(|end| start >= end)) {
                return Err("automation schedule start must be before its end".to_string());
            }
            if max_scheduled_runs.is_some_and(|value| value < 1) {
                return Err("max scheduled runs must be positive".to_string());
            }
        }
    }
    Ok(())
}

pub fn preview_occurrences(
    automation_id: &str,
    schedule: &AutomationSchedule,
    after: DateTime<Utc>,
    count: usize,
) -> Result<Vec<AutomationOccurrence>, String> {
    validate_schedule(schedule)?;
    let mut result = Vec::with_capacity(count);
    let mut cursor = after;
    while result.len() < count {
        let Some(next) = next_occurrence(automation_id, schedule, cursor)? else {
            break;
        };
        cursor = next.scheduled_at;
        result.push(next);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use chrono::{DateTime, Utc};

    use super::{next_occurrence, preview_occurrences, validate_schedule};
    use crate::runtime::AutomationSchedule;

    fn utc(value: &str) -> DateTime<Utc> {
        value.parse().unwrap()
    }

    #[test]
    fn parses_standard_cron_and_weekday_or_semantics() {
        let schedule = AutomationSchedule::Recurring {
            cron: "15 10 * * MON-FRI".to_string(),
            timezone: "UTC".to_string(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        };
        assert!(validate_schedule(&schedule).is_ok());
        let next = next_occurrence("a", &schedule, utc("2026-08-02T12:00:00Z"))
            .unwrap()
            .unwrap();
        assert_eq!(next.local_time, "2026-08-03T10:15");
    }

    #[test]
    fn skips_nonexistent_dst_times_and_uses_first_repeated_time() {
        let schedule = AutomationSchedule::Recurring {
            cron: "30 2 * * *".to_string(),
            timezone: "America/New_York".to_string(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        };
        let next = next_occurrence("a", &schedule, utc("2026-03-07T12:00:00Z"))
            .unwrap()
            .unwrap();
        assert_eq!(next.local_time, "2026-03-09T02:30");
        assert_eq!(next.scheduled_at, utc("2026-03-09T06:30:00Z"));

        let repeated = AutomationSchedule::Recurring {
            cron: "30 1 * * *".to_string(),
            timezone: "America/New_York".to_string(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        };
        let first = next_occurrence("a", &repeated, utc("2026-11-01T00:00:00Z"))
            .unwrap()
            .unwrap();
        assert_eq!(first.scheduled_at, utc("2026-11-01T05:30:00Z"));
        let next = next_occurrence("a", &repeated, first.scheduled_at)
            .unwrap()
            .unwrap();
        assert_eq!(next.scheduled_at, utc("2026-11-02T06:30:00Z"));
        assert_ne!(first.key, next.key);
    }

    #[test]
    fn previews_are_strictly_increasing() {
        let schedule = AutomationSchedule::Recurring {
            cron: "*/30 * * * *".to_string(),
            timezone: "UTC".to_string(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        };
        let values = preview_occurrences("a", &schedule, utc("2026-08-02T12:01:00Z"), 4).unwrap();
        assert_eq!(values.len(), 4);
        assert!(values
            .windows(2)
            .all(|pair| pair[0].scheduled_at < pair[1].scheduled_at));
    }
}
