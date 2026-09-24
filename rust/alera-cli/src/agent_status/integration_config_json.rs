use std::path::{Path, PathBuf};

use serde_json::{json, Map, Value};

use super::{
    clean_managed_definitions, env_path, home_dir, managed_command, managed_hook_definition,
    object_field, read_json_object, write_json_object,
};

pub(super) fn install_copilot(script: &Path) -> anyhow::Result<()> {
    let path = copilot_hooks_path()?;
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

pub(super) fn install_grok(script: &Path) -> anyhow::Result<()> {
    let path = grok_hooks_path()?;
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

pub(super) fn install_agy(script: &Path) -> anyhow::Result<()> {
    let path = home_dir()?.join(".gemini/config/hooks.json");
    let mut config = read_json_object(&path)?.unwrap_or_default();
    apply_agy_bundle(&mut config, script);
    write_json_object(&path, &config)
}

pub(super) fn cleanup_agy(home: &Path) -> anyhow::Result<()> {
    let path = home.join(".gemini/config/hooks.json");
    let Some(mut config) = read_json_object(&path)? else {
        return Ok(());
    };
    let Some(bundle) = config.get("alera-status").cloned() else {
        return Ok(());
    };
    let Some(mut bundle) = bundle.as_object().cloned() else {
        return Ok(());
    };
    let mut changed = false;
    for event in ["PreInvocation", "PostInvocation", "Stop", "PostToolUse"] {
        let Some(value) = bundle.remove(event) else {
            continue;
        };
        let had = value.as_array().map(Vec::len).unwrap_or(0);
        let cleaned = clean_managed_definitions(Some(value));
        if cleaned.len() != had {
            changed = true;
        }
        if !cleaned.is_empty() {
            bundle.insert(event.to_string(), Value::Array(cleaned));
        }
    }
    if bundle.is_empty() {
        config.remove("alera-status");
        changed = true;
    } else if changed {
        config.insert("alera-status".to_string(), Value::Object(bundle));
    }
    if !changed {
        return Ok(());
    }
    write_json_object(&path, &config)
}

pub(super) fn cleanup_dedicated_hooks_file(path: &Path) -> anyhow::Result<()> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

pub(super) fn copilot_hooks_path() -> anyhow::Result<PathBuf> {
    Ok(env_path("COPILOT_HOME")
        .unwrap_or(home_dir()?.join(".copilot"))
        .join("hooks/alera.json"))
}

pub(super) fn grok_hooks_path() -> anyhow::Result<PathBuf> {
    Ok(env_path("GROK_HOME")
        .unwrap_or(home_dir()?.join(".grok"))
        .join("hooks/alera-status.json"))
}

// Antigravity keeps each hook set under its own top-level key and uses two
// schemas inside it: lifecycle events take a flat `{ type, command }` handler,
// tool events a matcher wrapping `hooks`. `PreToolUse` is deliberately absent -
// Antigravity requires a permission `decision` from it, which an observational
// hook cannot give without taking over the user's tool policy.
pub(super) fn apply_agy_bundle(config: &mut Map<String, Value>, script: &Path) {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agy_cleanup_removes_alera_handlers_and_keeps_user_ones() {
        let home = tempfile::tempdir().unwrap();
        let path = home.path().join(".gemini/config/hooks.json");
        write_json_object(
            &path,
            &Map::from_iter([
                (
                    "alera-status".to_string(),
                    json!({
                        "Stop": [
                            { "type": "command", "command": "echo user" },
                            { "type": "command", "command": "/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh" }
                        ]
                    }),
                ),
                (
                    "other-bundle".to_string(),
                    json!({ "Stop": [{ "type": "command", "command": "echo other" }] }),
                ),
            ]),
        )
        .unwrap();

        cleanup_agy(home.path()).unwrap();

        let config = read_json_object(&path).unwrap().unwrap();
        assert_eq!(
            config["alera-status"]["Stop"],
            json!([{ "type": "command", "command": "echo user" }])
        );
        assert_eq!(
            config["other-bundle"]["Stop"],
            json!([{ "type": "command", "command": "echo other" }])
        );
    }

    #[test]
    fn dedicated_hook_file_cleanup_deletes_only_the_alera_file() {
        let root = tempfile::tempdir().unwrap();
        let alera = root.path().join("hooks/alera.json");
        let other = root.path().join("hooks/user.json");
        std::fs::create_dir_all(alera.parent().unwrap()).unwrap();
        std::fs::write(&alera, "{}\n").unwrap();
        std::fs::write(&other, "{\"keep\":true}\n").unwrap();

        cleanup_dedicated_hooks_file(&alera).unwrap();

        assert!(!alera.exists());
        assert!(other.exists());
    }
}
