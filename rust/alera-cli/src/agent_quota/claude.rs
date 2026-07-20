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
