use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use super::user_hooks::cleanup_managed_hooks_file;
use super::{
    install_claude_hooks_into, is_alera_managed_definition, read_json_object, write_json_object,
    CLAUDE_HOOK_EVENTS,
};

/// Writes Alera-managed Claude hooks into each CCS account instance.
///
/// CCS sets `CLAUDE_CONFIG_DIR` to `$CCS_DIR/instances/<account>`, so the
/// runtime overlay never reaches those sessions. Instance `settings.json` is
/// usually a symlink chain to `~/.claude/settings.json`, which Grok scans and
/// leftover cleanup must keep free of Alera commands. `settings.local.json` is
/// instance-local, not in CCS `SHARED_ITEMS`, and Claude loads it from the
/// config dir.
pub(super) fn install_ccs_claude_hooks(
    script: &Path,
    home: &Path,
    environment: &BTreeMap<String, String>,
) -> anyhow::Result<()> {
    let mut errors = Vec::new();
    let user_claude = home.join(".claude");
    for path in ccs_claude_local_settings_paths(home, environment) {
        if resolves_into(&path, &user_claude) {
            continue;
        }
        if let Err(error) = install_hooks_at(&path, script) {
            errors.push(format!("{}: {error}", path.display()));
        }
    }
    for path in ccs_claude_leftover_settings_paths(home, environment) {
        if resolves_into(&path, &user_claude) {
            continue;
        }
        if let Err(error) = cleanup_managed_hooks_file(&path) {
            errors.push(format!("{}: {error}", path.display()));
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(errors.join("; ")))
    }
}

pub(super) fn remove_ccs_claude_hooks(
    home: &Path,
    environment: &BTreeMap<String, String>,
) -> anyhow::Result<()> {
    let mut errors = Vec::new();
    let user_claude = home.join(".claude");
    for path in ccs_claude_local_settings_paths(home, environment)
        .into_iter()
        .chain(ccs_claude_leftover_settings_paths(home, environment))
    {
        if resolves_into(&path, &user_claude) {
            continue;
        }
        if !path.exists() {
            continue;
        }
        if let Err(error) = cleanup_managed_hooks_file(&path) {
            errors.push(format!("{}: {error}", path.display()));
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(errors.join("; ")))
    }
}

fn install_hooks_at(path: &Path, script: &Path) -> anyhow::Result<()> {
    let mut settings = read_json_object(path)?.unwrap_or_default();
    if claude_managed_hooks_complete(&settings) {
        return Ok(());
    }
    install_claude_hooks_into(&mut settings, script);
    write_json_object(path, &settings)
}

fn claude_managed_hooks_complete(settings: &serde_json::Map<String, serde_json::Value>) -> bool {
    let Some(hooks) = settings.get("hooks").and_then(serde_json::Value::as_object) else {
        return false;
    };
    CLAUDE_HOOK_EVENTS.iter().all(|(event, _)| {
        hooks
            .get(*event)
            .and_then(serde_json::Value::as_array)
            .is_some_and(|definitions| definitions.iter().any(is_alera_managed_definition))
    })
}

fn ccs_root(home: &Path, environment: &BTreeMap<String, String>) -> PathBuf {
    environment
        .get("CCS_DIR")
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".ccs"))
}

fn ccs_instance_dirs(home: &Path, environment: &BTreeMap<String, String>) -> Vec<PathBuf> {
    let instances = ccs_root(home, environment).join("instances");
    let Ok(entries) = std::fs::read_dir(&instances) else {
        return Vec::new();
    };
    let mut dirs = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name();
        if name.to_string_lossy().starts_with('.') {
            continue;
        }
        let path = entry.path();
        if path.is_dir() {
            dirs.push(path);
        }
    }
    dirs.sort();
    dirs
}

fn ccs_claude_local_settings_paths(
    home: &Path,
    environment: &BTreeMap<String, String>,
) -> Vec<PathBuf> {
    ccs_instance_dirs(home, environment)
        .into_iter()
        .map(|dir| dir.join("settings.local.json"))
        .collect()
}

/// Older Alera installs wrote managed Claude hooks into CCS `settings.json`.
/// Those files are not the live install target; strip leftovers so they cannot
/// double-POST beside `settings.local.json`.
fn ccs_claude_leftover_settings_paths(
    home: &Path,
    environment: &BTreeMap<String, String>,
) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    let shared = ccs_root(home, environment).join("shared/settings.json");
    if is_regular_file(&shared) {
        paths.push(shared);
    }
    for dir in ccs_instance_dirs(home, environment) {
        let settings = dir.join("settings.json");
        if is_regular_file(&settings) {
            paths.push(settings);
        }
    }
    paths
}

fn is_regular_file(path: &Path) -> bool {
    std::fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_file())
        .unwrap_or(false)
}

fn resolves_into(path: &Path, dir: &Path) -> bool {
    let resolved = canonicalize_existing(path);
    let dir = canonicalize_existing(dir);
    resolved == dir || resolved.starts_with(&dir)
}

fn canonicalize_existing(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| path.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::super::user_hooks;
    use super::super::{read_json_object, write_json_object, CLAUDE_HOOK_EVENTS};
    use super::*;
    use serde_json::{json, Map, Value};

    fn empty_env() -> BTreeMap<String, String> {
        BTreeMap::new()
    }

    fn hook_script() -> PathBuf {
        PathBuf::from("/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh")
    }

    #[cfg(unix)]
    #[test]
    fn ccs_install_writes_instance_local_settings_and_skips_user_claude() {
        let home = tempfile::tempdir().unwrap();
        let user_claude = home.path().join(".claude/settings.json");
        write_json_object(
            &user_claude,
            &Map::from_iter([(
                "hooks".to_string(),
                json!({
                    "Stop": [
                        {"hooks": [{"type": "command", "command": "/home/user/.orca/agent-hooks/claude-hook.sh"}]}
                    ]
                }),
            )]),
        )
        .unwrap();
        let shared = home.path().join(".ccs/shared/settings.json");
        std::fs::create_dir_all(shared.parent().unwrap()).unwrap();
        std::os::unix::fs::symlink(&user_claude, &shared).unwrap();
        let instance = home.path().join(".ccs/instances/profile-a");
        std::fs::create_dir_all(&instance).unwrap();
        std::os::unix::fs::symlink(&shared, instance.join("settings.json")).unwrap();
        let credentials = instance.join(".credentials.json");
        std::fs::write(&credentials, "{\"secret\":\"keep\"}\n").unwrap();

        install_ccs_claude_hooks(&hook_script(), home.path(), &empty_env()).unwrap();

        let user_settings = read_json_object(&user_claude).unwrap().unwrap();
        assert!(user_settings["hooks"]
            .to_string()
            .contains(".orca/agent-hooks"));
        assert!(!user_settings["hooks"]
            .to_string()
            .contains("alera-runtime-agent-hook"));
        assert!(std::fs::symlink_metadata(instance.join("settings.json"))
            .unwrap()
            .file_type()
            .is_symlink());
        let local = read_json_object(&instance.join("settings.local.json"))
            .unwrap()
            .unwrap();
        assert!(local["hooks"]
            .to_string()
            .contains("alera-runtime-agent-hook"));
        assert!(local["hooks"].as_object().unwrap().contains_key("Stop"));
        assert!(local["hooks"]
            .as_object()
            .unwrap()
            .contains_key("UserPromptSubmit"));
        assert_eq!(
            std::fs::read_to_string(&credentials).unwrap(),
            "{\"secret\":\"keep\"}\n"
        );
    }

    #[test]
    fn ccs_install_does_not_require_instance_settings_json() {
        let home = tempfile::tempdir().unwrap();
        let instance = home.path().join(".ccs/instances/work");
        std::fs::create_dir_all(&instance).unwrap();

        install_ccs_claude_hooks(&hook_script(), home.path(), &empty_env()).unwrap();

        let local = read_json_object(&instance.join("settings.local.json"))
            .unwrap()
            .unwrap();
        assert!(local["hooks"]
            .to_string()
            .contains("alera-runtime-agent-hook"));
        assert!(!instance.join("settings.json").exists());
    }

    #[test]
    fn ccs_disable_strips_instance_local_hooks_and_keeps_other_keys() {
        let home = tempfile::tempdir().unwrap();
        let instance = home.path().join(".ccs/instances/work");
        std::fs::create_dir_all(&instance).unwrap();
        write_json_object(
            &instance.join("settings.local.json"),
            &Map::from_iter([
                ("model".to_string(), json!("opus")),
                (
                    "hooks".to_string(),
                    json!({
                        "Stop": [
                            {"hooks": [{"type": "command", "command": "echo user"}]},
                            {"hooks": [{"type": "command", "command": "/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh"}]}
                        ]
                    }),
                ),
            ]),
        )
        .unwrap();

        remove_ccs_claude_hooks(home.path(), &empty_env()).unwrap();

        let local = read_json_object(&instance.join("settings.local.json"))
            .unwrap()
            .unwrap();
        assert_eq!(local["model"], json!("opus"));
        assert!(local["hooks"].to_string().contains("echo user"));
        assert!(!local["hooks"]
            .to_string()
            .contains("alera-runtime-agent-hook"));
    }

    #[test]
    fn ccs_install_strips_leftover_hooks_from_regular_instance_settings() {
        let home = tempfile::tempdir().unwrap();
        let instance = home.path().join(".ccs/instances/work");
        std::fs::create_dir_all(&instance).unwrap();
        write_json_object(
            &instance.join("settings.json"),
            &Map::from_iter([(
                "hooks".to_string(),
                json!({
                    "Stop": [
                        {"hooks": [{"type": "command", "command": "echo user"}]},
                        {"hooks": [{"type": "command", "command": "/home/user/.alera/agent-hooks/alera-claude-hook.sh"}]}
                    ]
                }),
            )]),
        )
        .unwrap();

        install_ccs_claude_hooks(&hook_script(), home.path(), &empty_env()).unwrap();

        let settings = read_json_object(&instance.join("settings.json"))
            .unwrap()
            .unwrap();
        assert!(settings["hooks"].to_string().contains("echo user"));
        assert!(!settings["hooks"].to_string().contains("alera-claude-hook"));
        let local = read_json_object(&instance.join("settings.local.json"))
            .unwrap()
            .unwrap();
        assert!(local["hooks"]
            .to_string()
            .contains("alera-runtime-agent-hook"));
    }

    #[test]
    #[test]
    fn ccs_install_keeps_existing_complete_managed_hooks() {
        let home = tempfile::tempdir().unwrap();
        let instance = home.path().join(".ccs/instances/work");
        std::fs::create_dir_all(&instance).unwrap();
        let mut hooks = Map::new();
        for (event, matcher) in CLAUDE_HOOK_EVENTS {
            let mut definition = Map::new();
            if let Some(matcher) = matcher {
                definition.insert("matcher".to_string(), json!(matcher));
            }
            definition.insert(
                "hooks".to_string(),
                json!([{
                    "type": "command",
                    "command": "/home/user/.alera/agent-hooks/alera-claude-hook.sh"
                }]),
            );
            hooks.insert((*event).to_string(), json!([definition]));
        }
        write_json_object(
            &instance.join("settings.local.json"),
            &Map::from_iter([("hooks".to_string(), Value::Object(hooks))]),
        )
        .unwrap();

        install_ccs_claude_hooks(&hook_script(), home.path(), &empty_env()).unwrap();

        let local = read_json_object(&instance.join("settings.local.json"))
            .unwrap()
            .unwrap();
        assert!(local["hooks"].to_string().contains("alera-claude-hook"));
        assert!(!local["hooks"]
            .to_string()
            .contains("alera-runtime-agent-hook"));
    }

    #[test]
    fn leftover_cleanup_still_strips_user_claude_after_ccs_local_install() {
        let home = tempfile::tempdir().unwrap();
        let user_claude = home.path().join(".claude/settings.json");
        write_json_object(
            &user_claude,
            &Map::from_iter([(
                "hooks".to_string(),
                json!({
                    "Stop": [
                        {"hooks": [{"type": "command", "command": "/home/user/.alera/agent-hooks/alera-claude-hook.sh"}]}
                    ]
                }),
            )]),
        )
        .unwrap();
        let instance = home.path().join(".ccs/instances/work");
        std::fs::create_dir_all(&instance).unwrap();
        install_ccs_claude_hooks(&hook_script(), home.path(), &empty_env()).unwrap();

        user_hooks::cleanup_claude_user_hooks(home.path()).unwrap();

        let user_config = read_json_object(&user_claude).unwrap().unwrap();
        assert!(!user_config.contains_key("hooks"));
        let local = read_json_object(&instance.join("settings.local.json"))
            .unwrap()
            .unwrap();
        assert!(local["hooks"]
            .to_string()
            .contains("alera-runtime-agent-hook"));
    }
}
