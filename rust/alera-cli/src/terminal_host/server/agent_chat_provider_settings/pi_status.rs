//! Explains a Pi default model that cannot start a turn, as T3 Code does.
//! Pi lists only models of providers it holds credentials for, so a default
//! whose provider lists nothing would fail every chat that keeps it.

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

use serde_json::Value;

use super::discovery::parse_cli;
use super::probe::{ProbeCommand, ProviderProbe};

/// `pi auth check --json --no-refresh` arrived in Pi 0.84.1.
const AUTH_CHECK_VERSION: (u64, u64, u64) = (0, 84, 1);
const MAX_SETTINGS_BYTES: u64 = 1024 * 1024;

pub(crate) const NO_MODELS: &str = "Pi has no usable models. Run `pi` in a terminal and use /login, or configure an API key in ~/.pi/agent.";

/// Pi's active default: launch arguments first, then its global settings.
#[derive(Debug, PartialEq)]
pub(crate) struct PiDefault {
    pub provider: String,
    pub model: Option<String>,
}

pub(crate) async fn pi_model_note(
    executable: &Path,
    args: &[OsString],
    environment: &BTreeMap<String, String>,
    version: Option<&str>,
    probe: &dyn ProviderProbe,
) -> Option<String> {
    let run = |args: &[&str]| ProbeCommand {
        executable: executable.into(),
        args: args.iter().map(|arg| (*arg).to_owned()).collect(),
        environment: environment.clone(),
        cwd: None,
    };
    let listing = probe.run(run(&["--list-models"])).await.ok()?;
    if !listing.success {
        return None;
    }
    let models = parse_cli("pi", &listing.stdout).ok()?;
    if models.is_empty() {
        return Some(NO_MODELS.into());
    }
    let default = launch_default(args).or_else(|| settings_default(environment))?;
    let prefix = format!("{}/", default.provider);
    if models
        .iter()
        .filter_map(|model| model["id"].as_str())
        .any(|id| id.starts_with(&prefix))
    {
        return None;
    }
    let label = match &default.model {
        Some(model) => format!("Pi default ({}/{model})", default.provider),
        None => format!("Pi default ({})", default.provider),
    };
    let unavailable = format!(
        "{label} uses {}, which has no available models in Pi. Choose another model, or check that provider's setup and the Pi launch arguments.",
        default.provider
    );
    // Auth check cannot see extension providers or a runtime --api-key, so it
    // only refines Pi's own verdict, and is skipped when the arguments give a key.
    if !version.and_then(semver).is_some_and(|v| v >= AUTH_CHECK_VERSION)
        || args.iter().any(|arg| arg == "--api-key")
    {
        return Some(unavailable);
    }
    let check = probe
        .run(run(&[
            "auth",
            "check",
            "--provider",
            &default.provider,
            "--json",
            "--no-refresh",
        ]))
        .await
        .ok();
    // Pi exits nonzero for a provider that is not ready, so read the JSON.
    let missing = check
        .and_then(|output| serde_json::from_str::<Value>(output.stdout.trim()).ok())
        .is_some_and(|check| check["reason"] == "credentials_not_configured");
    Some(if missing {
        format!(
            "{label} has no credentials configured for {}. Choose another model, or run `pi` in a terminal and use /login or configure its API key.",
            default.provider
        )
    } else {
        unavailable
    })
}

pub(crate) fn launch_default(args: &[OsString]) -> Option<PiDefault> {
    let value = |flag: &str| {
        args.iter()
            .position(|arg| arg == flag)
            .and_then(|index| args.get(index + 1))
            .and_then(|value| value.to_str())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
    };
    let model = value("--model");
    match (value("--provider"), model) {
        (Some(provider), model) => Some(PiDefault { provider, model }),
        (None, Some(model)) => {
            let (provider, id) = model.split_once('/')?;
            Some(PiDefault {
                provider: provider.into(),
                model: Some(id.into()),
            })
        }
        (None, None) => None,
    }
}

fn settings_default(environment: &BTreeMap<String, String>) -> Option<PiDefault> {
    let directory = environment
        .get("PI_CODING_AGENT_DIR")
        .filter(|value| !value.trim().is_empty())
        .map(|value| expand_home(value, environment))
        .or_else(|| {
            environment
                .get(if cfg!(windows) { "USERPROFILE" } else { "HOME" })
                .map(|home| Path::new(home).join(".pi").join("agent"))
        })?;
    let path = directory.join("settings.json");
    if std::fs::metadata(&path).ok()?.len() > MAX_SETTINGS_BYTES {
        return None;
    }
    let settings: Value = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
    parse_settings(&settings)
}

pub(crate) fn parse_settings(settings: &Value) -> Option<PiDefault> {
    let text = |key: &str| {
        settings[key]
            .as_str()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
    };
    Some(PiDefault {
        provider: text("defaultProvider")?,
        model: text("defaultModel"),
    })
}

fn expand_home(value: &str, environment: &BTreeMap<String, String>) -> PathBuf {
    let home = environment.get(if cfg!(windows) { "USERPROFILE" } else { "HOME" });
    match (value.strip_prefix("~/"), home) {
        (Some(rest), Some(home)) => Path::new(home).join(rest),
        _ if value == "~" => home.map(PathBuf::from).unwrap_or_else(|| value.into()),
        _ => PathBuf::from(value),
    }
}

fn semver(version: &str) -> Option<(u64, u64, u64)> {
    let core = version.trim().trim_start_matches('v');
    let core = core.split(['-', '+']).next()?;
    let mut parts = core.split('.').map(|part| part.parse::<u64>().ok());
    Some((parts.next()??, parts.next()??, parts.next()??))
}

#[cfg(test)]
#[path = "pi_status_tests.rs"]
mod tests;
