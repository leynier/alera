use alera_core::runtime::{AgentProfile, AgentProfileLaunchMode};
use serde::{Deserialize, Serialize};

use super::agent_registry::{AgentAdapter, AgentStartupPrompt};
use super::managed_agent_launch::ManagedAgentLaunch;

pub const AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY: &str = "agentProfileLaunchV1";

/// The immutable launch inputs resolved from an agent profile before a tab is
/// spawned. Environment is deliberately outside this contract: it is resolved
/// in memory by the terminal host and may contain credentials.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfileLaunchSnapshotV1 {
    pub version: u8,
    pub profile: AgentProfileIdentityV1,
    pub agent_type: String,
    pub launch_mode: AgentProfileLaunchMode,
    pub launch: AgentProfileEffectiveLaunchV1,
    pub target: AgentProfileLaunchTargetV1,
    pub initial_delivery: AgentInitialDeliveryV1,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfileIdentityV1 {
    pub id: String,
    pub name: String,
    /// Concrete OCC revision resolved for this launch. New profiles begin at
    /// revision 0; recovery uses this identity without reading the catalog.
    pub revision: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AgentProfileEffectiveLaunchV1 {
    /// Command mode remains an opaque interactive-shell line. Splitting it
    /// would require guessing the user's shell grammar and would change its
    /// behavior on at least one supported platform.
    Command { command: String },
    Managed {
        executable: String,
        argv: Vec<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfileLaunchTargetV1 {
    pub target: AgentProfileLaunchTargetKindV1,
    pub platform: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AgentProfileLaunchTargetKindV1 {
    LocalTerminal,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentInitialDeliveryV1 {
    pub mechanism: AgentInitialDeliveryMechanismV1,
    pub replay: AgentInitialDeliveryReplayV1,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AgentInitialDeliveryMechanismV1 {
    PositionalAfterTerminator,
    Positional,
    LongOption { flag: String },
    StdinScript,
    TerminalAfterReady,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AgentInitialDeliveryReplayV1 {
    Once,
    OnRestart,
}

impl AgentProfileLaunchSnapshotV1 {
    pub fn new(
        profile: &AgentProfile,
        adapter: &AgentAdapter,
        command: Option<String>,
        managed_launch: Option<ManagedAgentLaunch>,
        replay: AgentInitialDeliveryReplayV1,
    ) -> Result<Self, String> {
        let launch = match profile.launch_mode {
            AgentProfileLaunchMode::Command => AgentProfileEffectiveLaunchV1::Command {
                command: command.ok_or_else(|| {
                    "command agent profile resolved without a command.".to_string()
                })?,
            },
            AgentProfileLaunchMode::Managed => {
                let launch = managed_launch.ok_or_else(|| {
                    "managed agent profile resolved without an executable.".to_string()
                })?;
                AgentProfileEffectiveLaunchV1::Managed {
                    executable: launch.executable,
                    argv: launch.arguments,
                }
            }
        };
        Ok(Self {
            version: 1,
            profile: AgentProfileIdentityV1 {
                id: profile.id.clone(),
                name: profile.name.clone(),
                revision: profile.revision,
            },
            agent_type: adapter.agent_type.to_string(),
            launch_mode: profile.launch_mode,
            launch,
            target: AgentProfileLaunchTargetV1 {
                target: AgentProfileLaunchTargetKindV1::LocalTerminal,
                platform: std::env::consts::OS.to_string(),
            },
            initial_delivery: AgentInitialDeliveryV1 {
                mechanism: AgentInitialDeliveryMechanismV1::from(adapter.startup_prompt),
                replay,
            },
        })
    }

    pub fn managed_launch(&self) -> Option<ManagedAgentLaunch> {
        match &self.launch {
            AgentProfileEffectiveLaunchV1::Managed { executable, argv } => {
                Some(ManagedAgentLaunch {
                    executable: executable.clone(),
                    arguments: argv.clone(),
                })
            }
            AgentProfileEffectiveLaunchV1::Command { .. } => None,
        }
    }

    pub fn command(&self) -> Option<&str> {
        match &self.launch {
            AgentProfileEffectiveLaunchV1::Command { command } => Some(command),
            AgentProfileEffectiveLaunchV1::Managed { .. } => None,
        }
    }
}

impl From<AgentStartupPrompt> for AgentInitialDeliveryMechanismV1 {
    fn from(value: AgentStartupPrompt) -> Self {
        match value {
            AgentStartupPrompt::PositionalAfterTerminator => Self::PositionalAfterTerminator,
            AgentStartupPrompt::Positional => Self::Positional,
            AgentStartupPrompt::LongOption(flag) => Self::LongOption {
                flag: flag.to_string(),
            },
            AgentStartupPrompt::StdinScript => Self::StdinScript,
            AgentStartupPrompt::TerminalAfterReady => Self::TerminalAfterReady,
        }
    }
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use serde_json::json;

    use super::*;
    use crate::terminal_host::orchestration::agent_registry::adapter_for;

    fn profile(mode: AgentProfileLaunchMode) -> AgentProfile {
        let now = Utc::now();
        AgentProfile {
            id: "profile-1".to_string(),
            name: "Codex Stable".to_string(),
            sort_order: 0,
            agent_type: "codex".to_string(),
            command: "codex --search && printf 'done'".to_string(),
            launch_mode: mode,
            managed_config: None,
            custom_prompt: String::new(),
            description: String::new(),
            quota_group: None,
            revision: 0,
            created_at: now,
            updated_at: now,
        }
    }

    #[test]
    fn managed_snapshot_round_trips_effective_argv_without_configuration_or_environment() {
        let snapshot = AgentProfileLaunchSnapshotV1::new(
            &profile(AgentProfileLaunchMode::Managed),
            adapter_for("codex").unwrap(),
            None,
            Some(ManagedAgentLaunch {
                executable: "codex".to_string(),
                arguments: vec!["--model".to_string(), "stable".to_string()],
            }),
            AgentInitialDeliveryReplayV1::Once,
        )
        .unwrap();
        let encoded = serde_json::to_value(&snapshot).unwrap();
        let decoded: AgentProfileLaunchSnapshotV1 =
            serde_json::from_value(encoded.clone()).unwrap();

        assert_eq!(decoded, snapshot);
        assert_eq!(encoded["version"], json!(1));
        assert_eq!(encoded["launch"]["executable"], json!("codex"));
        assert_eq!(encoded["launch"]["argv"], json!(["--model", "stable"]));
        assert!(encoded.get("environment").is_none());
        assert!(encoded.get("managedConfig").is_none());
        assert_eq!(encoded["profile"]["revision"], json!(0));
    }

    #[test]
    fn available_occ_revision_round_trips_as_profile_identity() {
        let mut profile = profile(AgentProfileLaunchMode::Command);
        profile.revision = 7;
        let snapshot = AgentProfileLaunchSnapshotV1::new(
            &profile,
            adapter_for("codex").unwrap(),
            Some("codex".to_string()),
            None,
            AgentInitialDeliveryReplayV1::Once,
        )
        .unwrap();
        let encoded = serde_json::to_value(&snapshot).unwrap();
        let decoded: AgentProfileLaunchSnapshotV1 = serde_json::from_value(encoded).unwrap();

        assert_eq!(decoded.profile.revision, 7);
    }

    #[test]
    fn command_snapshot_preserves_the_opaque_line_verbatim() {
        let profile = profile(AgentProfileLaunchMode::Command);
        let snapshot = AgentProfileLaunchSnapshotV1::new(
            &profile,
            adapter_for("codex").unwrap(),
            Some(profile.command.clone()),
            None,
            AgentInitialDeliveryReplayV1::OnRestart,
        )
        .unwrap();

        assert_eq!(snapshot.command(), Some("codex --search && printf 'done'"));
    }

    #[test]
    fn persisted_snapshot_survives_profile_edit_delete_and_restart_decode() {
        let mut profile = profile(AgentProfileLaunchMode::Command);
        let snapshot = AgentProfileLaunchSnapshotV1::new(
            &profile,
            adapter_for("codex").unwrap(),
            Some(profile.command.clone()),
            None,
            AgentInitialDeliveryReplayV1::OnRestart,
        )
        .unwrap();
        let persisted = serde_json::to_vec(&snapshot).unwrap();

        profile.name = "Edited Profile".to_string();
        profile.agent_type = "claude".to_string();
        profile.command = "claude --dangerously-skip-permissions".to_string();
        drop(profile);

        let after_restart: AgentProfileLaunchSnapshotV1 =
            serde_json::from_slice(&persisted).unwrap();
        assert_eq!(after_restart.profile.id, "profile-1");
        assert_eq!(after_restart.profile.name, "Codex Stable");
        assert_eq!(after_restart.agent_type, "codex");
        assert_eq!(
            after_restart.command(),
            Some("codex --search && printf 'done'")
        );
    }
}
