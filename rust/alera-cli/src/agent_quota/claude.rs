async fn fetch_claude(profile: Option<&ClaudeProfileRequest>) -> QuotaSnapshot {
    let (account_id, display_name, config_dir, _env) = match resolve_claude_account(profile).await {
        Ok(value) => value,
        Err(snapshot) => return snapshot,
    };
    let api_environment_present = anthropic_api_environment_present().await;
    let oauth = match config_dir.as_deref() {
        Some(config_dir) => fetch_claude_oauth(&account_id, &display_name, config_dir)
            .await
            .unwrap_or(ClaudeOAuthFetch::FallbackRequired),
        None => ClaudeOAuthFetch::CredentialsMissing(ClaudeCredentialGap::Absent),
    };
    match oauth {
        ClaudeOAuthFetch::Snapshot(snapshot) => snapshot,
        ClaudeOAuthFetch::CredentialsMissing(gap) if !api_environment_present => {
            QuotaSnapshot::unavailable("claude", &account_id, &display_name, gap.message())
        }
        ClaudeOAuthFetch::CredentialsMissing(_) | ClaudeOAuthFetch::FallbackRequired => {
            QuotaSnapshot::unavailable(
                "claude",
                &account_id,
                &display_name,
                "Claude OAuth usage is unavailable",
            )
        }
    }
}

/// Why an account has no usable OAuth credentials.
///
/// These collapsed into a single "not signed in" message, which is wrong for
/// two of the three: an unreadable keychain item and a credential blob in an
/// unexpected shape both belong to an account that *is* signed in, and each
/// needs a different thing from the user.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ClaudeCredentialGap {
    /// No credential store holds anything for this config directory.
    Absent,
    /// A credential store holds something that could not be read. On macOS the
    /// usual cause is a keychain item whose access control has not been granted
    /// to this binary yet.
    #[cfg(target_os = "macos")]
    Unreadable,
    /// Credentials were read but carry no `claudeAiOauth` entry, so the account
    /// authenticates some other way.
    NotOauth,
}

impl ClaudeCredentialGap {
    fn message(self) -> &'static str {
        match self {
            ClaudeCredentialGap::Absent => "Not signed in to Claude",
            #[cfg(target_os = "macos")]
            ClaudeCredentialGap::Unreadable => {
                "Claude credentials could not be read; allow Alera access to the Claude Code keychain item"
            }
            ClaudeCredentialGap::NotOauth => "Claude credentials are not OAuth credentials",
        }
    }
}

/// Explicit Claude TUI scrape for one account. Used by `agentQuota.fetchClaudeTui`.
pub(crate) async fn fetch_claude_tui(account_id: &str, display_name: &str) -> Value {
    let snapshot = fetch_claude_tui_snapshot(account_id, display_name).await;
    serde_json::to_value(snapshot).expect("quota snapshot serializes")
}

async fn fetch_claude_tui_snapshot(account_id: &str, display_name: &str) -> QuotaSnapshot {
    let profile = if account_id == "default" {
        None
    } else {
        Some(ClaudeProfileRequest {
            alias: display_name.to_string(),
            profile: account_id.to_string(),
        })
    };
    let (account_id, display_name, _config_dir, env) =
        match resolve_claude_account(profile.as_ref()).await {
            Ok(value) => value,
            Err(snapshot) => return snapshot,
        };
    let api_environment_present = anthropic_api_environment_present().await;
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

type ClaudeAccountParts = (String, String, Option<PathBuf>, BTreeMap<String, String>);

#[allow(clippy::result_large_err, clippy::type_complexity)]
async fn resolve_claude_account(
    profile: Option<&ClaudeProfileRequest>,
) -> Result<ClaudeAccountParts, QuotaSnapshot> {
    match profile {
        None => {
            let config_dir = home_dir().map(|home| home.join(".claude"));
            Ok((
                "default".to_string(),
                "Default".to_string(),
                config_dir,
                BTreeMap::new(),
            ))
        }
        Some(profile) => {
            let Some(home) = home_dir() else {
                return Err(QuotaSnapshot::unavailable(
                    "claude",
                    &profile.profile,
                    &profile.alias,
                    "Home directory is unavailable",
                ));
            };
            let ccs_root = shell_environment_value("CCS_DIR")
                .await
                .map(PathBuf::from)
                .unwrap_or_else(|| home.join(".ccs"));
            let config_dir = ccs_root.join("instances").join(&profile.profile);
            if !config_dir.exists() {
                return Err(QuotaSnapshot::unavailable(
                    "claude",
                    &profile.profile,
                    &profile.alias,
                    format!("CCS profile not found: {}", profile.profile),
                ));
            }
            Ok((
                profile.profile.clone(),
                profile.alias.clone(),
                Some(config_dir.clone()),
                BTreeMap::from([(
                    "CLAUDE_CONFIG_DIR".to_string(),
                    config_dir.to_string_lossy().to_string(),
                )]),
            ))
        }
    }
}

async fn anthropic_api_environment_present() -> bool {
    for name in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"] {
        if shell_environment_value(name).await.is_some() {
            return true;
        }
    }
    false
}

async fn claude_auth_status(environment: &BTreeMap<String, String>) -> Option<bool> {
    let mut command = windowless_async_command("claude");
    command
        .args(["auth", "status", "--json"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    crate::login_shell_environment::apply_login_shell_environment(&mut command, environment).await;
    let output = tokio::time::timeout(KEYCHAIN_TIMEOUT, command.output())
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

#[allow(clippy::large_enum_variant)]
enum ClaudeOAuthFetch {
    Snapshot(QuotaSnapshot),
    CredentialsMissing(ClaudeCredentialGap),
    FallbackRequired,
}

async fn fetch_claude_oauth(
    account_id: &str,
    display_name: &str,
    config_dir: &std::path::Path,
) -> Result<ClaudeOAuthFetch> {
    let credentials = match read_claude_oauth_credentials(config_dir).await? {
        ClaudeCredentialRead::Credentials(credentials) => credentials,
        ClaudeCredentialRead::Missing(gap) => {
            return Ok(ClaudeOAuthFetch::CredentialsMissing(gap))
        }
    };
    let Some(oauth) = credentials.get("claudeAiOauth") else {
        return Ok(ClaudeOAuthFetch::CredentialsMissing(
            ClaudeCredentialGap::NotOauth,
        ));
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
            ClaudeOAuthFetch::CredentialsMissing(ClaudeCredentialGap::NotOauth)
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

enum ClaudeCredentialRead {
    Credentials(Value),
    Missing(ClaudeCredentialGap),
}

async fn read_claude_oauth_credentials(
    config_dir: &std::path::Path,
) -> Result<ClaudeCredentialRead> {
    #[allow(unused_mut)]
    let mut gap = ClaudeCredentialGap::Absent;

    #[cfg(target_os = "macos")]
    for service in claude_keychain_services(config_dir) {
        match read_macos_keychain_password(&service).await {
            KeychainRead::Password(raw) => match serde_json::from_str::<Value>(&raw) {
                Ok(credentials) => return Ok(ClaudeCredentialRead::Credentials(credentials)),
                Err(_) => gap = ClaudeCredentialGap::NotOauth,
            },
            // The item is there but its access control has not been granted to
            // this binary, so reporting "not signed in" would send the user to
            // re-authenticate a session that is perfectly valid.
            KeychainRead::Unreadable => {
                tracing::warn!(service, "Claude keychain item could not be read");
                gap = ClaudeCredentialGap::Unreadable;
            }
            KeychainRead::Absent => {}
        }
    }

    let raw = match tokio::fs::read_to_string(config_dir.join(".credentials.json")).await {
        Ok(value) => value,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(ClaudeCredentialRead::Missing(gap))
        }
        Err(error) => return Err(error.into()),
    };
    Ok(ClaudeCredentialRead::Credentials(serde_json::from_str(
        &raw,
    )?))
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

/// `security` exit code for an item that is not in the keychain at all.
#[cfg(target_os = "macos")]
const SECURITY_ITEM_NOT_FOUND: i32 = 44;

#[cfg(target_os = "macos")]
enum KeychainRead {
    Password(String),
    Absent,
    Unreadable,
}

#[cfg(target_os = "macos")]
async fn read_macos_keychain_password(service: &str) -> KeychainRead {
    let account = match shell_environment_value("USER").await {
        Some(account) => account,
        None => shell_environment_value("USERNAME")
            .await
            .unwrap_or_else(|| "user".to_string()),
    };
    let mut command = windowless_async_command("security");
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
    let output = match tokio::time::timeout(KEYCHAIN_TIMEOUT, command.output()).await {
        Ok(Ok(output)) => output,
        Ok(Err(_)) | Err(_) => return KeychainRead::Unreadable,
    };
    if !output.status.success() {
        return if output.status.code() == Some(SECURITY_ITEM_NOT_FOUND) {
            KeychainRead::Absent
        } else {
            KeychainRead::Unreadable
        };
    }
    let Ok(credentials) = String::from_utf8(output.stdout) else {
        return KeychainRead::Unreadable;
    };
    if credentials.trim().is_empty() {
        KeychainRead::Absent
    } else {
        KeychainRead::Password(credentials.trim().to_string())
    }
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
