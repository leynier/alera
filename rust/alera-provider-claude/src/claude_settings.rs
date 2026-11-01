//! Claude Code settings the adapter reads outside skill discovery, from the
//! files the CLI layers, later files winning.

use crate::skills::{
    managed_settings_path, parse_lenient_json, read_text, settings_paths, SkillEnvironment,
};
use claude_agent_sdk::ClaudeAgentOptions;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::PathBuf;

/// The `env.ANTHROPIC_BASE_URL` Claude Code's user and managed settings set
/// for a CLI spawned with [env], T3 Code's `readClaudeSettingsBaseUrl`. The
/// managed file wins over the user one; a file that is unreadable or
/// malformed, or that sets no string, is skipped. Settings apply over the
/// process environment, so a caller falls back to [env]'s own value only
/// when this is `None`.
pub fn claude_settings_base_url(env: &BTreeMap<String, String>) -> Option<String> {
    let options = ClaudeAgentOptions {
        env: env.clone(),
        ..Default::default()
    };
    let environment = SkillEnvironment::new(&options, None);
    let paths = match environment.config_dir() {
        Some(config_dir) => settings_paths(&config_dir, &environment),
        None => managed_settings_path(&environment).into_iter().collect(),
    };
    // Later files win, so the first value from the end is the one in force.
    paths.iter().rev().find_map(|path| {
        let settings = parse_lenient_json(&read_text(path)?)?;
        settings
            .get("env")?
            .get("ANTHROPIC_BASE_URL")?
            .as_str()
            .map(str::to_owned)
    })
}

/// Whether Claude Code's settings forbid the modes Full Access uses.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct BypassAvailability {
    pub(crate) bypass_disabled: bool,
    pub(crate) auto_disabled: bool,
}

/// What the settings files the CLI would read for [environment] say about
/// `bypassPermissions` and `auto`, as T3 Code's `readClaudeBypassAvailability`.
/// `setting_sources`, when set, limits the user, project and local files to
/// the listed sources; managed and remote settings always apply.
pub(crate) fn bypass_availability(
    environment: &SkillEnvironment,
    setting_sources: Option<&[String]>,
) -> BypassAvailability {
    availability_of(&bypass_settings_paths(environment, setting_sources))
}

fn bypass_settings_paths(
    environment: &SkillEnvironment,
    setting_sources: Option<&[String]>,
) -> Vec<PathBuf> {
    let listed =
        |source: &str| setting_sources.is_none_or(|sources| sources.iter().any(|s| s == source));
    let mut paths = Vec::new();
    let config_dir = environment.config_dir();
    if let Some(config_dir) = &config_dir {
        for path in settings_paths(config_dir, environment) {
            let source = if path == config_dir.join("settings.json") {
                "user"
            } else if path.ends_with(".claude/settings.json") {
                "project"
            } else if path.ends_with(".claude/settings.local.json") {
                "local"
            } else {
                "managed"
            };
            if source == "managed" || listed(source) {
                paths.push(path);
            }
        }
        paths.push(config_dir.join("remote-settings.json"));
    } else {
        paths.extend(managed_settings_path(environment));
    }
    if let Some(dropins) = managed_settings_path(environment).and_then(|path| {
        path.parent()
            .map(|parent| parent.join("managed-settings.d"))
    }) {
        let mut files = std::fs::read_dir(dropins)
            .into_iter()
            .flatten()
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "json")
            })
            .collect::<Vec<_>>();
        files.sort();
        paths.extend(files);
    }
    paths
}

/// ORs the restrictions over [paths]. A file that exists but cannot be read
/// or decoded fails closed: it disables bypass.
pub(crate) fn availability_of(paths: &[PathBuf]) -> BypassAvailability {
    let mut availability = BypassAvailability::default();
    for path in paths {
        let text = match std::fs::read(path) {
            Ok(bytes) => String::from_utf8(bytes).ok(),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(_) => None,
        };
        let Some(settings) = text
            .as_deref()
            .and_then(parse_lenient_json)
            .filter(Value::is_object)
        else {
            availability.bypass_disabled = true;
            continue;
        };
        let permissions = settings.get("permissions").unwrap_or(&Value::Null);
        if !permissions.is_null() && !permissions.is_object() {
            availability.bypass_disabled = true;
            continue;
        }
        let mut apply = |value: Option<&Value>, auto: bool| match value {
            None | Some(Value::Null) | Some(Value::Bool(false)) => {}
            Some(Value::String(value)) if value == "disable" => {
                if auto {
                    availability.auto_disabled = true;
                } else {
                    availability.bypass_disabled = true;
                }
            }
            Some(_) => availability.bypass_disabled = true,
        };
        apply(permissions.get("disableBypassPermissionsMode"), false);
        apply(settings.get("disableAutoMode"), true);
        apply(permissions.get("disableAutoMode"), true);
    }
    availability
}

#[cfg(test)]
#[path = "claude_settings_tests.rs"]
mod tests;
