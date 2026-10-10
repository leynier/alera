//! `alera skill`: the Alera skills coding agents use, on this machine.

use anyhow::{Context, Result};
use serde_json::Value;

use crate::cli::{SkillAction, SkillCommand, SkillName, SkillRunnerName};
use crate::host_tools::{install_skills, SkillKind, SkillRunner};

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
    match command.action {
        SkillAction::Status => Ok((crate::agent_skills::status(&home), "agent skills", true)),
        SkillAction::Install(args) => {
            let kinds = if args.skills.is_empty() {
                SkillKind::ALL.to_vec()
            } else {
                args.skills.iter().copied().map(skill_kind).collect()
            };
            let result = install_skills(&kinds, runner(args.runner)).await;
            let succeeded = result.succeeded;
            let mut value = serde_json::to_value(&result)?;
            if succeeded && kinds.contains(&SkillKind::Orchestration) {
                // As the app does after installing orchestration: the hooks
                // that report agent status are part of that contract.
                value["hookWarnings"] = reconcile_hooks(&command.runtime).await.into();
            }
            value["status"] = crate::agent_skills::status(&home);
            let message = if succeeded {
                "agent skills installed"
            } else {
                "agent skill install failed"
            };
            Ok((value, message, succeeded))
        }
    }
}

async fn reconcile_hooks(runtime: &crate::cli::RuntimeDirArgs) -> Vec<String> {
    let runtime_dir = crate::runtime_dir(runtime);
    let settings = match alera_core::runtime::RuntimeStore::open(&runtime_dir).await {
        Ok(store) => store.agent_status_hook_settings().await,
        Err(error) => Err(error),
    };
    match settings {
        Ok(settings) => tokio::task::spawn_blocking(move || {
            crate::agent_status::reconcile_agent_integrations(&runtime_dir, &settings)
        })
        .await
        .unwrap_or_else(|error| vec![error.to_string()]),
        Err(error) => vec![error.to_string()],
    }
}

fn skill_kind(name: SkillName) -> SkillKind {
    match name {
        SkillName::Cli => SkillKind::Cli,
        SkillName::Orchestration => SkillKind::Orchestration,
        SkillName::Automations => SkillKind::Automations,
        SkillName::AgentProfiles => SkillKind::AgentProfiles,
    }
}

fn runner(name: SkillRunnerName) -> SkillRunner {
    match name {
        SkillRunnerName::Auto => SkillRunner::Auto,
        SkillRunnerName::Npx => SkillRunner::Npx,
        SkillRunnerName::Bunx => SkillRunner::Bunx,
    }
}
