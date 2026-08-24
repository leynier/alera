use std::collections::BTreeMap;
use std::time::Duration;

use alera_desktop_core::RuntimeBridge;
use freya::prelude::*;
use serde_json::{Value, json};
use uuid::Uuid;

use super::{AgentBehavior, AgentSignals, BEHAVIOR_KEY};

pub(super) fn install_skill(
    bridge: RuntimeBridge,
    skill: &'static str,
    runner: String,
    mut signals: AgentSignals,
) {
    if *signals.busy.read() {
        return;
    }
    signals.busy.set(true);
    signals.message.set(None);
    spawn(async move {
        let skills: &[&str] = if skill == "all" {
            &["cli", "orchestration", "computer-use", "emulator"]
        } else {
            &[skill]
        };
        let mut result = Ok(());
        for skill in skills {
            let payload = json!({
                "operationId": format!("freya-{skill}-{}", Uuid::new_v4()),
                "skill": skill,
                "runner": runner.to_ascii_lowercase(),
            });
            if let Err(error) = bridge
                .request_with_timeout("agentSkill.install", payload, Duration::from_secs(90))
                .await
            {
                result = Err(error);
                break;
            }
        }
        signals.message.set(Some(match result {
            Ok(()) if skill == "all" => "All Alera Skills Installed / Updated".to_string(),
            Ok(()) => "Skill Install Completed".to_string(),
            Err(error) => error,
        }));
        signals.busy.set(false);
    });
}

pub(super) fn update_hook(
    bridge: RuntimeBridge,
    mut hooks: BTreeMap<String, bool>,
    agent: &'static str,
    enabled: bool,
    signals: AgentSignals,
) {
    hooks.insert(agent.to_string(), enabled);
    run_request(
        bridge,
        "runtimeSettings.update",
        json!({"agentStatusHooks": hooks}),
        "Agent Hooks Updated",
        signals,
    );
}

pub(super) fn persist_behavior(
    bridge: RuntimeBridge,
    behavior: AgentBehavior,
    signals: AgentSignals,
) {
    let Ok(value) = serde_json::to_string(&behavior) else {
        return;
    };
    run_request(
        bridge,
        "runtimeMetadata.set",
        json!({"key": BEHAVIOR_KEY, "value": value}),
        "Agent Behavior Updated",
        signals,
    );
}

pub(super) fn run_request(
    bridge: RuntimeBridge,
    verb: &'static str,
    payload: Value,
    success: &'static str,
    mut signals: AgentSignals,
) {
    if *signals.busy.read() {
        return;
    }
    signals.busy.set(true);
    signals.message.set(None);
    spawn(async move {
        match bridge
            .request_with_timeout(verb, payload, Duration::from_secs(30))
            .await
        {
            Ok(_) => {
                signals.message.set(Some(success.to_string()));
                let next_revision = signals.revision.read().saturating_add(1);
                signals.revision.set(next_revision);
            }
            Err(error) => signals.message.set(Some(error)),
        }
        signals.busy.set(false);
    });
}
