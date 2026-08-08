use super::{parse_codex_models, parse_cursor_models, parse_grok_models};

#[test]
fn parses_codex_thinking_metadata() {
    let models = parse_codex_models(
        r#"{"models":[{"slug":"gpt-5.3-codex-spark","display_name":"GPT-5.3 Codex Spark","default_reasoning_level":"high"}]}"#,
    );
    assert_eq!(models[0]["id"], "gpt-5.3-codex-spark");
    assert_eq!(models[0]["defaultThinkingLevel"], "high");
    assert_eq!(models[0]["thinkingLevels"][3]["id"], "xhigh");
}

#[test]
fn parses_cursor_and_grok_formats() {
    let cursor = parse_cursor_models("auto - Auto (default)\nsonnet - Claude Sonnet\n");
    assert_eq!(cursor[0]["label"], "Auto");
    let grok = parse_grok_models("* grok-4.5 (default)\n- grok-code-fast\n");
    assert_eq!(grok[1]["id"], "grok-code-fast");
    assert_eq!(grok[1]["defaultThinkingLevel"], "default");
}
