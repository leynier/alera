//! Claude Code settings the adapter reads outside skill discovery, from the
//! files the CLI layers, later files winning.

use crate::skills::{
    managed_settings_path, parse_lenient_json, read_text, settings_paths, SkillEnvironment,
};
use claude_agent_sdk::ClaudeAgentOptions;
use std::collections::BTreeMap;

/// The `env.ANTHROPIC_BASE_URL` Claude Code's user and managed settings set
/// for a CLI spawned with [env], T3 Code's `readClaudeSettingsBaseUrl`. The
/// managed file wins over the user one; a file that is unreadable or
/// malformed, or that sets no string, is skipped. Settings apply over the
/// process environment, so a caller falls back to [env]'s own value only
/// when this is `None`.
pub fn claude_settings_base_url(env: &BTreeMap<String, String>) -> Option<String> {
    let options = ClaudeAgentOptions {
        env: env.clone(),
        ..Default::default()
    };
    let environment = SkillEnvironment::new(&options, None);
    let paths = match environment.config_dir() {
        Some(config_dir) => settings_paths(&config_dir, &environment),
        None => managed_settings_path(&environment).into_iter().collect(),
    };
    // Later files win, so the first value from the end is the one in force.
    paths.iter().rev().find_map(|path| {
        let settings = parse_lenient_json(&read_text(path)?)?;
        settings
            .get("env")?
            .get("ANTHROPIC_BASE_URL")?
            .as_str()
            .map(str::to_owned)
    })
}
