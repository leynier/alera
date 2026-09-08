use std::path::Path;

use serde_json::{json, Value};

use super::codex_hook_trust::{remove_alera_codex_hook_trust, upsert_codex_hook_trust};
use super::{
    clean_managed_definitions, managed_command, object_field, read_json_object, write_json_object,
};

const CODEX_HOOK_EVENTS: &[(&str, &str)] = &[
    ("SessionStart", "session_start"),
    ("UserPromptSubmit", "user_prompt_submit"),
    ("PreToolUse", "pre_tool_use"),
    ("PermissionRequest", "permission_request"),
    ("PostToolUse", "post_tool_use"),
    ("Stop", "stop"),
];

/// Writes Alera Codex hooks into the Codex home (`~/.codex` or `$CODEX_HOME`).
///
/// Codex trusts a hook by the path it was declared at plus a hash of the
/// command, so install also upserts Alera-owned trust records in
/// `config.toml`. User hook definitions and unrelated trust keys stay.
pub(super) fn install_codex(root: &Path, script: &Path) -> anyhow::Result<()> {
    std::fs::create_dir_all(root)?;
    let hooks_path = root.join("hooks.json");
    let toml_path = root.join("config.toml");
    let (mut toml_value, original_toml) = read_codex_toml(&toml_path)?;
    let mut config = read_json_object(&hooks_path)?.unwrap_or_default();
    let original = config.clone();
    let hooks = object_field(&mut config, "hooks");
    let mut trust = Vec::new();
    for (event, label) in CODEX_HOOK_EVENTS {
        let command = managed_command(script, "codex", event);
        let definitions = clean_managed_definitions(hooks.remove(*event));
        let index = definitions.len();
        let mut next = definitions;
        next.push(json!({
            "hooks": [{ "type": "command", "command": command.clone() }],
        }));
        hooks.insert((*event).to_string(), Value::Array(next));
        trust.push((*label, index, command));
    }
    if config != original {
        write_json_object(&hooks_path, &config)?;
    }

    let canonical_hooks_path = std::fs::canonicalize(&hooks_path).unwrap_or(hooks_path.clone());
    let root_table = toml_value
        .as_table_mut()
        .ok_or_else(|| anyhow::anyhow!("Codex config.toml root is not a table"))?;
    table_field(root_table, "features").insert("hooks".to_string(), toml::Value::Boolean(true));
    let state = table_field(table_field(root_table, "hooks"), "state");
    remove_alera_codex_hook_trust(
        state,
        &canonical_hooks_path,
        remaining_event_counts(&hooks_path)?,
    );
    upsert_codex_hook_trust(state, &canonical_hooks_path, &trust);
    write_toml_if_changed(&toml_path, &toml_value, &original_toml)
}

/// Removes Alera-managed Codex hook definitions and Alera trust records.
/// User entries in `hooks.json` and unrelated `config.toml` keys stay.
pub(super) fn cleanup_codex(root: &Path) -> anyhow::Result<()> {
    let hooks_path = root.join("hooks.json");
    super::user_hooks::cleanup_managed_hooks_file(&hooks_path)?;
    cleanup_codex_config_trust(root, &hooks_path)
}

fn cleanup_codex_config_trust(root: &Path, hooks_path: &Path) -> anyhow::Result<()> {
    let toml_path = root.join("config.toml");
    let (mut toml_value, original) = match read_codex_toml(&toml_path) {
        Ok(value) => value,
        Err(_) if !toml_path.exists() => return Ok(()),
        Err(error) => return Err(error),
    };
    let Some(root_table) = toml_value.as_table_mut() else {
        return Ok(());
    };
    let Some(hooks) = root_table
        .get_mut("hooks")
        .and_then(toml::Value::as_table_mut)
    else {
        return Ok(());
    };
    let Some(state) = hooks.get_mut("state").and_then(toml::Value::as_table_mut) else {
        return Ok(());
    };
    remove_alera_codex_hook_trust(state, hooks_path, remaining_event_counts(hooks_path)?);
    write_toml_if_changed(&toml_path, &toml_value, &original)
}

fn remaining_event_counts(hooks_path: &Path) -> anyhow::Result<Vec<(String, usize)>> {
    let Some(config) = read_json_object(hooks_path)? else {
        return Ok(Vec::new());
    };
    let Some(hooks) = config.get("hooks").and_then(Value::as_object) else {
        return Ok(Vec::new());
    };
    Ok(CODEX_HOOK_EVENTS
        .iter()
        .map(|(event, label)| {
            let count = hooks
                .get(*event)
                .and_then(Value::as_array)
                .map(Vec::len)
                .unwrap_or(0);
            ((*label).to_string(), count)
        })
        .collect())
}

fn read_codex_toml(path: &Path) -> anyhow::Result<(toml::Value, String)> {
    let source = match std::fs::read_to_string(path) {
        Ok(source) => source,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(error) => return Err(error.into()),
    };
    let value = if source.trim().is_empty() {
        toml::Value::Table(Default::default())
    } else {
        toml::from_str::<toml::Value>(&source)
            .map_err(|error| anyhow::anyhow!("Could not parse {}: {error}", path.display()))?
    };
    Ok((value, source))
}

fn write_toml_if_changed(path: &Path, value: &toml::Value, original: &str) -> anyhow::Result<()> {
    let serialized = toml::to_string(value)?;
    if serialized == original {
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, serialized)?;
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

#[cfg(test)]
#[path = "integration_config_codex_tests.rs"]
mod tests;
