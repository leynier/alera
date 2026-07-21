use std::path::PathBuf;

pub(super) fn install_opencode_plugin() -> anyhow::Result<()> {
    install_plugin(
        env_path("OPENCODE_CONFIG_DIR").unwrap_or(home_dir()?.join(".config/opencode")),
        "plugins/alera-agent-status.js",
        OPENCODE_PLUGIN,
    )
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

fn install_plugin(root: PathBuf, relative: &str, contents: &str) -> anyhow::Result<()> {
    let path = root.join(relative);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, contents)?;
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
