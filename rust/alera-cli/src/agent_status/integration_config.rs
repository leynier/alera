use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use alera_core::runtime::RuntimeAgentStatusHookSettings;
use serde_json::{json, Map, Value};

use self::codex_hook_trust::{codex_trusted_hash, remap_codex_source_hook_trust};
use self::cursor_overlay::prepare_cursor;
use super::integration_hook_scripts::write_managed_script;
use super::integration_plugins::{
    install_amp_plugin, install_opencode2_plugin, install_opencode_plugin, install_pi_plugin,
};

#[path = "integration_config_codex_trust.rs"]
mod codex_hook_trust;
#[path = "integration_config_cursor_overlay.rs"]
mod cursor_overlay;

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
    runtime_dir: &Path,
    session_id: Option<&str>,
    settings: &RuntimeAgentStatusHookSettings,
    environment: &mut BTreeMap<String, String>,
) -> Vec<String> {
    let mut warnings = Vec::new();
    let script = match write_managed_script() {
        Ok(script) => script,
        Err(error) => {
            warnings.push(error.to_string());
            return warnings;
        }
    };
    if settings.codex {
        match prepare_codex(runtime_dir, &script) {
            Ok(home) => {
                environment.insert("CODEX_HOME".to_string(), path_string(&home));
                environment.insert("ALERA_CODEX_HOME".to_string(), path_string(&home));
            }
            Err(error) => warnings.push(format!("Codex: {error}")),
        }
    }
    if settings.claude {
        match prepare_claude(runtime_dir, &script) {
            Ok(home) => {
                environment.insert("CLAUDE_CONFIG_DIR".to_string(), path_string(&home));
                environment.insert("ALERA_CLAUDE_CONFIG_DIR".to_string(), path_string(&home));
            }
            Err(error) => warnings.push(format!("Claude: {error}")),
        }
    }
    // The Cursor plugin is per terminal session, so it can only be built when a
    // session is being launched. `reconcile_agent_integrations` has none.
    if let (true, Some(session_id)) = (settings.cursor, session_id) {
        if let Err(error) = prepare_cursor(runtime_dir, session_id, &script, environment) {
            warnings.push(format!("Cursor: {error}"));
        }
    }
    for result in [
        settings.copilot.then(|| install_copilot(&script)),
        settings.agy.then(|| install_agy(&script)),
        settings.grok.then(|| install_grok(&script)),
        settings.opencode.then(install_opencode_plugin),
        settings.opencode2.then(install_opencode2_plugin),
        settings.pi.then(install_pi_plugin),
        settings.amp.then(install_amp_plugin),
    ]
    .into_iter()
    .flatten()
    {
        if let Err(error) = result {
            warnings.push(error.to_string());
        }
    }
    warnings
}

/// Host start: clear what a previous run left behind, then reconcile.
///
/// The clearing has to happen here and only here. The host owns no PTY yet, so
/// this is the one moment a per-session leftover is provably dead, and it is
/// also the only point that runs when every hook toggle is off.
pub fn start_agent_integrations(
    runtime_dir: &Path,
    settings: &RuntimeAgentStatusHookSettings,
) -> Vec<String> {
    let mut warnings =
        match home_dir().and_then(|home| cursor_overlay::clear_stale_state(runtime_dir, &home)) {
            Ok(()) => Vec::new(),
            Err(error) => vec![format!("Cursor: {error}")],
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

fn prepare_codex(runtime_dir: &Path, script: &Path) -> anyhow::Result<PathBuf> {
    let source = home_dir()?.join(".codex");
    let runtime_home = runtime_dir.join("agent-runtime-homes/codex/home");
    std::fs::create_dir_all(&runtime_home)?;
    copy_if_present(&source.join("auth.json"), &runtime_home.join("auth.json"))?;
    for entry in [
        "skills",
        "plugins",
        "plugin-state",
        "profile-v2",
        "themes",
        "prompts",
        "sessions",
    ] {
        link_if_present(&source.join(entry), &runtime_home.join(entry));
    }

    let source_hooks = read_json_object(&source.join("hooks.json"))?.unwrap_or_default();
    let mut config = source_hooks;
    let hooks = object_field(&mut config, "hooks");
    let events = [
        ("SessionStart", "session_start"),
        ("UserPromptSubmit", "user_prompt_submit"),
        ("PreToolUse", "pre_tool_use"),
        ("PermissionRequest", "permission_request"),
        ("PostToolUse", "post_tool_use"),
        ("Stop", "stop"),
    ];
    let hooks_path = runtime_home.join("hooks.json");
    let mut trust = Vec::new();
    for (event, label) in events {
        let command = managed_command(script, "codex", event);
        let definitions = clean_managed_definitions(hooks.remove(event));
        let index = definitions.len();
        let mut next = definitions;
        next.push(json!({
            "hooks": [{ "type": "command", "command": command }],
        }));
        hooks.insert(event.to_string(), Value::Array(next));
        trust.push((label, index, command));
    }
    write_json_object(&hooks_path, &config)?;

    let source_config = std::fs::read_to_string(source.join("config.toml")).unwrap_or_default();
    let mut toml_value = toml::from_str::<toml::Value>(&source_config)
        .unwrap_or_else(|_| toml::Value::Table(Default::default()));
    let root = toml_value
        .as_table_mut()
        .ok_or_else(|| anyhow::anyhow!("Codex config.toml root is not a table"))?;
    table_field(root, "features").insert("hooks".to_string(), toml::Value::Boolean(true));
    let state = table_field(table_field(root, "hooks"), "state");
    let canonical_hooks_path = std::fs::canonicalize(&hooks_path).unwrap_or(hooks_path.clone());
    // Source-home trust keys still point at ~/.codex/hooks.json after the
    // definitions are copied into the isolated runtime home; remap only those
    // existing records so already-trusted user hooks stay trusted.
    remap_codex_source_hook_trust(state, &source.join("hooks.json"), &canonical_hooks_path);
    for (label, index, command) in trust {
        let key = format!("{}:{label}:{index}:0", canonical_hooks_path.display());
        let mut entry = toml::map::Map::new();
        entry.insert("enabled".to_string(), toml::Value::Boolean(true));
        entry.insert(
            "trusted_hash".to_string(),
            toml::Value::String(codex_trusted_hash(label, &command)),
        );
        state.insert(key, toml::Value::Table(entry));
    }
    std::fs::write(
        runtime_home.join("config.toml"),
        toml::to_string(&toml_value)?,
    )?;
    Ok(runtime_home)
}

fn prepare_claude(runtime_dir: &Path, script: &Path) -> anyhow::Result<PathBuf> {
    let source = home_dir()?.join(".claude");
    let runtime_home = runtime_dir.join("agent-runtime-homes/claude/home");
    std::fs::create_dir_all(&runtime_home)?;
    if source.exists() {
        for entry in std::fs::read_dir(&source)? {
            let entry = entry?;
            if entry.file_name() != "settings.json" {
                link_if_present(&entry.path(), &runtime_home.join(entry.file_name()));
            }
        }
    }
    let mut settings = read_json_object(&source.join("settings.json"))?.unwrap_or_default();
    let hooks = object_field(&mut settings, "hooks");
    for (event, matcher) in [
        ("UserPromptSubmit", None),
        ("Stop", None),
        ("PreToolUse", Some("*")),
        ("PostToolUse", Some("*")),
        ("PostToolUseFailure", Some("*")),
        ("PermissionRequest", Some("*")),
    ] {
        let command = managed_command(script, "claude", event);
        let mut definitions = clean_managed_definitions(hooks.remove(event));
        definitions.push(managed_hook_definition(matcher, &command));
        hooks.insert(event.to_string(), Value::Array(definitions));
    }
    write_json_object(&runtime_home.join("settings.json"), &settings)?;
    Ok(runtime_home)
}

fn install_copilot(script: &Path) -> anyhow::Result<()> {
    let home = env_path("COPILOT_HOME").unwrap_or(home_dir()?.join(".copilot"));
    let path = home.join("hooks/alera.json");
    let events = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "SubagentStart",
        "SubagentStop",
        "PreCompact",
        "Stop",
        "ErrorOccurred",
        "PermissionRequest",
        "Notification",
    ];
    let hooks = events
        .into_iter()
        .map(|event| {
            (
                event.to_string(),
                json!([{ "type": "command", "bash": managed_command(script, "copilot", event), "timeoutSec": 5 }]),
            )
        })
        .collect::<Map<_, _>>();
    write_json_object(
        &path,
        &Map::from_iter([
            ("version".to_string(), json!(1)),
            ("hooks".to_string(), Value::Object(hooks)),
        ]),
    )
}

fn install_grok(script: &Path) -> anyhow::Result<()> {
    let home = env_path("GROK_HOME").unwrap_or(home_dir()?.join(".grok"));
    let path = home.join("hooks/alera-status.json");
    let hooks = [
        ("SessionStart", None),
        ("UserPromptSubmit", None),
        ("PreToolUse", Some("*")),
        ("PostToolUse", Some("*")),
        ("PostToolUseFailure", Some("*")),
        ("Notification", None),
        ("Stop", None),
        ("StopFailure", None),
        ("SessionEnd", None),
    ]
    .into_iter()
    .map(|(event, matcher)| {
        (
            event.to_string(),
            json!([managed_hook_definition(
                matcher,
                &managed_command(script, "grok", event)
            )]),
        )
    })
    .collect::<Map<_, _>>();
    write_json_object(
        &path,
        &Map::from_iter([("hooks".to_string(), Value::Object(hooks))]),
    )
}

fn install_agy(script: &Path) -> anyhow::Result<()> {
    let path = home_dir()?.join(".gemini/config/hooks.json");
    let mut config = read_json_object(&path)?.unwrap_or_default();
    apply_agy_bundle(&mut config, script);
    write_json_object(&path, &config)
}

// Antigravity keeps each hook set under its own top-level key and uses two
// schemas inside it: lifecycle events take a flat `{ type, command }` handler,
// tool events a matcher wrapping `hooks`. `PreToolUse` is deliberately absent -
// Antigravity requires a permission `decision` from it, which an observational
// hook cannot give without taking over the user's tool policy.
fn apply_agy_bundle(config: &mut Map<String, Value>, script: &Path) {
    let bundle = object_field(config, "alera-status");
    // Installing is an explicit request to enable, so the documented `enabled`
    // opt-out cannot survive it. Every other non-event key is left alone.
    bundle.remove("enabled");
    for event in ["PreInvocation", "PostInvocation", "Stop"] {
        let mut definitions = clean_managed_definitions(bundle.remove(event));
        definitions.push(
            json!({ "type": "command", "command": managed_command(script, "agy", event), "timeout": 10 }),
        );
        bundle.insert(event.to_string(), Value::Array(definitions));
    }
    let mut tool_definitions = clean_managed_definitions(bundle.remove("PostToolUse"));
    tool_definitions.push(
        json!({ "matcher": "*", "hooks": [{ "type": "command", "command": managed_command(script, "agy", "PostToolUse"), "timeout": 10 }] }),
    );
    bundle.insert("PostToolUse".to_string(), Value::Array(tool_definitions));
}

// Non-tool events have nothing to match on. Their schemas expect the key to be
// absent rather than null, so emitting `null` trips agent-side validation.
fn managed_hook_definition(matcher: Option<&str>, command: &str) -> Value {
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

fn managed_command(script: &Path, agent: &str, event: &str) -> String {
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

fn clean_managed_definitions(value: Option<Value>) -> Vec<Value> {
    value
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .filter(|definition| !is_alera_managed_definition(definition))
        .collect()
}

fn is_alera_managed_definition(definition: &Value) -> bool {
    let encoded = definition.to_string();
    encoded.contains(MANAGED_MARKER)
        || LEGACY_MANAGED_MARKERS
            .iter()
            .any(|marker| encoded.contains(marker))
}

fn object_field<'a>(object: &'a mut Map<String, Value>, key: &str) -> &'a mut Map<String, Value> {
    if !object.get(key).is_some_and(Value::is_object) {
        object.insert(key.to_string(), Value::Object(Map::new()));
    }
    object
        .get_mut(key)
        .and_then(Value::as_object_mut)
        .expect("object inserted")
}

fn table_field<'a>(
    table: &'a mut toml::map::Map<String, toml::Value>,
    key: &str,
) -> &'a mut toml::map::Map<String, toml::Value> {
    if !table.get(key).is_some_and(toml::Value::is_table) {
        table.insert(key.to_string(), toml::Value::Table(Default::default()));
    }
    table
        .get_mut(key)
        .and_then(toml::Value::as_table_mut)
        .expect("table inserted")
}

fn read_json_object(path: &Path) -> anyhow::Result<Option<Map<String, Value>>> {
    match std::fs::read_to_string(path) {
        Ok(contents) => Ok(serde_json::from_str::<Value>(&contents)?
            .as_object()
            .cloned()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn write_json_object(path: &Path, value: &Map<String, Value>) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, format!("{}\n", serde_json::to_string_pretty(value)?))?;
    Ok(())
}

fn copy_if_present(source: &Path, target: &Path) -> anyhow::Result<()> {
    if !source.is_file() {
        return Ok(());
    }
    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::copy(source, target)?;
    Ok(())
}

fn link_if_present(source: &Path, target: &Path) {
    if !source.exists() || target.exists() {
        return;
    }
    #[cfg(unix)]
    {
        let _ = std::os::unix::fs::symlink(source, target);
    }
    #[cfg(windows)]
    {
        if source.is_dir() {
            let _ = std::os::windows::fs::symlink_dir(source, target);
        } else {
            let _ = std::os::windows::fs::symlink_file(source, target);
        }
    }
}

pub(super) fn home_dir() -> anyhow::Result<PathBuf> {
    dirs::home_dir().ok_or_else(|| anyhow::anyhow!("Could not resolve the user home directory."))
}

fn env_path(key: &str) -> Option<PathBuf> {
    std::env::var_os(key)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn sh_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

#[cfg(test)]
#[path = "integration_config_tests.rs"]
mod tests;
