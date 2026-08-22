use serde_json::json;

use super::super::agent_registry::adapter_for;
use super::super::agent_startup_command::append_initial_prompt_argument;
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
    append_initial_prompt_argument(
        adapter_for("codex").unwrap(),
        &mut launch.arguments,
        "- Review why it's pending\n- Implement memory",
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

#[test]
fn a_long_option_managed_prompt_stays_one_argument_on_every_shell() {
    let mut launch = build_managed_agent_launch("opencode", &json!({"agent": "build"})).unwrap();
    append_initial_prompt_argument(
        adapter_for("opencode").unwrap(),
        &mut launch.arguments,
        "- Review why it's pending",
    );
    assert_eq!(
        render_managed_launch(&launch, "/bin/zsh"),
        "'opencode' '--agent' 'build' '--prompt=- Review why it'\"'\"'s pending'"
    );
    assert_eq!(
        render_managed_launch(&launch, "cmd.exe"),
        "\"opencode\" \"--agent\" \"build\" \"--prompt=- Review why it's pending\""
    );
}

#[test]
fn a_managed_amp_launch_keeps_its_prompt_off_the_command_line() {
    let mut launch = build_managed_agent_launch("amp", &json!({"mode": "high"})).unwrap();
    append_initial_prompt_argument(
        adapter_for("amp").unwrap(),
        &mut launch.arguments,
        "- Review why it's pending",
    );
    assert_eq!(
        render_managed_launch(&launch, "/bin/zsh"),
        "'amp' '--mode' 'high'"
    );
}
