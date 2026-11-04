use super::*;
use alera_provider_protocol::{McpServerSpec, McpTransport};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[test]
fn checkpoint_enabling_adds_native_replay_flag_without_claiming_active_rewind() {
    let provider = ClaudeProvider::new(ClaudeProviderConfig::default()).unwrap();
    let mut input = SessionStartInput::new("app");
    input
        .options
        .insert("enableFileCheckpointing".into(), json!(true));
    let options = provider.build_options(&input).unwrap();
    assert!(options.enable_file_checkpointing);
    assert_eq!(options.extra_args.get("replay-user-messages"), Some(&None));
    let capabilities = provider.native_history_capabilities();
    assert!(capabilities.file_checkpointing);
    assert!(!capabilities.rewind_files);
}

#[test]
fn full_access_overrides_configured_default_permission_mode() {
    let mut config = ClaudeProviderConfig::default();
    config.options.permission_mode = Some("default".into());
    // Claude settings can disable bypass, so none are read here.
    config.options.env.insert(
        "CLAUDE_CONFIG_DIR".into(),
        std::env::temp_dir()
            .join("alera-claude-no-config")
            .to_string_lossy()
            .into_owned(),
    );
    let provider = ClaudeProvider::new(config).unwrap();
    let input = SessionStartInput {
        runtime_mode: RuntimeMode::FullAccess,
        ..SessionStartInput::new("app-thread")
    };

    let options = provider.build_options(&input).unwrap();

    assert_eq!(
        options.permission_mode.as_deref(),
        Some("bypassPermissions")
    );
}

fn stdio_server(name: &str) -> McpServerSpec {
    McpServerSpec {
        name: name.into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("/usr/local/bin/mcp-server"),
            args: vec!["--stdio".into()],
            env: BTreeMap::from([(String::from("MCP_TOKEN"), String::from("private"))]),
            cwd: None,
        },
    }
}

fn http_server(name: &str) -> McpServerSpec {
    McpServerSpec {
        name: name.into(),
        transport: McpTransport::Http {
            url: "http://127.0.0.1:43123/mcp".into(),
            headers: BTreeMap::from([(
                String::from("Authorization"),
                String::from("Bearer private"),
            )]),
        },
    }
}

#[test]
fn injected_mcp_servers_map_to_native_sdk_options_and_trusted_tools_only() {
    let provider = ClaudeProvider::new(ClaudeProviderConfig::default()).unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers = vec![stdio_server("local-tools"), http_server("alera")];

    let options = provider.build_options(&input).unwrap();

    assert_eq!(
        options.mcp_servers["local-tools"],
        json!({
            "type": "stdio",
            "command": "/usr/local/bin/mcp-server",
            "args": ["--stdio"],
            "env": { "MCP_TOKEN": "private" }
        })
    );
    assert_eq!(
        options.mcp_servers["alera"],
        json!({
            "type": "http",
            "url": "http://127.0.0.1:43123/mcp",
            "headers": { "Authorization": "Bearer private" }
        })
    );
    assert!(options
        .allowed_tools
        .iter()
        .any(|tool| tool == "mcp__alera__*"));
    assert!(!options
        .allowed_tools
        .iter()
        .any(|tool| tool == "mcp__local-tools__*"));
}

#[test]
fn injected_mcp_server_name_collision_is_rejected() {
    let mut config = ClaudeProviderConfig::default();
    config.options.mcp_servers.insert(
        "alera".into(),
        json!({ "type": "http", "url": "http://caller.invalid/mcp" }),
    );
    let provider = ClaudeProvider::new(config).unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers = vec![http_server("alera")];

    let error = provider.build_options(&input).unwrap_err();

    assert!(matches!(error, ProviderError::Validation(message) if message.contains("collides")));
}

#[test]
fn injected_mcp_server_stdio_cwd_is_rejected_explicitly() {
    let provider = ClaudeProvider::new(ClaudeProviderConfig::default()).unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers = vec![McpServerSpec {
        name: "local-tools".into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("mcp-server"),
            args: Vec::new(),
            env: BTreeMap::new(),
            cwd: Some(PathBuf::from("/workspace")),
        },
    }];

    let error = provider.build_options(&input).unwrap_err();

    assert!(matches!(error, ProviderError::Unsupported(message) if message.contains("stdio cwd")));
}
