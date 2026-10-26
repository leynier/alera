use super::*;
use alera_provider_protocol::{McpServerSpec, McpTransport};

fn alera_server(name: &str) -> McpServerSpec {
    McpServerSpec {
        name: name.into(),
        transport: McpTransport::Stdio {
            command: "/usr/bin/alera".into(),
            args: vec!["mcp".into(), "serve".into()],
            env: Default::default(),
            cwd: None,
        },
    }
}

fn built(system_prompt: Option<SystemPrompt>, servers: Vec<McpServerSpec>) -> ClaudeAgentOptions {
    let mut config = ClaudeProviderConfig::default();
    config.options.system_prompt = system_prompt;
    let provider = ClaudeProvider::new(config).unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers = servers;
    provider.build_options(&input).unwrap()
}

#[test]
fn the_injected_alera_server_brings_the_background_wait_guidance() {
    let options = built(None, vec![alera_server("alera")]);
    assert!(matches!(
        options.system_prompt,
        Some(SystemPrompt::Text(ref text)) if text == BACKGROUND_WAIT_INSTRUCTIONS
    ));

    let preset = built(
        Some(SystemPrompt::Preset {
            preset: "claude_code".into(),
            append: Some("Be brief.".into()),
            exclude_dynamic_sections: None,
            snapshot: None,
        }),
        vec![alera_server("alera")],
    );
    let Some(SystemPrompt::Preset {
        append: Some(append),
        ..
    }) = preset.system_prompt
    else {
        panic!("the preset survives");
    };
    assert!(append.starts_with("Be brief.\n\n"));
    assert!(append.ends_with(BACKGROUND_WAIT_INSTRUCTIONS));

    let file = built(
        Some(SystemPrompt::File {
            path: "/prompt.md".into(),
        }),
        vec![alera_server("alera")],
    );
    assert!(matches!(
        file.system_prompt,
        Some(SystemPrompt::File { .. })
    ));
    assert_eq!(
        file.extra_args.get("append-system-prompt"),
        Some(&Some(BACKGROUND_WAIT_INSTRUCTIONS.to_owned()))
    );
}

#[test]
fn other_servers_leave_the_system_prompt_alone() {
    assert!(built(None, Vec::new()).system_prompt.is_none());
    assert!(built(None, vec![alera_server("other")])
        .system_prompt
        .is_none());
}

#[test]
fn only_running_background_commands_match_once_each() {
    let mut tasks = BackgroundTasks::default();
    tasks.observe(&EventKind::TaskStarted, "bash-1", true);
    tasks.observe(&EventKind::TaskStarted, "bash-2", true);
    tasks.observe(&EventKind::TaskStarted, "agent", false);
    tasks.observe(&EventKind::TaskProgress, "bash-3", true);
    tasks.observe(&EventKind::TaskCompleted, "bash-2", true);
    let requested = ["bash-1", "agent", "bash-2", "bash-1", "bash-3"].map(String::from);
    assert_eq!(tasks.matching(&requested), vec!["bash-1".to_owned()]);
    tasks.clear();
    assert!(tasks.matching(&requested).is_empty());
}
