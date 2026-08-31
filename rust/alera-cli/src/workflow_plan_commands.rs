use std::io::Read;

use alera_core::runtime::{PrepareWorkflowPlan, WORKFLOW_PLAN_MAX_BYTES};
use anyhow::{bail, Result};
use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_workflow_plans::{WorkflowPlansAction, WorkflowPlansArgs};
use crate::orchestration_commands::request_value_with_capability;
use crate::terminal_host::protocol::RUNTIME_HOST_WORKFLOW_PLANS_CAPABILITY;

pub(crate) async fn run_workflow_plans(runtime: &RuntimeDirArgs, args: WorkflowPlansArgs) -> i32 {
    let (verb, payload) = match request_payload(args.action) {
        Ok(request) => request,
        Err(error) => {
            eprintln!("{error}");
            return 64;
        }
    };
    match request_value_with_capability(
        runtime,
        RUNTIME_HOST_WORKFLOW_PLANS_CAPABILITY,
        verb,
        payload,
        Some(30_000),
    )
    .await
    {
        Ok(value) => {
            println!(
                "{}",
                serde_json::to_string_pretty(&value).unwrap_or_default()
            );
            0
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn request_payload(action: WorkflowPlansAction) -> Result<(&'static str, Value)> {
    match action {
        WorkflowPlansAction::Show { run, revision } => Ok((
            "workflows.plan",
            json!({"runId": run, "revision": revision}),
        )),
        WorkflowPlansAction::Prepare { document, stdin } => {
            let document = if stdin {
                let mut bytes = Vec::new();
                std::io::stdin()
                    .lock()
                    .take((WORKFLOW_PLAN_MAX_BYTES + 1) as u64)
                    .read_to_end(&mut bytes)?;
                String::from_utf8(bytes)?
            } else {
                document.unwrap_or_default()
            };
            if document.len() > WORKFLOW_PLAN_MAX_BYTES {
                bail!("workflow plan exceeds the byte limit");
            }
            serde_json::from_str::<PrepareWorkflowPlan>(&document)
                .map_err(|_| anyhow::anyhow!("invalid workflow plan document"))?;
            Ok(("workflows.preparePlan", json!({"document": document})))
        }
    }
}

#[cfg(test)]
mod tests {
    use clap::Parser;

    #[test]
    fn workflow_plan_cli_does_not_offer_human_approval_or_signing() {
        for action in ["approve", "reject", "sign", "request-changes"] {
            assert!(
                crate::cli::Cli::try_parse_from(["alera", "orchestration", "plans", action])
                    .is_err()
            );
        }
        crate::cli::Cli::try_parse_from(["alera", "orchestration", "plans", "prepare", "--stdin"])
            .unwrap();
        assert!(
            crate::cli::Cli::try_parse_from(["alera", "orchestration", "plans", "prepare"])
                .is_err()
        );
    }
}
