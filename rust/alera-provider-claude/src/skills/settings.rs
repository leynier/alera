//! The settings that shape the skill list: `skillOverrides` and
//! `enabledPlugins`, read across the files Claude Code layers, later files
//! winning, as T3 Code's `readSkillSettings` does.

use super::environment::SkillEnvironment;
use super::lenient_json::parse_lenient_json;
use super::paths::{exists, join, read_text, resolve};
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct SkillOverride {
    pub enabled: bool,
    pub user_invocation_only: bool,
}

#[derive(Debug, Default)]
pub(crate) struct SkillSettings {
    pub skill_overrides: HashMap<String, SkillOverride>,
    pub enabled_plugins: HashMap<String, bool>,
}

pub(crate) fn read_skill_settings(
    config_dir: &Path,
    environment: &SkillEnvironment,
) -> SkillSettings {
    let mut settings = SkillSettings::default();
    for path in settings_paths(config_dir, environment) {
        let Some(contents) = read_text(&path) else {
            continue;
        };
        let Some(file) = parse_lenient_json(&contents).and_then(decode_settings) else {
            continue;
        };
        settings.skill_overrides.extend(file.skill_overrides);
        for (key, enabled) in file.enabled_plugins {
            match enabled.as_bool() {
                Some(enabled) => {
                    settings.enabled_plugins.insert(key, enabled);
                }
                // Extended formats replace lower-precedence values without enabling the plugin here.
                None => {
                    settings.enabled_plugins.remove(&key);
                }
            }
        }
    }
    settings
}

struct SettingsFile {
    skill_overrides: Vec<(String, SkillOverride)>,
    enabled_plugins: Map<String, Value>,
}

/// The CLI validates the whole override map: one unknown value (or a
/// boolean) makes it drop the file, so its valid siblings are ignored too.
fn decode_settings(value: Value) -> Option<SettingsFile> {
    let Value::Object(mut root) = value else {
        return None;
    };
    let skill_overrides = match root.remove("skillOverrides") {
        None => Vec::new(),
        Some(Value::Object(overrides)) => overrides
            .into_iter()
            .map(|(name, value)| Some((name, parse_override(value.as_str()?)?)))
            .collect::<Option<Vec<_>>>()?,
        Some(_) => return None,
    };
    let enabled_plugins = match root.remove("enabledPlugins") {
        None => Map::new(),
        Some(Value::Object(plugins)) => plugins,
        Some(_) => return None,
    };
    Some(SettingsFile {
        skill_overrides,
        enabled_plugins,
    })
}

fn parse_override(value: &str) -> Option<SkillOverride> {
    let (enabled, user_invocation_only) = match value {
        "off" => (false, false),
        "user-invocable-only" => (true, true),
        "on" | "name-only" => (true, false),
        _ => return None,
    };
    Some(SkillOverride {
        enabled,
        user_invocation_only,
    })
}

/// User, project, project local, repository root local, then managed. From
/// a nested cwd the CLI reads only the root's local file.
fn settings_paths(config_dir: &Path, environment: &SkillEnvironment) -> Vec<PathBuf> {
    let cwd = environment.cwd();
    let mut paths = vec![join(config_dir, &["settings.json"])];
    if let Some(cwd) = cwd {
        paths.push(join(cwd, &[".claude", "settings.json"]));
        paths.push(join(cwd, &[".claude", "settings.local.json"]));
        if let Some(root) = find_repository_root(cwd) {
            if root != resolve(None, cwd) {
                paths.push(join(&root, &[".claude", "settings.local.json"]));
            }
        }
    }
    paths.extend(managed_settings_path(environment));
    paths
}

fn managed_settings_path(environment: &SkillEnvironment) -> Option<PathBuf> {
    if cfg!(target_os = "macos") {
        return Some("/Library/Application Support/ClaudeCode/managed-settings.json".into());
    }
    if cfg!(windows) {
        let program_data = environment.var("PROGRAMDATA")?;
        let program_data = program_data.trim();
        return (!program_data.is_empty()).then(|| {
            join(
                Path::new(program_data),
                &["ClaudeCode", "managed-settings.json"],
            )
        });
    }
    Some("/etc/claude-code/managed-settings.json".into())
}

/// The nearest ancestor of [cwd], itself included, that holds `.git`.
pub(crate) fn find_repository_root(cwd: &Path) -> Option<PathBuf> {
    let mut current = resolve(None, cwd);
    loop {
        if exists(&current.join(".git")) {
            return Some(current);
        }
        if !current.pop() {
            return None;
        }
    }
}
