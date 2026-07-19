use std::collections::BTreeMap;
use std::path::Path;

use alera_core::runtime::RuntimeAgentStatusHookSettings;

use super::integration_config::prepare_enabled_integrations;

pub fn prepare_launch_environment(
    runtime_dir: &Path,
    session_id: &str,
    workspace_id: &str,
    tab_id: &str,
    settings: &RuntimeAgentStatusHookSettings,
    environment: &mut BTreeMap<String, String>,
) -> anyhow::Result<()> {
    environment.retain(|key, _| !is_managed_hook_key(key));
    if settings.enabled_agents().is_empty() {
        return Ok(());
    }
    let endpoint = runtime_dir.join("agent-hooks").join(if cfg!(windows) {
        "endpoint.cmd"
    } else {
        "endpoint.env"
    });
    environment.insert(
        "ALERA_AGENT_HOOK_ENDPOINT".to_string(),
        endpoint.to_string_lossy().into_owned(),
    );
    environment.insert("ALERA_AGENT_HOOK_VERSION".to_string(), "1".to_string());
    environment.insert(
        "ALERA_TERMINAL_SESSION_ID".to_string(),
        session_id.to_string(),
    );
    environment.insert("ALERA_WORKSPACE_ID".to_string(), workspace_id.to_string());
    environment.insert("ALERA_TAB_ID".to_string(), tab_id.to_string());
    environment.insert(
        "ALERA_RUNTIME_DIR".to_string(),
        runtime_dir.to_string_lossy().into_owned(),
    );
    let _ = prepare_enabled_integrations(runtime_dir, settings, environment);
    Ok(())
}

fn is_managed_hook_key(key: &str) -> bool {
    key == "ALERA_AGENT_HOOK_ENDPOINT"
        || key == "ALERA_AGENT_HOOK_PORT"
        || key == "ALERA_AGENT_HOOK_TOKEN"
        || key == "ALERA_AGENT_HOOK_VERSION"
        || key == "ALERA_TERMINAL_SESSION_ID"
        || key == "ALERA_WORKSPACE_ID"
        || key == "ALERA_TAB_ID"
}
