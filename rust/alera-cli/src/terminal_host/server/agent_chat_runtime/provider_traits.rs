//! What each provider adapter implements, known without starting it. The
//! catalog and an idle chat's session report these; a running provider's own
//! `capabilities()` replaces the protocol flags once it is up.

use alera_provider_protocol::{McpInjectionCapabilities, ProviderCapabilities, RuntimeMode};
use serde_json::{json, Value};

pub(crate) const PROVIDERS: [&str; 9] = [
    "codex",
    "claudeAgent",
    "cursor",
    "grok",
    "opencode",
    "antigravity",
    "pi",
    "muse",
    "acpRegistry",
];

pub(crate) struct ProviderTraits {
    pub label: &'static str,
    pub capabilities: ProviderCapabilities,
    pub images: bool,
    pub files: bool,
    pub runtime_modes: &'static [&'static str],
    pub interaction_modes: &'static [&'static str],
    /// `TurnInput.model` changes the model of a running session.
    pub per_turn_model: bool,
}

const ALL_MODES: &[&str] = &[
    "approval-required",
    "auto-accept-edits",
    "auto",
    "full-access",
];
const DEFAULT_MODE: &[&str] = &["approval-required"];

fn caps(
    resume: bool,
    approvals: bool,
    user_input: bool,
    elicitation: bool,
    model_switch: bool,
    mcp_http: bool,
) -> ProviderCapabilities {
    ProviderCapabilities {
        // These are expected adapter transports. ACP and Muse confirm them
        // during initialization; the live capabilities remain authoritative.
        mcp_injection: McpInjectionCapabilities {
            stdio: true,
            http: mcp_http,
        },
        resume,
        interrupt: true,
        approvals,
        user_input,
        mcp_elicitation: elicitation,
        streaming: true,
        native_turn_ids: false,
        multiple_threads: false,
        model_switch,
        steer: false,
        snapshot: false,
        rollback: false,
        fork: false,
    }
}

pub(crate) fn provider_traits(provider: &str) -> Option<ProviderTraits> {
    let mut traits = match provider {
        "codex" => ProviderTraits {
            label: "Codex",
            capabilities: caps(true, true, true, true, true, true),
            images: true,
            files: false,
            runtime_modes: ALL_MODES,
            interaction_modes: &["default", "plan"],
            per_turn_model: true,
        },
        "claudeAgent" => ProviderTraits {
            label: "Claude Code",
            capabilities: caps(true, true, true, false, false, true),
            images: false,
            files: false,
            runtime_modes: ALL_MODES,
            interaction_modes: &["default", "plan"],
            per_turn_model: false,
        },
        "cursor" => ProviderTraits {
            label: "Cursor",
            capabilities: caps(true, false, false, false, true, true),
            images: true,
            files: false,
            runtime_modes: DEFAULT_MODE,
            interaction_modes: &["default", "plan"],
            per_turn_model: true,
        },
        "grok" => ProviderTraits {
            label: "Grok",
            capabilities: caps(true, true, true, true, false, true),
            images: false,
            files: false,
            runtime_modes: &["approval-required", "auto", "full-access"],
            interaction_modes: &["default"],
            per_turn_model: false,
        },
        "opencode" => ProviderTraits {
            label: "OpenCode",
            capabilities: caps(true, true, true, false, true, true),
            images: true,
            files: false,
            runtime_modes: DEFAULT_MODE,
            interaction_modes: &["default"],
            per_turn_model: true,
        },
        "antigravity" => ProviderTraits {
            label: "Antigravity",
            capabilities: caps(true, true, true, true, false, true),
            images: false,
            files: false,
            runtime_modes: ALL_MODES,
            interaction_modes: &["default"],
            per_turn_model: false,
        },
        "pi" => ProviderTraits {
            label: "Pi",
            capabilities: caps(true, true, true, false, true, false),
            images: true,
            files: false,
            runtime_modes: DEFAULT_MODE,
            interaction_modes: &["default"],
            per_turn_model: true,
        },
        "muse" => ProviderTraits {
            label: "Muse",
            capabilities: caps(true, true, true, false, true, true),
            images: false,
            files: false,
            runtime_modes: &["approval-required", "auto", "full-access"],
            interaction_modes: &["default"],
            per_turn_model: true,
        },
        "acpRegistry" => ProviderTraits {
            label: "ACP Agent",
            capabilities: caps(false, true, true, true, false, true),
            images: false,
            files: false,
            runtime_modes: DEFAULT_MODE,
            interaction_modes: &["default"],
            per_turn_model: false,
        },
        _ => return None,
    };
    traits.capabilities.native_turn_ids = matches!(provider, "codex" | "cursor" | "muse");
    traits.capabilities.steer = provider == "codex";
    traits.capabilities.fork = matches!(provider, "codex" | "claudeAgent");
    traits.capabilities.rollback = provider == "codex";
    Some(traits)
}

pub(crate) fn parse_runtime_mode(value: &str) -> Option<RuntimeMode> {
    serde_json::from_value(Value::String(value.to_string())).ok()
}

/// The `capabilities` object of a session: protocol flags plus what the
/// adapter accepts as turn input.
pub(crate) fn capabilities_json(provider: &str, live: Option<&ProviderCapabilities>) -> Value {
    let traits = provider_traits(provider);
    let fallback = traits
        .as_ref()
        .map(|traits| traits.capabilities.clone())
        .unwrap_or_default();
    let caps = live.unwrap_or(&fallback);
    json!({
        "resume": caps.resume,
        "interrupt": caps.interrupt,
        "approvals": caps.approvals,
        "userInput": caps.user_input,
        "mcpElicitation": caps.mcp_elicitation,
        "streaming": caps.streaming,
        "modelSwitch": caps.model_switch,
        "steer": caps.steer,
        "fork": caps.fork,
        "rollback": caps.rollback,
        "snapshot": caps.snapshot,
        "nativeTurnIds": caps.native_turn_ids,
        "multipleThreads": caps.multiple_threads,
        // Codex interrupts a child thread's turn; Claude stops a task.
        "stopSubagent": matches!(provider, "claude" | "codex"),
        "attachments": traits.as_ref().is_some_and(|t| t.images || t.files),
        "images": traits.as_ref().is_some_and(|t| t.images),
        "plan": traits.as_ref().is_some_and(|t| t.interaction_modes.contains(&"plan")),
        "mcpInjection": {
            "stdio": caps.mcp_injection.stdio,
            "http": caps.mcp_injection.http,
        },
    })
}

pub(crate) fn mcp_injection_source(provider: &str) -> &'static str {
    match provider {
        "grok" | "antigravity" | "acpRegistry" | "muse" => "negotiated",
        "opencode" => "configuration",
        _ => "adapter",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_provider_has_traits_and_a_default_mode() {
        for provider in PROVIDERS {
            let traits = provider_traits(provider).expect(provider);
            assert!(traits.runtime_modes.contains(&"approval-required"));
            for mode in traits.runtime_modes {
                assert!(parse_runtime_mode(mode).is_some(), "{mode}");
            }
        }
    }
}
