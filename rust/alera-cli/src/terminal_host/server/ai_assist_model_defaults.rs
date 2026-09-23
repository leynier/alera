pub(super) fn default_model(agent: &str) -> &'static str {
    match agent {
        "claude" => "sonnet",
        "codex" => "gpt-5.5",
        "copilot" => "gpt-5.4",
        "cursor" => "auto",
        "agy" => "", // empty means AGY uses its own default model
        "opencode" | "opencode2" => "opencode/deepseek-v4-flash-free",
        "opencode-go" => "glm-5.3-flash",
        "pi" => "github-copilot/gpt-5.4-mini",
        "amp" => "smart",
        "grok" => "grok-4.6",
        "fx" => "",
        _ => "custom",
    }
}
