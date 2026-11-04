// Antigravity quotas from `agy -p "/usage"`, whose output is one
// tab-separated line per bucket: group, label, remaining percent and the
// reset time in UTC. Included into `agent_quota.rs`.

/// An untouched bucket's reset is the request time plus its window, give or
/// take this much, after T3 Code `1da04920a5`.
const ANTIGRAVITY_RESET_TOLERANCE_MS: i64 = 60_000;

async fn fetch_antigravity() -> QuotaSnapshot {
    let result = async {
        let mut command = windowless_async_command("agy");
        command
            .args(["-p", "/usage"])
            .stdin(Stdio::null())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        crate::login_shell_environment::apply_login_shell_environment(
            &mut command,
            &BTreeMap::new(),
        )
        .await;
        let requested_at = now_millis();
        let output = tokio::time::timeout(PTY_TIMEOUT, command.output())
            .await
            .map_err(|_| anyhow!("Antigravity usage timed out"))?
            .context("Antigravity CLI not found or could not start")?;
        if !output.status.success() {
            return Err(anyhow!(
                "Antigravity usage failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }
        Ok((String::from_utf8_lossy(&output.stdout).into_owned(), requested_at))
    }
    .await;
    match result {
        Ok((output, requested_at)) => parse_antigravity_usage(&output, requested_at),
        Err(error) => command_error_snapshot("antigravity", "default", "Antigravity", error),
    }
}

/// The window of a bucket label such as `Five Hour Limit Remaining`.
fn antigravity_window(label: &str) -> Option<(&'static str, i64)> {
    let lower = label.to_lowercase();
    if lower.contains("five hour") || lower.contains("5 hour") {
        Some(("5 Hour", SESSION_WINDOW_MINUTES))
    } else if lower.contains("weekly") {
        Some(("Weekly", WEEKLY_WINDOW_MINUTES))
    } else {
        None
    }
}

fn parse_antigravity_usage(output: &str, requested_at: i64) -> QuotaSnapshot {
    let mut buckets: Vec<QuotaBucket> = Vec::new();
    for line in strip_terminal_sequences(output).lines() {
        let fields: Vec<&str> = line.split('\t').map(str::trim).collect();
        let [group, label, percent, reset, ..] = fields.as_slice() else {
            continue;
        };
        let Some(remaining) = percent
            .strip_suffix('%')
            .and_then(|value| value.trim().parse::<f64>().ok())
            .filter(|value| (0.0..=100.0).contains(value))
        else {
            continue;
        };
        if group.is_empty() || label.is_empty() {
            continue;
        }
        let window = antigravity_window(label);
        let window_minutes = window.map(|(_, minutes)| minutes);
        let resets_at = chrono::DateTime::parse_from_rfc3339(reset)
            .ok()
            .map(|reset| reset.timestamp_millis())
            .filter(|reset| !rolling_reset(remaining, *reset, window_minutes, requested_at));
        let name = format!(
            "{} - {}",
            title_case_words(group),
            window.map_or(*label, |(name, _)| name)
        );
        buckets.retain(|bucket| bucket.name != name);
        buckets.push(QuotaBucket {
            name,
            used_percent: 100.0 - remaining,
            window_minutes,
            resets_at,
            reset_description: None,
        });
    }
    if buckets.is_empty() {
        return QuotaSnapshot::error(
            "antigravity",
            "default",
            "Antigravity",
            "Usage output did not include recognizable quota percentages",
        );
    }
    QuotaSnapshot::ok("antigravity", "default", "Antigravity", Vec::new(), buckets)
}

/// Whether a reset is the rolling one an untouched bucket reports: full
/// remaining, and exactly one window after the request.
fn rolling_reset(remaining: f64, reset: i64, window_minutes: Option<i64>, requested_at: i64) -> bool {
    let Some(window_minutes) = window_minutes else {
        return false;
    };
    remaining >= 100.0
        && (reset - requested_at - window_minutes * 60_000).abs() <= ANTIGRAVITY_RESET_TOLERANCE_MS
}

#[cfg(test)]
#[path = "antigravity_tests.rs"]
mod antigravity_tests;
