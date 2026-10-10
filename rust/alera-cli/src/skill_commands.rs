//! `alera skill`: the Alera skills coding agents use, on this machine.
//!
//! The install runs as a runtime job, so it finishes even when this command
//! stops waiting for it.

use anyhow::{Context, Result};
use serde_json::{json, Value};

use crate::agent_profile_commands::ensure_capabilities;
use crate::cli::{SkillAction, SkillCommand, SkillInstallArgs, SkillName, SkillRunnerName};
use crate::host_tools::SkillKind;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_AGENT_SKILL_INSTALL_JOBS_CAPABILITY;

const INSTALL_RUNNING: &str = "already running";

pub(crate) async fn run(command: SkillCommand) -> i32 {
    let json_output = command.output.json;
    match run_command(command).await {
        Ok((value, message, succeeded)) => {
            crate::print_value(&value, json_output, message);
            if succeeded {
                0
            } else {
                1
            }
        }
        Err(error) => crate::print_error(error),
    }
}

async fn run_command(command: SkillCommand) -> Result<(Value, &'static str, bool)> {
    let home = dirs::home_dir().context("This machine has no home directory")?;
    let runtime_dir = crate::runtime_dir(&command.runtime);
    match command.action {
        SkillAction::Status => {
            let mut value = crate::agent_skills::status(&home);
            // A runtime that is not running has no install in progress.
            if let Ok(Some(mut client)) = RuntimeHostRpcClient::connect(&runtime_dir).await {
                if let Ok(state) = client.request_value("agentSkill.state", &json!({})).await {
                    value["install"] = state;
                }
            }
            Ok((value, "agent skills", true))
        }
        SkillAction::Install(args) => {
            let mut client = RuntimeHostRpcClient::connect_or_start(&runtime_dir).await?;
            ensure_capabilities(
                &mut client,
                &[RUNTIME_HOST_AGENT_SKILL_INSTALL_JOBS_CAPABILITY],
            )
            .await?;
            let operation_id = uuid::Uuid::new_v4().to_string();
            let wait_ms = args.wait_seconds.saturating_mul(1000);
            let answer = client
                .request_value_with_deadline(
                    "agentSkill.install",
                    &install_payload(&operation_id, &args),
                    wait_ms,
                )
                .await;
            let (mut value, message, succeeded) = match answer {
                Ok(mut result) => {
                    let succeeded = result["succeeded"] == true;
                    result["state"] = json!(if succeeded { "completed" } else { "failed" });
                    let message = if succeeded {
                        "agent skills installed"
                    } else {
                        "agent skill install failed"
                    };
                    (result, message, succeeded)
                }
                Err(error) if still_running(&error.to_string()) => (
                    running_answer(&operation_id),
                    "agent skill install still running",
                    true,
                ),
                Err(error) => return Err(error),
            };
            value["status"] = crate::agent_skills::status(&home);
            Ok((value, message, succeeded))
        }
    }
}

fn install_payload(operation_id: &str, args: &SkillInstallArgs) -> Value {
    let skills = if args.skills.is_empty() {
        SkillKind::ALL.to_vec()
    } else {
        args.skills.iter().copied().map(skill_kind).collect()
    };
    json!({
        "operationId": operation_id,
        "skills": skills.iter().map(|kind| kind.id()).collect::<Vec<_>>(),
        "runner": runner_name(args.runner),
    })
}

/// The wait ended first, or another request's install is still running.
/// Either way the runtime finishes it, and `skill status` shows the result.
fn still_running(message: &str) -> bool {
    message.contains("did not answer") || message.contains(INSTALL_RUNNING)
}

fn running_answer(operation_id: &str) -> Value {
    json!({
        "state": "running",
        "operationId": operation_id,
        "message": "The install is still running on the runtime. Run `alera skill status` (check_agent_skills) later: `install.running` is null once it has finished, and `install.last` has its result. Do not start another install meanwhile.",
    })
}

fn skill_kind(name: SkillName) -> SkillKind {
    match name {
        SkillName::Cli => SkillKind::Cli,
        SkillName::Orchestration => SkillKind::Orchestration,
        SkillName::Automations => SkillKind::Automations,
        SkillName::AgentProfiles => SkillKind::AgentProfiles,
    }
}

fn runner_name(runner: SkillRunnerName) -> &'static str {
    match runner {
        SkillRunnerName::Auto => "auto",
        SkillRunnerName::Npx => "npx",
        SkillRunnerName::Bunx => "bunx",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_install_names_every_skill_unless_some_are_given() {
        let all = SkillInstallArgs {
            skills: Vec::new(),
            runner: SkillRunnerName::Auto,
            wait_seconds: 45,
        };
        assert_eq!(
            install_payload("op", &all),
            json!({
                "operationId": "op",
                "skills": ["cli", "orchestration", "automations", "agentProfiles"],
                "runner": "auto",
            })
        );
        let some = SkillInstallArgs {
            skills: vec![SkillName::AgentProfiles],
            runner: SkillRunnerName::Bunx,
            wait_seconds: 45,
        };
        assert_eq!(
            install_payload("op", &some)["skills"],
            json!(["agentProfiles"])
        );
        assert_eq!(install_payload("op", &some)["runner"], "bunx");
    }

    #[test]
    fn a_wait_that_ends_first_or_a_running_install_is_reported_as_running() {
        assert!(still_running(
            "runtime host did not answer agentSkill.install within 45000ms"
        ));
        assert!(still_running("An agent skill install is already running."));
        assert!(!still_running("runner must be auto, npx, or bunx."));
        assert_eq!(running_answer("op")["state"], "running");
    }
}
