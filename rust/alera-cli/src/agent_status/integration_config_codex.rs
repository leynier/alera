use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use super::codex_hook_trust::{codex_trusted_hash, remap_codex_source_hook_trust};
use super::{
    clean_managed_definitions, home_dir, link_if_present, managed_command, object_field,
    read_json_object, write_json_object,
};

/// Builds the isolated Codex home the launch points `CODEX_HOME` at.
///
/// Codex trusts a hook by the path it was declared at, so the definitions are
/// copied into the runtime home and the existing trust records are remapped
/// rather than re-approved.
pub(super) fn prepare_codex(runtime_dir: &Path, script: &Path) -> anyhow::Result<PathBuf> {
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
