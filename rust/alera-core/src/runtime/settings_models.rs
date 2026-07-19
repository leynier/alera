use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSettings {
    #[serde(default)]
    pub workspace_directory: Option<String>,
    #[serde(default = "default_true")]
    pub confirm_workspace_removal: bool,
    #[serde(default)]
    pub agent_status_hooks: RuntimeAgentStatusHookSettings,
}

impl Default for RuntimeSettings {
    fn default() -> Self {
        Self {
            workspace_directory: None,
            confirm_workspace_removal: true,
            agent_status_hooks: RuntimeAgentStatusHookSettings::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAgentStatusHookSettings {
    #[serde(default)]
    pub codex: bool,
    #[serde(default)]
    pub claude: bool,
    #[serde(default)]
    pub copilot: bool,
    #[serde(default)]
    pub cursor: bool,
    #[serde(default)]
    pub agy: bool,
    #[serde(default)]
    pub opencode: bool,
    #[serde(default)]
    pub pi: bool,
    #[serde(default)]
    pub amp: bool,
    #[serde(default)]
    pub grok: bool,
}

impl RuntimeAgentStatusHookSettings {
    pub fn is_enabled(&self, agent: &str) -> bool {
        match agent {
            "codex" => self.codex,
            "claude" => self.claude,
            "copilot" => self.copilot,
            "cursor" => self.cursor,
            "agy" => self.agy,
            "opencode" => self.opencode,
            "pi" => self.pi,
            "amp" => self.amp,
            "grok" => self.grok,
            _ => false,
        }
    }

    pub fn set_enabled(&mut self, agent: &str, enabled: bool) -> bool {
        let target = match agent {
            "codex" => &mut self.codex,
            "claude" => &mut self.claude,
            "copilot" => &mut self.copilot,
            "cursor" => &mut self.cursor,
            "agy" => &mut self.agy,
            "opencode" => &mut self.opencode,
            "pi" => &mut self.pi,
            "amp" => &mut self.amp,
            "grok" => &mut self.grok,
            _ => return false,
        };
        *target = enabled;
        true
    }

    pub fn enabled_agents(&self) -> Vec<&'static str> {
        const AGENTS: [&str; 9] = [
            "codex", "claude", "copilot", "cursor", "agy", "opencode", "pi", "amp", "grok",
        ];
        AGENTS
            .into_iter()
            .filter(|agent| self.is_enabled(agent))
            .collect()
    }
}

fn default_true() -> bool {
    true
}
