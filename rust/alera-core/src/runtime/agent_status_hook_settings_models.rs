use serde::{Deserialize, Serialize};

/// Which agents report status through Alera's hooks.
///
/// OpenCode v1 and OpenCode 2 used to be separate agents with their own
/// `opencode2` toggle; both install as `opencode` now. The wire form still
/// reads that key (either toggle enables OpenCode) and writes it as a copy of
/// `opencode`, because the app can attach to an older sidecar, and an older
/// app to a newer one, and each side must keep installing the plugin the
/// other expects.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(
    rename_all = "camelCase",
    from = "RuntimeAgentStatusHookSettingsWire",
    into = "RuntimeAgentStatusHookSettingsWire"
)]
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
    #[serde(default)]
    pub fx: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeAgentStatusHookSettingsWire {
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
    opencode2: bool,
    #[serde(default)]
    pub pi: bool,
    #[serde(default)]
    pub amp: bool,
    #[serde(default)]
    pub grok: bool,
    #[serde(default)]
    pub fx: bool,
}

impl From<RuntimeAgentStatusHookSettingsWire> for RuntimeAgentStatusHookSettings {
    fn from(wire: RuntimeAgentStatusHookSettingsWire) -> Self {
        Self {
            codex: wire.codex,
            claude: wire.claude,
            copilot: wire.copilot,
            cursor: wire.cursor,
            agy: wire.agy,
            opencode: wire.opencode || wire.opencode2,
            pi: wire.pi,
            amp: wire.amp,
            grok: wire.grok,
            fx: wire.fx,
        }
    }
}

impl From<RuntimeAgentStatusHookSettings> for RuntimeAgentStatusHookSettingsWire {
    fn from(settings: RuntimeAgentStatusHookSettings) -> Self {
        Self {
            codex: settings.codex,
            claude: settings.claude,
            copilot: settings.copilot,
            cursor: settings.cursor,
            agy: settings.agy,
            opencode: settings.opencode,
            opencode2: settings.opencode,
            pi: settings.pi,
            amp: settings.amp,
            grok: settings.grok,
            fx: settings.fx,
        }
    }
}

impl RuntimeAgentStatusHookSettings {
    pub fn is_enabled(&self, agent: &str) -> bool {
        match agent {
            "codex" => self.codex,
            "claude" => self.claude,
            "copilot" => self.copilot,
            "cursor" => self.cursor,
            "agy" => self.agy,
            "opencode" | "opencode2" => self.opencode,
            "pi" => self.pi,
            "amp" => self.amp,
            "grok" => self.grok,
            "fx" => self.fx,
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
            "opencode" | "opencode2" => &mut self.opencode,
            "pi" => &mut self.pi,
            "amp" => &mut self.amp,
            "grok" => &mut self.grok,
            "fx" => &mut self.fx,
            _ => return false,
        };
        *target = enabled;
        true
    }

    pub fn enabled_agents(&self) -> Vec<&'static str> {
        const AGENTS: [&str; 10] = [
            "codex", "claude", "copilot", "cursor", "agy", "opencode", "pi", "amp", "grok", "fx",
        ];
        AGENTS
            .into_iter()
            .filter(|agent| self.is_enabled(agent))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn either_opencode_toggle_enables_opencode() {
        let legacy: RuntimeAgentStatusHookSettings =
            serde_json::from_value(json!({"opencode": false, "opencode2": true})).unwrap();
        assert!(legacy.opencode);
        assert!(legacy.is_enabled("opencode2"));
        let off: RuntimeAgentStatusHookSettings =
            serde_json::from_value(json!({"opencode": false})).unwrap();
        assert!(!off.opencode);
    }

    #[test]
    fn the_retired_opencode2_key_is_written_as_a_copy_of_opencode() {
        let mut settings = RuntimeAgentStatusHookSettings::default();
        assert!(settings.set_enabled("opencode2", true));
        let wire = serde_json::to_value(&settings).unwrap();
        assert_eq!(wire["opencode"], json!(true));
        assert_eq!(wire["opencode2"], json!(true));
        assert_eq!(settings.enabled_agents(), ["opencode"]);
    }
}
