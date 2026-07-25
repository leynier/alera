//! Resolving which agent profile runs a task, and picking the next candidate
//! when an earlier one failed to start.

use alera_core::runtime::OrchestrationPolicyStatus;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::orchestration_validation::optional_string;
use super::ServerActor;

/// The launch identity for one spawn attempt.
pub(super) struct ResolvedSpawnProfile {
    pub agent_type: String,
    /// `None` leaves the adapter's default command in place.
    pub command: Option<String>,
    pub profile_name: Option<String>,
    pub quota_group: Option<String>,
}

impl ServerActor {
    /// Resolves `--profile` into an adapter and command, or falls back to the
    /// explicit `--agent`/`--command` pair.
    pub(super) async fn resolve_spawn_profile(
        &mut self,
        payload: &Value,
    ) -> HostResult<ResolvedSpawnProfile> {
        let Some(name) = optional_string(payload, "profile") else {
            let agent_type = optional_string(payload, "agent").ok_or_else(|| {
                HostError::format("agent is required unless a profile is given.".to_string())
            })?;
            return Ok(ResolvedSpawnProfile {
                agent_type,
                command: optional_string(payload, "command"),
                profile_name: None,
                quota_group: None,
            });
        };
        let profile = self
            .runtime_store
            .agent_profile_by_name(&name)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::format(format!(
                    "unknown agent profile: {name}. Declare it in Settings first."
                ))
            })?;
        Ok(ResolvedSpawnProfile {
            agent_type: profile.agent_type,
            command: Some(profile.command),
            profile_name: Some(profile.name),
            quota_group: profile.quota_group,
        })
    }

    /// Chooses the profile a stage should use next.
    ///
    /// Candidates are the stage's preferred profile followed by its fallbacks,
    /// minus everything already attempted for this task. Among what is left,
    /// a candidate whose quota group differs from the last attempt wins: a
    /// fallback inside the same usage bucket buys nothing, which is the whole
    /// reason the quota group field exists.
    pub(super) async fn next_profile_for_task(
        &mut self,
        task_id: &str,
        stage_id: &str,
        policy: &Value,
    ) -> HostResult<Option<String>> {
        let candidates = stage_candidates(policy, stage_id);
        if candidates.is_empty() {
            return Ok(None);
        }
        let attempted = self
            .runtime_store
            .orchestration_task_attempted_profiles(task_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let remaining: Vec<String> = candidates
            .into_iter()
            .filter(|candidate| {
                !attempted
                    .iter()
                    .any(|used| used.eq_ignore_ascii_case(candidate))
            })
            .collect();
        if remaining.is_empty() {
            return Ok(None);
        }
        let last_group = match attempted.last() {
            None => None,
            Some(name) => self.quota_group_for(name).await?,
        };
        let Some(last_group) = last_group else {
            return Ok(remaining.into_iter().next());
        };
        for candidate in &remaining {
            let group = self.quota_group_for(candidate).await?;
            // An unknown or absent group counts as different: the user did not
            // assert that it shares a bucket, so assuming it does would skip a
            // usable candidate.
            if group.as_deref() != Some(last_group.as_str()) {
                return Ok(Some(candidate.clone()));
            }
        }
        Ok(remaining.into_iter().next())
    }

    /// The profile a task should be launched with, if its run has an approved
    /// policy that declares its stage. Selection failures are not fatal: the
    /// coordinator falls back to the run-level agent type rather than stalling.
    pub(super) async fn coordinator_profile_for_task(
        &mut self,
        task: &alera_core::runtime::OrchestrationTask,
    ) -> Option<String> {
        let stage_id = task.stage_id.as_deref()?;
        let run_id = task.run_id.as_deref()?;
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
            .ok()??;
        if run.execution_policy_status != OrchestrationPolicyStatus::Approved {
            return None;
        }
        let policy: Value = serde_json::from_str(run.execution_policy.as_deref()?).ok()?;
        self.next_profile_for_task(&task.id, stage_id, &policy)
            .await
            .ok()?
    }

    /// The launch command for a task's stage profile, for adapters that get a
    /// bare terminal and dispatch on readiness.
    pub(super) async fn coordinator_profile_command_for_task(
        &mut self,
        task: &alera_core::runtime::OrchestrationTask,
    ) -> Option<String> {
        let name = self.coordinator_profile_for_task(task).await?;
        self.runtime_store
            .agent_profile_by_name(&name)
            .await
            .ok()?
            .map(|profile| profile.command)
    }

    async fn quota_group_for(&mut self, profile_name: &str) -> HostResult<Option<String>> {
        Ok(self
            .runtime_store
            .agent_profile_by_name(profile_name)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .and_then(|profile| profile.quota_group))
    }
}

/// The preferred profile followed by the stage's fallbacks, in order.
fn stage_candidates(policy: &Value, stage_id: &str) -> Vec<String> {
    let Some(stages) = policy.get("stages").and_then(Value::as_array) else {
        return Vec::new();
    };
    let Some(stage) = stages
        .iter()
        .find(|stage| stage.get("id").and_then(Value::as_str) == Some(stage_id))
    else {
        return Vec::new();
    };
    let mut candidates = Vec::new();
    if let Some(profile) = stage.get("profile").and_then(Value::as_str) {
        candidates.push(profile.to_string());
    }
    if let Some(fallbacks) = stage.get("fallbacks").and_then(Value::as_array) {
        for fallback in fallbacks {
            if let Some(name) = fallback.as_str() {
                candidates.push(name.to_string());
            }
        }
    }
    candidates
}

#[cfg(test)]
mod tests {
    use super::stage_candidates;
    use serde_json::json;

    #[test]
    fn candidates_are_the_preferred_profile_then_the_fallbacks() {
        let policy = json!({"stages": [
            {"id": "impl", "profile": "Codex", "fallbacks": ["Claude", "Amp"]},
            {"id": "docs", "profile": "Cheap"}
        ]});
        assert_eq!(
            stage_candidates(&policy, "impl"),
            vec!["Codex".to_string(), "Claude".to_string(), "Amp".to_string()]
        );
        assert_eq!(stage_candidates(&policy, "docs"), vec!["Cheap".to_string()]);
    }

    #[test]
    fn an_unknown_stage_or_malformed_policy_has_no_candidates() {
        let policy = json!({"stages": [{"id": "impl", "profile": "Codex"}]});
        assert!(stage_candidates(&policy, "missing").is_empty());
        assert!(stage_candidates(&json!({}), "impl").is_empty());
        assert!(stage_candidates(&json!({"stages": "nope"}), "impl").is_empty());
    }
}
