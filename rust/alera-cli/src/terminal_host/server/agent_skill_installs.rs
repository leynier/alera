//! `agentSkill.install` and `agentSkill.state`: installing the Alera skills
//! coding agents use, as a runtime job.
//!
//! An install can take minutes on a cold clone, longer than an MCP client
//! waits for one call. The job belongs to the runtime, not to the request, so
//! it finishes even when the caller stops waiting, and only one runs at a
//! time: a second request while one is running is refused instead of starting
//! another installer against the same folders. `agentSkill.state` reports the
//! running job and the last result.

use std::sync::{Mutex, MutexGuard, OnceLock};

use chrono::Utc;
use serde_json::{json, Value};

use crate::agent_status::reconcile_agent_integrations;
use crate::host_tools::{install_skills, SkillKind, SkillRunner};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

/// The message a request gets while another install is running.
pub(crate) const INSTALL_RUNNING_MESSAGE: &str = "An agent skill install is already running.";

#[derive(Default)]
struct InstallState {
    running: Option<Value>,
    last: Option<Value>,
}

fn state() -> MutexGuard<'static, InstallState> {
    static STATE: OnceLock<Mutex<InstallState>> = OnceLock::new();
    STATE
        .get_or_init(Mutex::default)
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// The running install, if any, and the last finished one.
pub(super) fn install_state() -> Value {
    let state = state();
    json!({ "running": state.running, "last": state.last })
}

pub(super) fn install_running() -> bool {
    state().running.is_some()
}

/// Clears the running install when its task ends, even by panic, so a failed
/// install never blocks the next one.
struct RunningInstall;

impl Drop for RunningInstall {
    fn drop(&mut self) {
        state().running = None;
    }
}

fn claim(operation_id: &str, skills: &[SkillKind]) -> HostResult<RunningInstall> {
    let mut state = state();
    if state.running.is_some() {
        return Err(HostError::state(INSTALL_RUNNING_MESSAGE));
    }
    state.running = Some(json!({
        "operationId": operation_id,
        "skills": skills.iter().map(|kind| kind.id()).collect::<Vec<_>>(),
        "startedAt": Utc::now(),
    }));
    Ok(RunningInstall)
}

/// `skills` lists several skills; `skill` names one, as the mobile app sends.
fn requested_skills(payload: &Value) -> HostResult<Vec<SkillKind>> {
    let names = match payload.get("skills").and_then(Value::as_array) {
        Some(names) => names
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_owned)
            .collect(),
        None => vec![required_non_blank(payload, "skill")?],
    };
    let kinds = names
        .iter()
        .map(|name| {
            SkillKind::parse(name).ok_or_else(|| {
                HostError::format(
                    "skill must be cli, orchestration, automations, or agentProfiles.",
                )
            })
        })
        .collect::<HostResult<Vec<_>>>()?;
    if kinds.is_empty() {
        return Err(HostError::format("skills must name at least one skill."));
    }
    Ok(kinds)
}

impl ServerActor {
    pub(super) fn start_skill_install_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let skills = requested_skills(payload)?;
        let runner_name = required_non_blank(payload, "runner")?;
        let runner = SkillRunner::parse(&runner_name)
            .ok_or_else(|| HostError::format("runner must be auto, npx, or bunx."))?;
        let running = claim(&operation_id, &skills)?;
        // The progress events name one skill, as the apps expect; a batch
        // reports under its first.
        let skill_name = skills[0].id().to_owned();
        self.broadcast_authenticated(event(
            "agentSkillInstallProgress",
            json!({
                "operationId": operation_id,
                "skill": skill_name,
                "phase": "installing",
                "message": "Installing Skill",
            }),
        ));
        let store = self.runtime_store.clone();
        let runtime_dir = self.runtime_dir.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let install_result = install_skills(&skills, runner).await;
            let mut value = serde_json::to_value(&install_result)
                .map_err(|error| HostError::state(error.to_string()));
            if install_result.succeeded && skills.contains(&SkillKind::Orchestration) {
                // The agent status hooks are part of the orchestration contract.
                if let Ok(settings) = store.agent_status_hook_settings().await {
                    let warnings = tokio::task::spawn_blocking(move || {
                        reconcile_agent_integrations(&runtime_dir, &settings)
                    })
                    .await
                    .unwrap_or_else(|error| vec![error.to_string()]);
                    if let Ok(Value::Object(object)) = &mut value {
                        object.insert("hookWarnings".to_string(), json!(warnings));
                    }
                }
            }
            if let Ok(Value::Object(object)) = &mut value {
                object.insert("operationId".to_string(), json!(operation_id));
                object.insert("finishedAt".to_string(), json!(Utc::now()));
                state().last = Some(Value::Object(object.clone()));
            }
            drop(running);
            let _ = inbox
                .send_wait(ServerCommand::HostToolFinished {
                    client_id,
                    request_id,
                    result: value,
                    operation_id: Some(operation_id),
                    skill: Some(skill_name),
                })
                .await;
        });
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_batch_or_a_single_skill_is_accepted() {
        let batch = requested_skills(&json!({ "skills": ["cli", "agentProfiles"] })).unwrap();
        assert_eq!(batch, [SkillKind::Cli, SkillKind::AgentProfiles]);
        let single = requested_skills(&json!({ "skill": "orchestration" })).unwrap();
        assert_eq!(single, [SkillKind::Orchestration]);
        assert!(requested_skills(&json!({ "skills": ["nope"] })).is_err());
        assert!(requested_skills(&json!({ "skills": [] })).is_err());
        assert!(requested_skills(&json!({})).is_err());
    }

    #[test]
    fn only_one_install_runs_and_a_finished_one_frees_the_slot() {
        let first = claim("op-1", &[SkillKind::Cli]).unwrap();
        assert!(install_running());
        assert_eq!(install_state()["running"]["operationId"], "op-1");
        let refused = claim("op-2", &[SkillKind::Cli]).err().unwrap();
        assert_eq!(refused.wire_message(), INSTALL_RUNNING_MESSAGE);
        drop(first);
        assert!(!install_running());
        drop(claim("op-3", &[SkillKind::Cli]).unwrap());
    }
}
