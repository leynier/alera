//! Codex thread config defaults sent with every `thread/start`,
//! `thread/resume` and `thread/fork`, as T3 Code's `CODEX_THREAD_CONFIG`.
//!
//! - Codex 0.152 made the `update_plan` checklist tool opt-in, and without it
//!   a Codex turn never reports plan progress.
//! - Codex waits only 1 s for MCP servers before the first model request and
//!   leaves out any server still starting, so a cold `npx` or `uvx` server
//!   would be missing from the first turn. A hung server now delays only
//!   that first request, by at most 10 s.
//!
//! A caller value for either setting always wins.

use alera_provider_protocol::ProviderError;
use serde_json::{Map, Value};

const UPDATE_PLAN_KEY: &str = "tools.update_plan.enabled";
const MCP_STARTUP_GRACE_KEY: &str = "mcp_optional_startup_grace_ms";
const MCP_STARTUP_GRACE_MS: u64 = 10_000;

pub(crate) fn apply_defaults(params: &mut Map<String, Value>) -> Result<(), ProviderError> {
    let config = params
        .entry("config")
        .or_insert_with(|| Value::Object(Map::new()))
        .as_object_mut()
        .ok_or_else(|| {
            ProviderError::Validation("Codex thread config must be a JSON object".into())
        })?;
    if !sets_update_plan(config) {
        match config.get_mut("tools").and_then(Value::as_object_mut) {
            // A nested `tools` table may be applied after a dotted key and
            // replace it, so the setting joins that table instead.
            Some(tools) => {
                tools.insert("update_plan".into(), serde_json::json!({ "enabled": true }));
            }
            None => {
                config.insert(UPDATE_PLAN_KEY.into(), Value::Bool(true));
            }
        }
    }
    config
        .entry(MCP_STARTUP_GRACE_KEY)
        .or_insert_with(|| Value::Number(MCP_STARTUP_GRACE_MS.into()));
    Ok(())
}

/// Whether the caller config already says anything about `update_plan`,
/// dotted or nested.
fn sets_update_plan(config: &Map<String, Value>) -> bool {
    config
        .keys()
        .any(|key| key == "tools.update_plan" || key.starts_with("tools.update_plan."))
        || config
            .get("tools")
            .and_then(Value::as_object)
            .is_some_and(|tools| tools.contains_key("update_plan"))
}
