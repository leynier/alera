use crate::error::{ClaudeSdkError, Result};
use crate::types::{ClaudeAgentOptions, SystemPrompt, ThinkingConfig, Tools};
use alera_agent_transport::{JsonLineProcess, JsonTransport, ProcessConfig, TransportError};
use serde_json::{json, Value};
use std::ffi::OsString;
use std::path::PathBuf;

pub(crate) async fn spawn_cli(options: &ClaudeAgentOptions) -> Result<Box<dyn JsonTransport>> {
    let config = build_process_config(options);
    let process = match JsonLineProcess::spawn(config).await {
        Ok(process) => process,
        Err(TransportError::Spawn { executable, source })
            if source.kind() == std::io::ErrorKind::NotFound =>
        {
            return Err(ClaudeSdkError::CliNotFound(
                executable.display().to_string(),
            ));
        }
        Err(error) => return Err(ClaudeSdkError::transport(error.to_string())),
    };
    Ok(Box::new(process))
}

pub(crate) fn build_process_config(options: &ClaudeAgentOptions) -> ProcessConfig {
    let mut config = ProcessConfig {
        executable: options
            .cli_path
            .clone()
            .unwrap_or_else(|| PathBuf::from("claude")),
        args: build_cli_arguments(options),
        cwd: options.cwd.clone(),
        max_frame_bytes: options.max_buffer_size,
        shutdown_timeout: options.shutdown_timeout,
        ..ProcessConfig::default()
    };
    for (key, value) in &options.env {
        config
            .env
            .insert(OsString::from(key), OsString::from(value));
    }
    config
        .env
        .entry("CLAUDE_CODE_ENTRYPOINT".into())
        .or_insert_with(|| "sdk-rust".into());
    config
        .env
        .entry("CLAUDE_AGENT_SDK_VERSION".into())
        .or_insert_with(|| env!("CARGO_PKG_VERSION").into());
    config
        .env
        .entry("CLAUDE_CODE_SDK_READS_SESSION_STATE".into())
        .or_insert_with(|| "1".into());
    if options.enable_file_checkpointing {
        config.env.insert(
            "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING".into(),
            "true".into(),
        );
    }
    if let Some(cwd) = &options.cwd {
        config.env.insert("PWD".into(), cwd.as_os_str().to_owned());
    }
    config
}

pub(crate) fn build_cli_arguments(options: &ClaudeAgentOptions) -> Vec<OsString> {
    let mut args = vec!["--output-format", "stream-json", "--verbose"]
        .into_iter()
        .map(OsString::from)
        .collect::<Vec<_>>();
    match &options.system_prompt {
        None => push_pair(&mut args, "--system-prompt", ""),
        Some(SystemPrompt::Text(prompt)) => push_pair(&mut args, "--system-prompt", prompt),
        Some(SystemPrompt::File { path }) => push_pair(&mut args, "--system-prompt-file", path),
        Some(SystemPrompt::Custom { prompt, .. }) => {
            push_pair(&mut args, "--system-prompt", prompt)
        }
        Some(SystemPrompt::Preset {
            append: Some(append),
            ..
        }) => push_pair(&mut args, "--append-system-prompt", append),
        Some(SystemPrompt::Preset { append: None, .. }) => {}
    }
    if let Some(tools) = &options.tools {
        match tools {
            Tools::Names(names) => push_pair(&mut args, "--tools", &names.join(",")),
            Tools::Preset { .. } => push_pair(&mut args, "--tools", "default"),
        }
    }
    let mut allowed_tools = options.allowed_tools.clone();
    if let Some(skills) = &options.skills {
        for skill in skills {
            let rule = format!("Skill({skill})");
            if !allowed_tools.iter().any(|item| item == &rule) {
                allowed_tools.push(rule);
            }
        }
    }
    if !allowed_tools.is_empty() {
        push_pair(&mut args, "--allowedTools", &allowed_tools.join(","));
    }
    if let Some(turns) = options.max_turns {
        push_pair(&mut args, "--max-turns", &turns.to_string());
    }
    if let Some(budget) = options.max_budget_usd {
        push_pair(&mut args, "--max-budget-usd", &budget.to_string());
    }
    if !options.disallowed_tools.is_empty() {
        push_pair(
            &mut args,
            "--disallowedTools",
            &options.disallowed_tools.join(","),
        );
    }
    if let Some(budget) = options.task_budget {
        push_pair(&mut args, "--task-budget", &budget.to_string());
    }
    if let Some(model) = &options.model {
        push_pair(&mut args, "--model", model);
    }
    if let Some(model) = &options.fallback_model {
        push_pair(&mut args, "--fallback-model", model);
    }
    if !options.betas.is_empty() {
        push_pair(&mut args, "--betas", &options.betas.join(","));
    }
    if let Some(tool) = &options.permission_prompt_tool_name {
        push_pair(&mut args, "--permission-prompt-tool", tool);
    }
    if let Some(mode) = &options.permission_mode {
        push_pair(&mut args, "--permission-mode", mode);
    }
    if options.continue_conversation {
        args.push("--continue".into());
    }
    if let Some(resume) = &options.resume {
        push_equals(&mut args, "--resume", resume);
    }
    if let Some(session_id) = &options.session_id {
        push_equals(&mut args, "--session-id", session_id);
    }
    if let Some(settings) = &options.settings {
        push_pair(&mut args, "--settings", settings);
    }
    for directory in &options.add_dirs {
        push_pair(&mut args, "--add-dir", &directory.to_string_lossy());
    }
    if !options.mcp_servers.is_empty() {
        let servers = options
            .mcp_servers
            .iter()
            .map(|(name, value)| {
                let value = if value.get("type").and_then(Value::as_str) == Some("sdk") {
                    let mut value = value.clone();
                    if let Value::Object(object) = &mut value {
                        object.remove("instance");
                    }
                    value
                } else {
                    value.clone()
                };
                (name.clone(), value)
            })
            .collect::<serde_json::Map<_, _>>();
        let config = json!({ "mcpServers": servers });
        push_pair(&mut args, "--mcp-config", &config.to_string());
    }
    if options.include_partial_messages {
        args.push("--include-partial-messages".into());
    }
    if options.include_hook_events {
        args.push("--include-hook-events".into());
    }
    if options.strict_mcp_config {
        args.push("--strict-mcp-config".into());
    }
    if options.fork_session {
        args.push("--fork-session".into());
    }
    if let Some(value) = &options.resume_session_at {
        push_equals(&mut args, "--resume-session-at", value);
    }
    if let Some(value) = &options.resume_drops_turn {
        push_equals(&mut args, "--resume-drops-turn", value);
    }
    let setting_sources = options.setting_sources.clone().or_else(|| {
        options
            .skills
            .as_ref()
            .map(|_| vec!["user".into(), "project".into()])
    });
    if let Some(sources) = setting_sources {
        push_equals(&mut args, "--setting-sources", &sources.join(","));
    }
    for (flag, value) in &options.extra_args {
        let name = format!("--{flag}");
        match value {
            None => args.push(name.into()),
            Some(value) if value.starts_with('-') => push_equals(&mut args, &name, value),
            Some(value) => push_pair(&mut args, &name, value),
        }
    }
    match &options.thinking {
        Some(ThinkingConfig::Adaptive) => push_pair(&mut args, "--thinking", "adaptive"),
        Some(ThinkingConfig::Disabled) => push_pair(&mut args, "--thinking", "disabled"),
        Some(ThinkingConfig::Enabled {
            budget_tokens,
            display,
        }) => {
            push_pair(
                &mut args,
                "--max-thinking-tokens",
                &budget_tokens.to_string(),
            );
            if let Some(display) = display {
                push_pair(&mut args, "--thinking-display", display);
            }
        }
        None => {
            if let Some(tokens) = options.max_thinking_tokens {
                push_pair(&mut args, "--max-thinking-tokens", &tokens.to_string());
            }
        }
    }
    if let Some(effort) = &options.effort {
        push_pair(&mut args, "--effort", effort);
    }
    if let Some(Value::Object(format)) = &options.output_format {
        if format.get("type").and_then(serde_json::Value::as_str) == Some("json_schema") {
            if let Some(schema) = format.get("schema") {
                push_pair(&mut args, "--json-schema", &schema.to_string());
            }
        }
    }
    args.extend([
        OsString::from("--input-format"),
        OsString::from("stream-json"),
    ]);
    args
}

fn push_pair(args: &mut Vec<OsString>, name: &str, value: &str) {
    args.push(name.into());
    args.push(value.into());
}

fn push_equals(args: &mut Vec<OsString>, name: &str, value: &str) {
    args.push(format!("{name}={value}").into());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_fork_and_effort_launch_args_match_upstream_options() {
        let options = ClaudeAgentOptions {
            resume: Some("source-session".into()),
            fork_session: true,
            resume_session_at: Some("transcript-uuid".into()),
            effort: Some("high".into()),
            ..Default::default()
        };
        let config = build_process_config(&options);
        let args = config
            .args
            .iter()
            .map(|arg| arg.to_string_lossy().into_owned())
            .collect::<Vec<_>>();
        assert!(args.iter().any(|arg| arg == "--resume=source-session"));
        assert!(args.iter().any(|arg| arg == "--fork-session"));
        assert!(args
            .iter()
            .any(|arg| arg == "--resume-session-at=transcript-uuid"));
        assert!(args.windows(2).any(|pair| pair == ["--effort", "high"]));
        assert!(!args.iter().any(|arg| arg == "--reasoning-effort"));
    }

    #[test]
    fn file_checkpointing_uses_exact_upstream_environment_value() {
        let options = ClaudeAgentOptions {
            enable_file_checkpointing: true,
            env: std::collections::BTreeMap::from([(
                "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING".into(),
                "caller-value".into(),
            )]),
            ..Default::default()
        };
        let config = build_process_config(&options);
        assert_eq!(
            config
                .env
                .get(&OsString::from("CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING")),
            Some(&OsString::from("true"))
        );
        let disabled = build_process_config(&ClaudeAgentOptions::default());
        assert!(!disabled
            .env
            .contains_key(&OsString::from("CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING")));
    }

    #[test]
    fn session_state_events_are_enabled_without_overriding_options_env() {
        let options = ClaudeAgentOptions::default();
        let config = build_process_config(&options);
        assert_eq!(
            config
                .env
                .get(&OsString::from("CLAUDE_CODE_SDK_READS_SESSION_STATE")),
            Some(&OsString::from("1"))
        );

        let options = ClaudeAgentOptions {
            env: [("CLAUDE_CODE_SDK_READS_SESSION_STATE".into(), "0".into())]
                .into_iter()
                .collect(),
            ..ClaudeAgentOptions::default()
        };
        let config = build_process_config(&options);
        assert_eq!(
            config
                .env
                .get(&OsString::from("CLAUDE_CODE_SDK_READS_SESSION_STATE")),
            Some(&OsString::from("0"))
        );
    }
}
