use serde_json::json;

use super::super::managed_agent_launch::build_managed_agent_launch;
use super::*;

#[test]
fn rendering_quotes_each_token_for_supported_shell_families() {
    let launch = ManagedAgentLaunch {
        executable: "agy".to_string(),
        arguments: vec![
            "--model".to_string(),
            "Gemini 3.5 Flash (High)".to_string(),
            "it's ready".to_string(),
        ],
    };
    assert_eq!(
        render_managed_launch(&launch, "/bin/zsh"),
        "'agy' '--model' 'Gemini 3.5 Flash (High)' 'it'\"'\"'s ready'"
    );
    assert_eq!(
        render_managed_launch(&launch, "pwsh.exe"),
        "'agy' '--model' 'Gemini 3.5 Flash (High)' 'it''s ready'"
    );
    assert_eq!(
        render_managed_launch(&launch, "cmd.exe"),
        "\"agy\" \"--model\" \"Gemini 3.5 Flash (High)\" \"it's ready\""
    );
}

#[test]
fn codex_managed_prompt_follows_the_option_terminator_on_every_shell() {
    let mut launch = build_managed_agent_launch("codex", &json!({"webSearch": true})).unwrap();
    crate::terminal_host::orchestration::agent_startup_command::append_codex_initial_prompt_argument(
        &mut launch.arguments,
        "- Review why it's pending\n- Implement memory".to_string(),
    );
    assert_eq!(
        render_managed_launch(&launch, "/bin/zsh"),
        "'codex' '--search' '--' '- Review why it'\"'\"'s pending\n- Implement memory'"
    );
    assert_eq!(
        render_managed_launch(&launch, "pwsh.exe"),
        "'codex' '--search' '--' '- Review why it''s pending\n- Implement memory'"
    );
    assert_eq!(
        render_managed_launch(&launch, "cmd.exe"),
        "\"codex\" \"--search\" \"--\" \"- Review why it's pending\n- Implement memory\""
    );
}
