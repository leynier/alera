#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AgentAdapter {
    pub agent_type: &'static str,
    pub default_command: &'static str,
    pub force_submit: bool,
    pub interrupt_bytes: &'static [u8],
    pub startup_prompt: AgentStartupPrompt,
}

/// How a freshly launched agent receives the prompt it is supposed to start
/// working on.
///
/// Most spawnable agents get their prompt at launch. `fx` is the exception: it
/// has no interactive initial-prompt argument and its built-in Herdr integration
/// emits an idle event after the TUI is ready, so the host can paste safely then.
/// Print/execute flags (`-p`, `--print`, `-x`) are deliberately unused, since
/// they answer once and exit instead of leaving an agent in the tab.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentStartupPrompt {
    /// Positional, preceded by the standard option terminator so a prompt
    /// starting with a dash is not read as another option.
    PositionalAfterTerminator,
    /// Positional, with no terminator available. `pi` rejects `--` outright
    /// (`Error: Unknown option: --`), so the terminator cannot be used, and a
    /// dash-prefixed prompt has to be defused another way.
    Positional,
    /// A long option carrying the prompt as a single `--flag=<prompt>` token,
    /// which keeps a dash-prefixed prompt out of the parser's way without a
    /// terminator.
    LongOption(&'static str),
    /// The CLI has no interactive initial-prompt argument at all. `amp` only
    /// accepts an opening message on stdin, so the prompt is fed from a file
    /// through a generated launcher script.
    StdinScript,
    /// The CLI starts only without a prompt. A semantic ready event tells the
    /// host when it is safe to paste and submit the opening prompt in the PTY.
    TerminalAfterReady,
}

const CTRL_C: &[u8] = b"\x03";

pub const AGENT_ADAPTERS: &[AgentAdapter] = &[
    AgentAdapter {
        agent_type: "codex",
        default_command: "codex",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::PositionalAfterTerminator,
    },
    AgentAdapter {
        agent_type: "claude",
        default_command: "claude",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::PositionalAfterTerminator,
    },
    AgentAdapter {
        agent_type: "copilot",
        default_command: "copilot",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::LongOption("--interactive"),
    },
    AgentAdapter {
        agent_type: "cursor",
        default_command: "cursor-agent",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::PositionalAfterTerminator,
    },
    AgentAdapter {
        agent_type: "agy",
        default_command: "agy",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::LongOption("--prompt-interactive"),
    },
    AgentAdapter {
        agent_type: "opencode",
        default_command: "opencode",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::LongOption("--prompt"),
    },
    AgentAdapter {
        // OpenCode 2 installs as `opencode2` beside v1's `opencode`.
        agent_type: "opencode2",
        default_command: "opencode2",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::LongOption("--prompt"),
    },
    AgentAdapter {
        agent_type: "pi",
        default_command: "pi",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::Positional,
    },
    AgentAdapter {
        agent_type: "amp",
        default_command: "amp",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::StdinScript,
    },
    AgentAdapter {
        agent_type: "grok",
        default_command: "grok",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::PositionalAfterTerminator,
    },
    AgentAdapter {
        agent_type: "fx",
        default_command: "fx",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_prompt: AgentStartupPrompt::TerminalAfterReady,
    },
];

pub fn adapter_for(agent_type: &str) -> Option<&'static AgentAdapter> {
    AGENT_ADAPTERS
        .iter()
        .find(|adapter| adapter.agent_type == agent_type)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_detected_agent_has_a_spawn_adapter() {
        let types: Vec<_> = AGENT_ADAPTERS
            .iter()
            .map(|adapter| adapter.agent_type)
            .collect();
        assert_eq!(
            types,
            [
                "codex",
                "claude",
                "copilot",
                "cursor",
                "agy",
                "opencode",
                "opencode2",
                "pi",
                "amp",
                "grok",
                "fx"
            ]
        );
        assert!(AGENT_ADAPTERS
            .iter()
            .all(|adapter| !adapter.default_command.is_empty()));
    }

    #[test]
    fn every_agent_declares_how_it_receives_its_initial_prompt() {
        let shapes: Vec<_> = AGENT_ADAPTERS
            .iter()
            .map(|adapter| (adapter.agent_type, adapter.startup_prompt))
            .collect();
        assert_eq!(
            shapes,
            [
                ("codex", AgentStartupPrompt::PositionalAfterTerminator),
                ("claude", AgentStartupPrompt::PositionalAfterTerminator),
                ("copilot", AgentStartupPrompt::LongOption("--interactive")),
                ("cursor", AgentStartupPrompt::PositionalAfterTerminator),
                (
                    "agy",
                    AgentStartupPrompt::LongOption("--prompt-interactive")
                ),
                ("opencode", AgentStartupPrompt::LongOption("--prompt")),
                ("opencode2", AgentStartupPrompt::LongOption("--prompt")),
                ("pi", AgentStartupPrompt::Positional),
                ("amp", AgentStartupPrompt::StdinScript),
                ("grok", AgentStartupPrompt::PositionalAfterTerminator),
                ("fx", AgentStartupPrompt::TerminalAfterReady),
            ]
        );
    }
}
