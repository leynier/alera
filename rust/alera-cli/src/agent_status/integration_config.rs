use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use alera_core::runtime::RuntimeAgentStatusHookSettings;
use serde_json::{json, Map, Value};

use super::integration_hook_scripts::write_managed_script;
use super::integration_plugins::{
    install_amp_plugin, install_opencode2_plugin, install_opencode_plugin, install_pi_plugin,
    remove_amp_plugin, remove_opencode2_plugin, remove_opencode_plugin, remove_pi_plugin,
};

#[path = "integration_config_ccs.rs"]
mod ccs;
#[path = "integration_config_codex.rs"]
mod codex;
#[path = "integration_config_codex_trust.rs"]
mod codex_hook_trust;
#[path = "integration_config_cursor.rs"]
mod cursor;
#[path = "integration_config_json.rs"]
mod json;
#[path = "integration_config_user_hooks.rs"]
mod user_hooks;
use json::{
    cleanup_agy, cleanup_dedicated_hooks_file, copilot_hooks_path, grok_hooks_path, install_agy,
    install_copilot, install_grok,
};

const MANAGED_MARKER: &str = "alera-runtime-agent-hook";
const LEGACY_MANAGED_MARKERS: [&str; 9] = [
    "alera-codex-hook.",
    "alera-claude-hook.",
    "alera-copilot-hook.",
    "alera-cursor-hook.",
    // Antigravity is the one agent whose desktop installer also writes per-event
    // Windows wrappers (`alera-agy-stop.cmd` and friends), so the marker has to
    // cover the whole `alera-agy-*` family rather than just the core script.
    "alera-agy-",
    "alera-opencode-hook.",
    "alera-pi-hook.",
    "alera-amp-hook.",
    "alera-grok-hook.",
];

pub fn prepare_enabled_integrations(
    _runtime_dir: &Path,
    _session_id: Option<&str>,
    settings: &RuntimeAgentStatusHookSettings,
    environment: &mut BTreeMap<String, String>,
) -> Vec<String> {
    let mut warnings = Vec::new();
    let home = match home_dir() {
        Ok(home) => home,
        Err(error) => {
            warnings.push(error.to_string());
            return warnings;
        }
    };
    let script = if needs_managed_script(settings) {
        match write_managed_script() {
            Ok(script) => Some(script),
            Err(error) => {
                warnings.push(error.to_string());
                return warnings;
            }
        }
    } else {
        None
    };

    let codex_home = resolved_codex_home(&home);
    apply_scripted(
        "Codex",
        settings.codex,
        script.as_deref(),
        |script| codex::install_codex(&codex_home, script),
        || codex::cleanup_codex(&codex_home),
        &mut warnings,
    );
    apply_scripted(
        "Claude",
        settings.claude,
        script.as_deref(),
        |script| install_claude(&home, script, environment),
        || cleanup_claude(&home, environment),
        &mut warnings,
    );
    apply_scripted(
        "Cursor",
        settings.cursor,
        script.as_deref(),
        |script| cursor::install_cursor_user_hooks(&home, script),
        || cursor::cleanup_cursor_user_hooks(&home),
        &mut warnings,
    );
    apply_scripted(
        "Copilot",
        settings.copilot,
        script.as_deref(),
        install_copilot,
        || cleanup_dedicated_hooks_file(&copilot_hooks_path()?),
        &mut warnings,
    );
    apply_scripted(
        "Antigravity",
        settings.agy,
        script.as_deref(),
        install_agy,
        || cleanup_agy(&home),
        &mut warnings,
    );
    apply_scripted(
        "Grok",
        settings.grok,
        script.as_deref(),
        install_grok,
        || cleanup_dedicated_hooks_file(&grok_hooks_path()?),
        &mut warnings,
    );
    apply_plugin(
        "OpenCode",
        settings.opencode,
        install_opencode_plugin,
        remove_opencode_plugin,
        &mut warnings,
    );
    apply_plugin(
        "OpenCode 2",
        settings.opencode2,
        install_opencode2_plugin,
        remove_opencode2_plugin,
        &mut warnings,
    );
    apply_plugin(
        "Pi",
        settings.pi,
        install_pi_plugin,
        remove_pi_plugin,
        &mut warnings,
    );
    apply_plugin(
        "Amp",
        settings.amp,
        install_amp_plugin,
        remove_amp_plugin,
        &mut warnings,
    );
    warnings
}

/// Host start: clear what a previous run left behind, then reconcile.
///
/// The leftover overlay and runtime-home directories belong to older Alera
/// versions. The host owns no PTY yet, so every one of those directories is
/// from a session that no longer exists. Reconcile also runs when every hook
/// toggle is off, which is what makes cleanup reachable.
pub fn start_agent_integrations(
    runtime_dir: &Path,
    settings: &RuntimeAgentStatusHookSettings,
) -> Vec<String> {
    let mut warnings = match clear_legacy_runtime_state(runtime_dir) {
        Ok(()) => Vec::new(),
        Err(error) => vec![error.to_string()],
    };
    warnings.extend(reconcile_agent_integrations(runtime_dir, settings));
    warnings
}

pub fn reconcile_agent_integrations(
    runtime_dir: &Path,
    settings: &RuntimeAgentStatusHookSettings,
) -> Vec<String> {
    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    prepare_enabled_integrations(runtime_dir, None, settings, &mut environment)
}

fn resolved_codex_home(home: &Path) -> PathBuf {
    match env_path("CODEX_HOME") {
        Some(path) if is_legacy_alera_codex_home(&path) => home.join(".codex"),
        Some(path) => path,
        None => home.join(".codex"),
    }
}

fn is_legacy_alera_codex_home(path: &Path) -> bool {
    path.components()
        .any(|component| component.as_os_str() == "agent-runtime-homes")
}

fn needs_managed_script(settings: &RuntimeAgentStatusHookSettings) -> bool {
    settings.codex
        || settings.claude
        || settings.copilot
        || settings.cursor
        || settings.agy
        || settings.grok
}

fn apply_scripted(
    name: &str,
    enabled: bool,
    script: Option<&Path>,
    install: impl FnOnce(&Path) -> anyhow::Result<()>,
    cleanup: impl FnOnce() -> anyhow::Result<()>,
    warnings: &mut Vec<String>,
) {
    let result = if enabled {
        match script {
            Some(script) => install(script),
            None => Err(anyhow::anyhow!("managed script was not written")),
        }
    } else {
        cleanup()
    };
    push_warning(name, result, warnings);
}

fn apply_plugin(
    name: &str,
    enabled: bool,
    install: impl FnOnce() -> anyhow::Result<()>,
    cleanup: impl FnOnce() -> anyhow::Result<()>,
    warnings: &mut Vec<String>,
) {
    let result = if enabled { install() } else { cleanup() };
    push_warning(name, result, warnings);
}

fn push_warning(name: &str, result: anyhow::Result<()>, warnings: &mut Vec<String>) {
    if let Err(error) = result {
        warnings.push(format!("{name}: {error}"));
    }
}

fn install_claude(
    home: &Path,
    script: &Path,
    environment: &BTreeMap<String, String>,
) -> anyhow::Result<()> {
    user_hooks::install_claude_user_hooks(home, script)?;
    ccs::remove_ccs_claude_hooks(home, environment)
}

fn cleanup_claude(home: &Path, environment: &BTreeMap<String, String>) -> anyhow::Result<()> {
    let mut errors = Vec::new();
    if let Err(error) = user_hooks::cleanup_claude_user_hooks(home) {
        errors.push(error.to_string());
    }
    if let Err(error) = ccs::remove_ccs_claude_hooks(home, environment) {
        errors.push(error.to_string());
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(errors.join("; ")))
    }
}

fn clear_legacy_runtime_state(runtime_dir: &Path) -> anyhow::Result<()> {
    let mut errors = Vec::new();
    for relative in ["agent-runtime-homes", "agent-runtime-overlays"] {
        let path = runtime_dir.join(relative);
        if path.exists() {
            if let Err(error) = std::fs::remove_dir_all(&path) {
                errors.push(format!("{}: {error}", path.display()));
            }
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(errors.join("; ")))
    }
}

pub(super) const CLAUDE_HOOK_EVENTS: &[(&str, Option<&str>)] = &[
    ("UserPromptSubmit", None),
    ("Stop", None),
    ("PreToolUse", Some("*")),
    ("PostToolUse", Some("*")),
    ("PostToolUseFailure", Some("*")),
    ("PermissionRequest", Some("*")),
];

pub(super) fn install_claude_hooks_into(settings: &mut Map<String, Value>, script: &Path) {
    let hooks = object_field(settings, "hooks");
    for (event, matcher) in CLAUDE_HOOK_EVENTS {
        let command = managed_command(script, "claude", event);
        let mut definitions = clean_managed_definitions(hooks.remove(*event));
        definitions.push(managed_hook_definition(*matcher, &command));
        hooks.insert((*event).to_string(), Value::Array(definitions));
    }
}

// Non-tool events have nothing to match on. Their schemas expect the key to be
// absent rather than null, so emitting `null` trips agent-side validation.
pub(super) fn managed_hook_definition(matcher: Option<&str>, command: &str) -> Value {
    let mut definition = Map::new();
    if let Some(matcher) = matcher {
        definition.insert("matcher".to_string(), json!(matcher));
    }
    definition.insert(
        "hooks".to_string(),
        json!([{ "type": "command", "command": command }]),
    );
    Value::Object(definition)
}

pub(super) fn managed_command(script: &Path, agent: &str, event: &str) -> String {
    #[cfg(windows)]
    {
        format!(
            "cmd /d /s /c \"set ALERA_AGENT_TYPE={agent}&& set ALERA_AGENT_HOOK_EVENT={event}&& call \"\"{}\"\"\"",
            script.display()
        )
    }
    #[cfg(not(windows))]
    {
        format!(
            "ALERA_AGENT_TYPE={} ALERA_AGENT_HOOK_EVENT={} /bin/sh {}",
            sh_quote(agent),
            sh_quote(event),
            sh_quote(&path_string(script)),
        )
    }
}

pub(super) fn clean_managed_definitions(value: Option<Value>) -> Vec<Value> {
    value
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .filter(|definition| !is_alera_managed_definition(definition))
        .collect()
}

pub(super) fn is_alera_managed_definition(definition: &Value) -> bool {
    let encoded = definition.to_string();
    encoded.contains(MANAGED_MARKER)
        || LEGACY_MANAGED_MARKERS
            .iter()
            .any(|marker| encoded.contains(marker))
}

pub(super) fn object_field<'a>(
    object: &'a mut Map<String, Value>,
    key: &str,
) -> &'a mut Map<String, Value> {
    if !object.get(key).is_some_and(Value::is_object) {
        object.insert(key.to_string(), Value::Object(Map::new()));
    }
    object
        .get_mut(key)
        .and_then(Value::as_object_mut)
        .expect("object inserted")
}

pub(super) fn read_json_object(path: &Path) -> anyhow::Result<Option<Map<String, Value>>> {
    match std::fs::read_to_string(path) {
        Ok(contents) => Ok(serde_json::from_str::<Value>(&contents)?
            .as_object()
            .cloned()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

pub(super) fn write_json_object(path: &Path, value: &Map<String, Value>) -> anyhow::Result<()> {
    let serialized = format!("{}\n", serde_json::to_string_pretty(value)?);
    if path.is_file() {
        if let Ok(existing) = std::fs::read_to_string(path) {
            if existing == serialized {
                return Ok(());
            }
        }
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, serialized)?;
    Ok(())
}

pub(super) fn home_dir() -> anyhow::Result<PathBuf> {
    dirs::home_dir().ok_or_else(|| anyhow::anyhow!("Could not resolve the user home directory."))
}

pub(super) fn env_path(key: &str) -> Option<PathBuf> {
    std::env::var_os(key)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

#[cfg(not(windows))]
fn sh_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

#[cfg(test)]
#[path = "integration_config_tests.rs"]
mod tests;
