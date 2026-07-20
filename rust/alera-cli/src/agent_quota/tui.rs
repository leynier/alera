async fn fetch_claude(
    profile: Option<&ClaudeProfileRequest>,
    cli_permits: Arc<Semaphore>,
    allow_cli_fallback: bool,
) -> QuotaSnapshot {
    let (account_id, display_name, config_dir, env) = match profile {
        None => {
            let config_dir = home_dir().map(|home| home.join(".claude"));
            (
                "default".to_string(),
                "Default".to_string(),
                config_dir,
                BTreeMap::new(),
            )
        }
        Some(profile) => {
            let Some(home) = home_dir() else {
                return QuotaSnapshot::unavailable(
                    "claude",
                    &profile.profile,
                    &profile.alias,
                    "Home directory is unavailable",
                );
            };
            let ccs_root = std::env::var("CCS_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|_| home.join(".ccs"));
            let config_dir = ccs_root.join("instances").join(&profile.profile);
            if !config_dir.exists() {
                return QuotaSnapshot::unavailable(
                    "claude",
                    &profile.profile,
                    &profile.alias,
                    format!("CCS profile not found: {}", profile.profile),
                );
            }
            (
                profile.profile.clone(),
                profile.alias.clone(),
                Some(config_dir.clone()),
                BTreeMap::from([(
                    "CLAUDE_CONFIG_DIR".to_string(),
                    config_dir.to_string_lossy().to_string(),
                )]),
            )
        }
    };
    let api_environment_present = anthropic_api_environment_present();
    let oauth = match config_dir.as_deref() {
        Some(config_dir) => fetch_claude_oauth(&account_id, &display_name, config_dir)
            .await
            .unwrap_or(ClaudeOAuthFetch::FallbackRequired),
        None => ClaudeOAuthFetch::CredentialsMissing,
    };
    match oauth {
        ClaudeOAuthFetch::Snapshot(snapshot) => return snapshot,
        ClaudeOAuthFetch::CredentialsMissing if !api_environment_present => {
            return QuotaSnapshot::unavailable(
                "claude",
                &account_id,
                &display_name,
                "Not signed in to Claude",
            )
        }
        ClaudeOAuthFetch::CredentialsMissing | ClaudeOAuthFetch::FallbackRequired => {}
    }
    if !allow_cli_fallback {
        return QuotaSnapshot::unavailable(
            "claude",
            &account_id,
            &display_name,
            "Claude OAuth usage is unavailable",
        );
    }
    let _permit = cli_permits.acquire_owned().await.ok();
    if !api_environment_present && claude_auth_status(&env).await == Some(false) {
        return QuotaSnapshot::unavailable(
            "claude",
            &account_id,
            &display_name,
            "Not signed in to Claude",
        );
    }
    match run_tui_command(
        "claude",
        &[
            "--strict-mcp-config",
            "--no-chrome",
            "--setting-sources",
            "user",
        ],
        "/usage",
        env,
        TuiCompletion::Generic,
    )
    .await
    {
        Ok(output) => parse_tui_snapshot("claude", &account_id, &display_name, &output),
        Err(error) => command_error_snapshot("claude", &account_id, &display_name, error),
    }
}

fn anthropic_api_environment_present() -> bool {
    ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]
        .iter()
        .any(|name| std::env::var_os(name).is_some_and(|value| !value.is_empty()))
}

async fn claude_auth_status(environment: &BTreeMap<String, String>) -> Option<bool> {
    let mut command = Command::new("claude");
    command
        .args(["auth", "status", "--json"])
        .envs(environment)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    let output = tokio::time::timeout(Duration::from_secs(3), command.output())
        .await
        .ok()?
        .ok()?;
    parse_claude_auth_status(&output.stdout)
}

fn parse_claude_auth_status(output: &[u8]) -> Option<bool> {
    serde_json::from_slice::<Value>(output)
        .ok()?
        .get("loggedIn")?
        .as_bool()
}

enum ClaudeOAuthFetch {
    Snapshot(QuotaSnapshot),
    CredentialsMissing,
    FallbackRequired,
}

async fn fetch_claude_oauth(
    account_id: &str,
    display_name: &str,
    config_dir: &std::path::Path,
) -> Result<ClaudeOAuthFetch> {
    let Some(credentials) = read_claude_oauth_credentials(config_dir).await? else {
        return Ok(ClaudeOAuthFetch::CredentialsMissing);
    };
    let Some(oauth) = credentials.get("claudeAiOauth") else {
        return Ok(ClaudeOAuthFetch::CredentialsMissing);
    };
    let token = oauth
        .get("accessToken")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty());
    let has_refresh_token = oauth
        .get("refreshToken")
        .and_then(Value::as_str)
        .is_some_and(|value| !value.trim().is_empty());
    let Some(token) = token else {
        return Ok(if has_refresh_token {
            ClaudeOAuthFetch::FallbackRequired
        } else {
            ClaudeOAuthFetch::CredentialsMissing
        });
    };
    let response = reqwest::Client::new()
        .get("https://api.anthropic.com/api/oauth/usage")
        .header(AUTHORIZATION, format!("Bearer {token}"))
        .header("anthropic-beta", "oauth-2025-04-20")
        .header("User-Agent", "claude-code/2.1.0")
        .timeout(FETCH_TIMEOUT)
        .send()
        .await?;
    if !response.status().is_success() {
        return Ok(ClaudeOAuthFetch::FallbackRequired);
    }
    let data: Value = response.json().await?;
    let mut windows = Vec::new();
    if let Some(window) = map_claude_oauth_window(
        data.get("five_hour"),
        "5 Hour",
        SESSION_WINDOW_MINUTES,
    ) {
        windows.push(window);
    }
    if let Some(window) =
        map_claude_oauth_window(data.get("seven_day"), "Weekly", WEEKLY_WINDOW_MINUTES)
    {
        windows.push(window);
    }
    let mut buckets = Vec::new();
    if let Some(limits) = data.get("limits").and_then(Value::as_array) {
        for limit in limits {
            if limit.get("is_active").and_then(Value::as_bool) == Some(false) {
                continue;
            }
            let Some(used_percent) = limit.get("percent").and_then(numeric) else {
                continue;
            };
            let name = limit
                .get("scope")
                .and_then(|value| value.get("model"))
                .and_then(|value| value.get("display_name"))
                .and_then(Value::as_str)
                .or_else(|| {
                    limit
                        .get("scope")
                        .and_then(|value| value.get("model"))
                        .and_then(|value| value.get("id"))
                        .and_then(Value::as_str)
                })
                .unwrap_or("Model");
            buckets.push(QuotaBucket {
                name: format!("{name} Weekly"),
                used_percent: used_percent.clamp(0.0, 100.0),
                window_minutes: Some(WEEKLY_WINDOW_MINUTES),
                resets_at: limit.get("resets_at").and_then(claude_reset_millis),
                reset_description: None,
            });
        }
    }
    if windows.is_empty() && buckets.is_empty() {
        Ok(ClaudeOAuthFetch::FallbackRequired)
    } else {
        Ok(ClaudeOAuthFetch::Snapshot(QuotaSnapshot::ok(
            "claude",
            account_id,
            display_name,
            windows,
            buckets,
        )))
    }
}

async fn read_claude_oauth_credentials(config_dir: &std::path::Path) -> Result<Option<Value>> {
    #[cfg(target_os = "macos")]
    for service in claude_keychain_services(config_dir) {
        if let Some(raw) = read_macos_keychain_password(&service).await {
            if let Ok(credentials) = serde_json::from_str::<Value>(&raw) {
                return Ok(Some(credentials));
            }
        }
    }

    let raw = match tokio::fs::read_to_string(config_dir.join(".credentials.json")).await {
        Ok(value) => value,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    Ok(Some(serde_json::from_str(&raw)?))
}

#[cfg(target_os = "macos")]
fn claude_keychain_services(config_dir: &std::path::Path) -> Vec<String> {
    const LEGACY_SERVICE: &str = "Claude Code-credentials";
    let digest = hex::encode(Sha256::digest(config_dir.to_string_lossy().as_bytes()));
    let scoped = format!("{LEGACY_SERVICE}-{}", &digest[..8]);
    if home_dir().is_some_and(|home| config_dir == home.join(".claude")) {
        vec![scoped, LEGACY_SERVICE.to_string()]
    } else {
        vec![scoped]
    }
}

#[cfg(target_os = "macos")]
async fn read_macos_keychain_password(service: &str) -> Option<String> {
    let account = std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "user".to_string());
    let mut command = Command::new("security");
    command
        .args([
            "find-generic-password",
            "-s",
            service,
            "-a",
            &account,
            "-w",
        ])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    let output = tokio::time::timeout(Duration::from_secs(3), command.output())
        .await
        .ok()?
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let credentials = String::from_utf8(output.stdout).ok()?;
    (!credentials.trim().is_empty()).then(|| credentials.trim().to_string())
}

fn map_claude_oauth_window(
    value: Option<&Value>,
    label: &str,
    minutes: i64,
) -> Option<QuotaWindow> {
    let value = value?;
    let used_percent = value
        .get("utilization")
        .or_else(|| value.get("used_percentage"))
        .and_then(numeric)?;
    Some(QuotaWindow {
        label: label.to_string(),
        used_percent: used_percent.clamp(0.0, 100.0),
        window_minutes: Some(minutes),
        resets_at: value.get("resets_at").and_then(claude_reset_millis),
        reset_description: None,
    })
}

fn claude_reset_millis(value: &Value) -> Option<i64> {
    if let Some(timestamp) = value.as_i64() {
        return Some(normalize_timestamp_millis(timestamp));
    }
    let raw = value.as_str()?;
    raw.parse::<i64>()
        .ok()
        .map(normalize_timestamp_millis)
        .or_else(|| parse_timestamp_millis(raw))
}

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
