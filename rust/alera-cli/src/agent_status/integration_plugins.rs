use std::path::{Path, PathBuf};

const MANAGED_FILE_MARKER: &str = "ALERA_AGENT_STATUS_MANAGED_FILE";

/// One file serves OpenCode v1 and OpenCode 2. Older Alera versions also wrote
/// a separate OpenCode 2 plugin beside it, which v2 would now load as a
/// second plugin with the same id, so installing removes it.
pub(super) fn install_opencode_plugin() -> anyhow::Result<()> {
    install_opencode_plugin_into(opencode_config_dir()?)
}

fn install_opencode_plugin_into(root: PathBuf) -> anyhow::Result<()> {
    remove_plugin(root.clone(), LEGACY_OPENCODE2_PLUGIN)?;
    install_plugin(root, OPENCODE_PLUGIN_PATH, OPENCODE_PLUGIN)
}

pub(super) fn install_pi_plugin() -> anyhow::Result<()> {
    install_plugin(
        env_path("PI_CODING_AGENT_DIR").unwrap_or(home_dir()?.join(".pi/agent")),
        "extensions/alera-agent-status.ts",
        PI_PLUGIN,
    )
}

pub(super) fn install_amp_plugin() -> anyhow::Result<()> {
    install_plugin(
        env_path("AMP_CONFIG_DIR").unwrap_or(home_dir()?.join(".config/amp")),
        "plugins/alera-agent-status.ts",
        AMP_PLUGIN,
    )
}

pub(super) fn remove_opencode_plugin() -> anyhow::Result<()> {
    let root = opencode_config_dir()?;
    remove_plugin(root.clone(), LEGACY_OPENCODE2_PLUGIN)?;
    remove_plugin(root, OPENCODE_PLUGIN_PATH)
}

fn opencode_config_dir() -> anyhow::Result<PathBuf> {
    Ok(env_path("OPENCODE_CONFIG_DIR").unwrap_or(home_dir()?.join(".config/opencode")))
}

const OPENCODE_PLUGIN_PATH: &str = "plugins/alera-agent-status.js";
const LEGACY_OPENCODE2_PLUGIN: &str = "plugins/alera-agent-status-v2.js";

pub(super) fn remove_pi_plugin() -> anyhow::Result<()> {
    remove_plugin(
        env_path("PI_CODING_AGENT_DIR").unwrap_or(home_dir()?.join(".pi/agent")),
        "extensions/alera-agent-status.ts",
    )
}

pub(super) fn remove_amp_plugin() -> anyhow::Result<()> {
    remove_plugin(
        env_path("AMP_CONFIG_DIR").unwrap_or(home_dir()?.join(".config/amp")),
        "plugins/alera-agent-status.ts",
    )
}

fn install_plugin(root: PathBuf, relative: &str, contents: &str) -> anyhow::Result<()> {
    let path = root.join(relative);
    if path.is_file() {
        if let Ok(existing) = std::fs::read_to_string(&path) {
            if existing == contents {
                return Ok(());
            }
        }
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, contents)?;
    Ok(())
}

fn remove_plugin(root: PathBuf, relative: &str) -> anyhow::Result<()> {
    remove_managed_plugin_file(&root.join(relative))
}

fn remove_managed_plugin_file(path: &Path) -> anyhow::Result<()> {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    if !contents.contains(MANAGED_FILE_MARKER) {
        return Ok(());
    }
    std::fs::remove_file(path)?;
    Ok(())
}

fn home_dir() -> anyhow::Result<PathBuf> {
    dirs::home_dir().ok_or_else(|| anyhow::anyhow!("Could not resolve the user home directory."))
}

fn env_path(key: &str) -> Option<PathBuf> {
    std::env::var_os(key)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

const OPENCODE_PLUGIN: &str = include_str!("integration_plugins/opencode.js");
const PI_PLUGIN: &str = include_str!("integration_plugins/pi.ts");
const AMP_PLUGIN: &str = include_str!("integration_plugins/amp.ts");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remove_deletes_alera_marked_plugin_files_only() {
        let root = tempfile::tempdir().unwrap();
        let managed = root.path().join("plugins/alera-agent-status.js");
        let foreign = root.path().join("plugins/user-plugin.js");
        std::fs::create_dir_all(managed.parent().unwrap()).unwrap();
        std::fs::write(&managed, "// ALERA_AGENT_STATUS_MANAGED_FILE\nexport {}\n").unwrap();
        std::fs::write(&foreign, "export {}\n").unwrap();

        remove_managed_plugin_file(&managed).unwrap();
        remove_managed_plugin_file(&foreign).unwrap();

        assert!(!managed.exists());
        assert!(foreign.exists());
    }

    #[test]
    fn remove_is_a_no_op_when_the_plugin_is_missing() {
        let root = tempfile::tempdir().unwrap();
        remove_managed_plugin_file(&root.path().join("missing.js")).unwrap();
    }

    #[test]
    fn installing_opencode_replaces_the_separate_opencode2_plugin() {
        let root = tempfile::tempdir().unwrap();
        let plugins = root.path().join("plugins");
        std::fs::create_dir_all(&plugins).unwrap();
        let legacy = plugins.join("alera-agent-status-v2.js");
        std::fs::write(
            &legacy,
            "// ALERA_AGENT_STATUS_MANAGED_FILE\nexport default {}\n",
        )
        .unwrap();
        let foreign = plugins.join("user-plugin.js");
        std::fs::write(&foreign, "export default {}\n").unwrap();

        install_opencode_plugin_into(root.path().to_path_buf()).unwrap();

        assert!(!legacy.exists());
        assert!(foreign.exists());
        let installed = std::fs::read_to_string(plugins.join("alera-agent-status.js")).unwrap();
        assert_eq!(installed, OPENCODE_PLUGIN);
        // Both loaders' entry points and the single hook route.
        assert!(installed.contains("server,\n  setup,"));
        assert!(installed.contains("/hook/opencode`"));
        assert!(!installed.contains("/hook/opencode2"));
    }
}
