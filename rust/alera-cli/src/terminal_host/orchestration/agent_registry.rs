#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AgentAdapter {
    pub agent_type: &'static str,
    pub default_command: &'static str,
    pub force_submit: bool,
    pub interrupt_bytes: &'static [u8],
    pub startup_delivery: AgentStartupDelivery,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentStartupDelivery {
    InitialPromptArgument,
    ReadinessInjection,
}

const CTRL_C: &[u8] = b"\x03";

pub const AGENT_ADAPTERS: &[AgentAdapter] = &[
    AgentAdapter {
        agent_type: "codex",
        default_command: "codex",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_delivery: AgentStartupDelivery::InitialPromptArgument,
    },
    AgentAdapter {
        agent_type: "claude",
        default_command: "claude",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_delivery: AgentStartupDelivery::ReadinessInjection,
    },
    AgentAdapter {
        agent_type: "copilot",
        default_command: "copilot",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_delivery: AgentStartupDelivery::ReadinessInjection,
    },
    AgentAdapter {
        agent_type: "cursor",
        default_command: "cursor-agent",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_delivery: AgentStartupDelivery::ReadinessInjection,
    },
    AgentAdapter {
        agent_type: "agy",
        default_command: "agy",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_delivery: AgentStartupDelivery::ReadinessInjection,
    },
    AgentAdapter {
        agent_type: "opencode",
        default_command: "opencode",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_delivery: AgentStartupDelivery::ReadinessInjection,
    },
    AgentAdapter {
        agent_type: "pi",
        default_command: "pi",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_delivery: AgentStartupDelivery::ReadinessInjection,
    },
    AgentAdapter {
        agent_type: "amp",
        default_command: "amp",
        force_submit: true,
        interrupt_bytes: CTRL_C,
        startup_delivery: AgentStartupDelivery::ReadinessInjection,
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
            ["codex", "claude", "copilot", "cursor", "agy", "opencode", "pi", "amp"]
        );
        assert!(AGENT_ADAPTERS
            .iter()
            .all(|adapter| !adapter.default_command.is_empty()));
    }

    #[test]
    fn only_codex_receives_its_initial_prompt_as_an_argument() {
        let initial_argument_agents: Vec<_> = AGENT_ADAPTERS
            .iter()
            .filter(|adapter| {
                adapter.startup_delivery == AgentStartupDelivery::InitialPromptArgument
            })
            .map(|adapter| adapter.agent_type)
            .collect();
        assert_eq!(initial_argument_agents, ["codex"]);
        assert!(AGENT_ADAPTERS
            .iter()
            .filter(|adapter| adapter.agent_type != "codex")
            .all(|adapter| adapter.startup_delivery == AgentStartupDelivery::ReadinessInjection));
    }
}
