//! `alera runtime settings` and `alera runtime resources`.
//!
//! Only an explicit allowlist of runtime settings is readable or writable
//! here. Credentials, push notifications, voice, quota environment names, text
//! actions, AI Assist commands, and MCP access stay in the Alera app.

use alera_core::runtime::{RuntimeAiAssistSettings, RuntimeSettings, AI_ASSIST_AGENTS};
use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Map, Value};

use crate::cli::{RuntimeDirArgs, RuntimeSettingsAction, RuntimeSettingsCommand};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_AGENT_PROFILES_CAPABILITY, RUNTIME_HOST_RESOURCE_MONITOR_CAPABILITY,
};

/// How a setting's text value is parsed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Flag,
    /// A string that `--unset` clears.
    ClearableText,
    AiAssistAgent,
    Number {
        min: u64,
        max: u64,
    },
}

/// One allowlisted setting: its CLI key, the settings object that holds it
/// (`None` for a top-level field), and the field name on the wire.
struct Setting {
    key: &'static str,
    group: Option<&'static str>,
    field: &'static str,
    kind: Kind,
}

const AI_ASSIST: &str = "aiTextGeneration";
const AUTOMATION: &str = "automation";
const RETENTION_DAYS: Kind = Kind::Number { min: 1, max: 3650 };

const SETTINGS: &[Setting] = &[
    setting(
        "workspaceDirectory",
        None,
        "workspaceDirectory",
        Kind::ClearableText,
    ),
    setting(
        "confirmProjectRemoval",
        None,
        "confirmProjectRemoval",
        Kind::Flag,
    ),
    setting(
        "confirmWorkspaceRemoval",
        None,
        "confirmWorkspaceRemoval",
        Kind::Flag,
    ),
    setting(
        "defaultAgentProfileId",
        None,
        "defaultAgentProfileId",
        Kind::ClearableText,
    ),
    setting("aiAssist.enabled", Some(AI_ASSIST), "enabled", Kind::Flag),
    setting(
        "aiAssist.autoGenerateAgentTitles",
        Some(AI_ASSIST),
        "autoGenerateAgentTitles",
        Kind::Flag,
    ),
    setting(
        "aiAssist.agent",
        Some(AI_ASSIST),
        "agent",
        Kind::AiAssistAgent,
    ),
    setting(
        "aiAssist.timeoutSeconds",
        Some(AI_ASSIST),
        "timeoutSeconds",
        Kind::Number { min: 10, max: 600 },
    ),
    setting(
        "automation.startAtLogin",
        Some(AUTOMATION),
        "autostart",
        Kind::Flag,
    ),
    setting(
        "automation.runRetentionDays",
        Some(AUTOMATION),
        "runRetentionDays",
        RETENTION_DAYS,
    ),
    setting(
        "automation.auditRetentionDays",
        Some(AUTOMATION),
        "auditRetentionDays",
        RETENTION_DAYS,
    ),
    setting(
        "automation.trashRetentionDays",
        Some(AUTOMATION),
        "trashRetentionDays",
        RETENTION_DAYS,
    ),
];

const fn setting(
    key: &'static str,
    group: Option<&'static str>,
    field: &'static str,
    kind: Kind,
) -> Setting {
    Setting {
        key,
        group,
        field,
        kind,
    }
}

/// Every key `runtime settings set` accepts, in display order.
pub(crate) fn setting_keys() -> impl Iterator<Item = &'static str> {
    SETTINGS.iter().map(|setting| setting.key)
}

/// AI Assist agents a setting may select. `custom` needs a command, which is
/// not open to this surface.
pub(crate) fn selectable_ai_assist_agents() -> Vec<&'static str> {
    AI_ASSIST_AGENTS
        .iter()
        .copied()
        .filter(|agent| *agent != "custom")
        .collect()
}

fn find_setting(key: &str) -> Result<&'static Setting> {
    SETTINGS
        .iter()
        .find(|setting| setting.key == key)
        .ok_or_else(|| {
            anyhow!(
                "Unsupported runtime setting: {key}. Supported keys: {}.",
                setting_keys().collect::<Vec<_>>().join(", ")
            )
        })
}

fn parse_value(setting: &Setting, raw: &str) -> Result<Value> {
    let raw = raw.trim();
    match setting.kind {
        Kind::Flag => match raw {
            "true" => Ok(json!(true)),
            "false" => Ok(json!(false)),
            _ => bail!("{} must be true or false.", setting.key),
        },
        Kind::ClearableText if raw.is_empty() => {
            bail!(
                "{} cannot be empty. Use --unset {} to clear it.",
                setting.key,
                setting.key
            )
        }
        Kind::ClearableText => Ok(json!(raw)),
        Kind::AiAssistAgent if selectable_ai_assist_agents().contains(&raw) => Ok(json!(raw)),
        Kind::AiAssistAgent => bail!(
            "{} must be one of: {}.",
            setting.key,
            selectable_ai_assist_agents().join(", ")
        ),
        Kind::Number { min, max } => match raw.parse::<u64>() {
            Ok(value) if (min..=max).contains(&value) => Ok(json!(value)),
            _ => bail!(
                "{} must be a whole number from {min} to {max}.",
                setting.key
            ),
        },
    }
}

/// The allowlisted settings, as `runtime settings show` prints them.
pub(crate) fn settings_view(settings: &RuntimeSettings) -> Result<Value> {
    let wire = settings_wire(settings)?;
    let mut view = Map::new();
    for setting in SETTINGS {
        let value = match setting.group {
            Some(group) => wire[group][setting.field].clone(),
            None => wire[setting.field].clone(),
        };
        match setting.key.split_once('.') {
            Some((section, name)) => {
                let section = view
                    .entry(section)
                    .or_insert_with(|| Value::Object(Map::new()));
                section[name] = value;
            }
            None => {
                view.insert(setting.key.to_string(), value);
            }
        }
    }
    Ok(Value::Object(view))
}

/// Settings on the wire, with AI Assist defaults filled in when it was never
/// configured, as the host applies them.
fn settings_wire(settings: &RuntimeSettings) -> Result<Value> {
    let mut wire = serde_json::to_value(settings).context("could not encode runtime settings")?;
    if wire[AI_ASSIST].is_null() {
        wire[AI_ASSIST] = serde_json::to_value(RuntimeAiAssistSettings::default())?;
    }
    Ok(wire)
}

/// The `runtimeSettings.update` payload for `assignments` (`key=value`) and
/// `unset` keys. Settings that live in an object (AI Assist, automation) are
/// sent whole, so the payload starts from the current values.
pub(crate) fn settings_update_payload(
    current: &RuntimeSettings,
    assignments: &[String],
    unset: &[String],
) -> Result<Value> {
    let wire = settings_wire(current)?;
    let mut payload = Map::new();
    let mut seen = std::collections::HashSet::new();
    let mut apply = |setting: &'static Setting, value: Value| -> Result<()> {
        if !seen.insert(setting.key) {
            bail!("{} is set more than once.", setting.key);
        }
        match setting.group {
            Some(group) => {
                let object = payload.entry(group).or_insert_with(|| wire[group].clone());
                object[setting.field] = value;
            }
            None => {
                payload.insert(setting.field.to_string(), value);
            }
        }
        Ok(())
    };
    for assignment in assignments {
        let (key, raw) = assignment
            .split_once('=')
            .ok_or_else(|| anyhow!("Expected key=value, got {assignment}."))?;
        let setting = find_setting(key.trim())?;
        apply(setting, parse_value(setting, raw)?)?;
    }
    for key in unset {
        let setting = find_setting(key.trim())?;
        if setting.kind != Kind::ClearableText {
            bail!("{} cannot be unset.", setting.key);
        }
        apply(setting, Value::Null)?;
    }
    if payload.is_empty() {
        bail!("Name at least one setting to change.");
    }
    Ok(Value::Object(payload))
}

pub(crate) async fn run_settings(
    runtime: &RuntimeDirArgs,
    command: RuntimeSettingsCommand,
    json_output: bool,
) -> i32 {
    match settings(runtime, command).await {
        Ok((view, message)) => {
            crate::print_value(&view, json_output, message);
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn settings(
    runtime: &RuntimeDirArgs,
    command: RuntimeSettingsCommand,
) -> Result<(Value, &'static str)> {
    let mut client = RuntimeHostRpcClient::connect_or_start(&crate::runtime_dir(runtime)).await?;
    let current: RuntimeSettings = client.request("runtimeSettings.get", &json!({})).await?;
    let RuntimeSettingsAction::Set(args) = command.action else {
        return Ok((settings_view(&current)?, "runtime settings"));
    };
    let payload = settings_update_payload(&current, &args.assignments, &args.unset)?;
    if let Some(profile_id) = payload["defaultAgentProfileId"].as_str() {
        ensure_profile_exists(&mut client, profile_id).await?;
    }
    let saved: RuntimeSettings = client.request("runtimeSettings.update", &payload).await?;
    Ok((settings_view(&saved)?, "runtime settings updated"))
}

async fn ensure_profile_exists(client: &mut RuntimeHostRpcClient, profile_id: &str) -> Result<()> {
    crate::agent_profile_commands::ensure_capabilities(
        client,
        &[RUNTIME_HOST_AGENT_PROFILES_CAPABILITY],
    )
    .await?;
    let (_, profiles) = crate::agent_profile_commands::list_profiles(client).await?;
    if profiles.iter().any(|profile| profile.id == profile_id) {
        Ok(())
    } else {
        bail!("Agent profile not found: {profile_id}. Use an id from agent-profile list.")
    }
}

/// The first snapshot after the monitor starts only says it is warming up,
/// so wait briefly for a measured one.
const RESOURCE_ATTEMPTS: u32 = 12;
const RESOURCE_RETRY: std::time::Duration = std::time::Duration::from_millis(500);

pub(crate) async fn run_resources(runtime: &RuntimeDirArgs, json_output: bool) -> i32 {
    match resources(runtime).await {
        Ok(snapshot) => {
            crate::print_value(&snapshot, json_output, "resource snapshot");
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn resources(runtime: &RuntimeDirArgs) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_RESOURCE_MONITOR_CAPABILITY,
    )
    .await?;
    let mut snapshot = Value::Null;
    for attempt in 0..RESOURCE_ATTEMPTS {
        if attempt > 0 {
            tokio::time::sleep(RESOURCE_RETRY).await;
        }
        snapshot = client
            .request_value("resources.snapshot", &json!({}))
            .await?;
        if snapshot["warming"] != true {
            break;
        }
    }
    Ok(snapshot)
}

#[cfg(test)]
#[path = "runtime_settings_commands_tests.rs"]
mod tests;
