async fn fetch_tui_provider(
    provider: &str,
    display_name: &str,
    command: &str,
    slash_command: &str,
) -> QuotaSnapshot {
    let completion = if provider == "antigravity" {
        TuiCompletion::Antigravity
    } else {
        TuiCompletion::Generic
    };
    match run_tui_command(
        command,
        &[],
        slash_command,
        BTreeMap::new(),
        completion,
    )
    .await
    {
        Ok(output) => parse_tui_snapshot(provider, "default", display_name, &output),
        Err(error) => command_error_snapshot(provider, "default", display_name, error),
    }
}

fn command_error_snapshot(
    provider: &str,
    account_id: &str,
    display_name: &str,
    error: anyhow::Error,
) -> QuotaSnapshot {
    let message = redact_error(&error.to_string());
    if message.to_lowercase().contains("not found") {
        QuotaSnapshot::unavailable(provider, account_id, display_name, message)
    } else {
        QuotaSnapshot::error(provider, account_id, display_name, message)
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum TuiCompletion {
    Generic,
    Antigravity,
}

async fn run_tui_command(
    command: &str,
    arguments: &[&str],
    slash_command: &str,
    environment: BTreeMap<String, String>,
    completion: TuiCompletion,
) -> Result<String> {
    let command = command.to_string();
    let arguments = arguments
        .iter()
        .map(|argument| (*argument).to_string())
        .collect::<Vec<_>>();
    let slash_command = slash_command.to_string();
    tokio::task::spawn_blocking(move || -> Result<String> {
        let pty_system = native_pty_system();
        let pair = pty_system.openpty(PtySize {
            rows: 46,
            cols: 150,
            pixel_width: 0,
            pixel_height: 0,
        })?;
        let mut builder = CommandBuilder::new(&command);
        for argument in arguments {
            builder.arg(argument);
        }
        for (key, value) in environment {
            builder.env(key, value);
        }
        builder.env("TERM", "xterm-256color");
        let mut child = pair
            .slave
            .spawn_command(builder)
            .with_context(|| format!("{command} CLI not found or could not start"))?;
        drop(pair.slave);
        let mut killer = child.clone_killer();
        let mut reader = pair.master.try_clone_reader()?;
        let mut writer = pair.master.take_writer()?;
        let (tx, rx) = mpsc::channel::<Vec<u8>>();
        std::thread::spawn(move || {
            let mut buffer = [0_u8; 8192];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) | Err(_) => break,
                    Ok(count) => {
                        if tx.send(buffer[..count].to_vec()).is_err() {
                            break;
                        }
                    }
                }
            }
        });

        let startup_started = Instant::now();
        let mut startup_output = Vec::new();
        while startup_started.elapsed() < Duration::from_secs(8) {
            match rx.recv_timeout(Duration::from_millis(250)) {
                Ok(chunk) => {
                    startup_output.extend_from_slice(&chunk);
                    let clean = strip_terminal_sequences(&String::from_utf8_lossy(&startup_output));
                    if clean.contains("? for shortcuts")
                        || clean.contains("Type a request")
                        || clean.contains("What can I help you")
                    {
                        break;
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
        }
        writer.write_all(format!("{slash_command}\r").as_bytes())?;
        writer.flush()?;
        let started = Instant::now();
        let mut output = Vec::new();
        let mut last_data = Instant::now();
        while started.elapsed() < PTY_TIMEOUT {
            match rx.recv_timeout(Duration::from_millis(250)) {
                Ok(chunk) => {
                    output.extend_from_slice(&chunk);
                    if output.len() > 200_000 {
                        output.drain(..output.len() - 200_000);
                    }
                    last_data = Instant::now();
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    let settled = match completion {
                        TuiCompletion::Antigravity => {
                            last_data.elapsed() > Duration::from_millis(300)
                                && antigravity_usage_complete(&String::from_utf8_lossy(&output))
                        }
                        TuiCompletion::Generic => {
                            started.elapsed() > Duration::from_secs(4)
                                && output.len() > 100
                                && String::from_utf8_lossy(&output).contains('%')
                                && last_data.elapsed() > Duration::from_millis(900)
                        }
                    };
                    if settled {
                        break;
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
        let _ = killer.kill();
        let _ = child.wait();
        Ok(String::from_utf8_lossy(&output).to_string())
    })
    .await
    .context("Quota PTY task failed")?
}

fn antigravity_usage_complete(output: &str) -> bool {
    const EXPECTED_BUCKETS: [&str; 4] = [
        "Gemini Models - Weekly",
        "Gemini Models - 5 Hour",
        "Claude And GPT Models - Weekly",
        "Claude And GPT Models - 5 Hour",
    ];
    let snapshot = parse_tui_snapshot("antigravity", "default", "Antigravity", output);
    snapshot.status == "ok"
        && EXPECTED_BUCKETS.iter().all(|expected| {
            snapshot
                .buckets
                .iter()
                .any(|bucket| bucket.name == *expected)
        })
}

fn parse_tui_snapshot(
    provider: &str,
    account_id: &str,
    display_name: &str,
    output: &str,
) -> QuotaSnapshot {
    let clean = strip_terminal_sequences(output);
    let percent_re = Regex::new(r"(?i)(\d{1,3}(?:\.\d+)?)\s*%\s*(used|left|remaining)?").unwrap();
    let mut windows = Vec::new();
    let mut buckets = Vec::new();
    let mut current_label: Option<String> = None;
    let mut current_group: Option<String> = None;
    for raw_line in clean.lines() {
        let line = raw_line.split_whitespace().collect::<Vec<_>>().join(" ");
        if line.len() < 3 {
            continue;
        }
        let lower = line.to_lowercase();
        if lower.contains("five hour limit") || lower.contains("5 hour limit") {
            current_label = Some("5 Hour".to_string());
        } else if lower.contains("weekly limit") {
            current_label = Some("Weekly".to_string());
        }
        if provider == "antigravity" && lower.ends_with("models") {
            current_group = Some(title_case_words(&line));
            continue;
        }
        let Some(captures) = percent_re.captures(&line) else {
            continue;
        };
        let raw_percent = captures
            .get(1)
            .and_then(|value| value.as_str().parse::<f64>().ok())
            .unwrap_or(0.0);
        let suffix = captures
            .get(2)
            .map(|value| value.as_str().to_lowercase())
            .unwrap_or_default();
        let used_percent = if suffix == "used" {
            raw_percent
        } else if suffix == "left" || suffix == "remaining" || provider == "antigravity" {
            100.0 - raw_percent
        } else {
            raw_percent
        }
        .clamp(0.0, 100.0);
        let window_minutes = if current_label.as_deref() == Some("5 Hour")
            || lower.contains("5h")
            || lower.contains("5 hour")
            || lower.contains("session")
        {
            Some(SESSION_WINDOW_MINUTES)
        } else if current_label.as_deref() == Some("Weekly")
            || lower.contains("week")
            || lower.contains("7 day")
        {
            Some(WEEKLY_WINDOW_MINUTES)
        } else {
            None
        };
        let reset_description = extract_reset_description(&line);
        if provider == "antigravity" {
            let label = current_label.clone().unwrap_or_else(|| "Quota".to_string());
            let name = current_group
                .as_ref()
                .map(|group| format!("{group} - {label}"))
                .unwrap_or(label);
            buckets.retain(|bucket: &QuotaBucket| bucket.name != name);
            buckets.push(QuotaBucket {
                name,
                used_percent,
                window_minutes,
                resets_at: None,
                reset_description,
            });
        } else if window_minutes.is_none() {
            buckets.push(QuotaBucket {
                name: line
                    .replace(captures.get(0).unwrap().as_str(), "")
                    .trim_matches(|value: char| {
                        value == '-' || value == ':' || value.is_whitespace()
                    })
                    .to_string(),
                used_percent,
                window_minutes,
                resets_at: None,
                reset_description,
            });
        } else {
            windows.push(QuotaWindow {
                label: if window_minutes == Some(SESSION_WINDOW_MINUTES) {
                    "5 Hour".to_string()
                } else {
                    "Weekly".to_string()
                },
                used_percent,
                window_minutes,
                resets_at: None,
                reset_description,
            });
        }
    }
    deduplicate_windows(&mut windows);
    if windows.is_empty() && buckets.is_empty() {
        return QuotaSnapshot::error(
            provider,
            account_id,
            display_name,
            "Usage output did not include recognizable quota percentages",
        );
    }
    QuotaSnapshot::ok(provider, account_id, display_name, windows, buckets)
}

fn deduplicate_windows(windows: &mut Vec<QuotaWindow>) {
    let mut unique = BTreeMap::<Option<i64>, QuotaWindow>::new();
    for window in windows.drain(..) {
        unique.insert(window.window_minutes, window);
    }
    windows.extend(unique.into_values());
}

fn extract_reset_description(line: &str) -> Option<String> {
    let lower = line.to_lowercase();
    let index = lower.find("reset").or_else(|| lower.find("refresh"))?;
    Some(line[index..].trim().to_string())
}

fn title_case_words(value: &str) -> String {
    value
        .split_whitespace()
        .map(|part| {
            let lower = part.to_lowercase();
            if lower == "gpt" {
                return "GPT".to_string();
            }
            let mut chars = lower.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}
