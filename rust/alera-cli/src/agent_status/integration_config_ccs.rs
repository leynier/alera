use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use super::user_hooks::cleanup_managed_hooks_file;

/// Strips Alera-managed Claude hooks from the CCS account instances.
///
/// CCS sets `CLAUDE_CONFIG_DIR` to `$CCS_DIR/instances/<account>`, and older
/// Alera versions wrote the managed hooks into `settings.local.json` there.
/// Claude never read that file: a config directory contributes `settings.json`
/// and nothing else, so those hooks were dead and no CCS session was ever
/// detected. The live install target is the user's own `settings.json`, which
/// every instance symlinks to (`user_hooks::install_claude_user_hooks`).
///
/// Anything that resolves into `~/.claude` is skipped, so stripping a CCS
/// leftover can never write through the symlink chain and undo that install.
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

/// Alera also wrote managed hooks into CCS `settings.json` at one point. Those
/// are regular files only when the instance diverged from the shared symlink;
/// strip those leftovers too.
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
    use super::super::{read_json_object, write_json_object};
    use super::*;
    use serde_json::{json, Map};

    fn empty_env() -> BTreeMap<String, String> {
        BTreeMap::new()
    }

    #[test]
    fn ccs_removal_strips_dead_instance_local_hooks_and_keeps_other_keys() {
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
    fn ccs_removal_strips_leftover_hooks_from_regular_instance_settings() {
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

        remove_ccs_claude_hooks(home.path(), &empty_env()).unwrap();

        let settings = read_json_object(&instance.join("settings.json"))
            .unwrap()
            .unwrap();
        assert!(settings["hooks"].to_string().contains("echo user"));
        assert!(!settings["hooks"].to_string().contains("alera-claude-hook"));
    }

    /// The instance settings.json is a symlink chain to the user's file, which
    /// is now the live install target. Removal must not follow it.
    #[cfg(unix)]
    #[test]
    fn ccs_removal_never_writes_through_a_symlink_into_user_claude() {
        let home = tempfile::tempdir().unwrap();
        let user_claude = home.path().join(".claude/settings.json");
        write_json_object(
            &user_claude,
            &Map::from_iter([(
                "hooks".to_string(),
                json!({
                    "Stop": [
                        {"hooks": [{"type": "command", "command": "/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh"}]}
                    ]
                }),
            )]),
        )
        .unwrap();
        let shared = home.path().join(".ccs/shared/settings.json");
        std::fs::create_dir_all(shared.parent().unwrap()).unwrap();
        std::os::unix::fs::symlink(&user_claude, &shared).unwrap();
        let instance = home.path().join(".ccs/instances/work");
        std::fs::create_dir_all(&instance).unwrap();
        std::os::unix::fs::symlink(&shared, instance.join("settings.json")).unwrap();

        remove_ccs_claude_hooks(home.path(), &empty_env()).unwrap();

        let settings = read_json_object(&user_claude).unwrap().unwrap();
        assert!(settings["hooks"]
            .to_string()
            .contains("alera-runtime-agent-hook"));
    }

    #[test]
    fn ccs_removal_is_a_no_op_without_instances() {
        let home = tempfile::tempdir().unwrap();
        remove_ccs_claude_hooks(home.path(), &empty_env()).unwrap();
        assert!(!home.path().join(".ccs").exists());
    }
}
