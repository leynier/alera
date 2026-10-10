//! Proposals, execution control, corrections, and cleanup of workflow runs.
//! Every verb is one `workflows.*` request; none of them approves, reviews, or
//! signs a plan, which only a person does in the Alera app.

use std::collections::BTreeMap;
use std::io::Read;

use alera_core::runtime::WORKFLOW_PLAN_MAX_BYTES;
use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_workflow_plans::{
    WorkflowCleanupAction, WorkflowExecutionAction, WorkflowExecutionVerb,
    WorkflowProposalCreateArgs, WorkflowProposalsAction,
};
use crate::orchestration_commands::request_value_with_capability;
use crate::terminal_host::protocol::RUNTIME_HOST_WORKFLOW_LIFECYCLE_CAPABILITY;

const READ_DEADLINE_MS: u64 = 30_000;
/// Coordinator launches and cleanups run git and agent start-up on the host.
const LONG_DEADLINE_MS: u64 = 50_000;
const OBJECTIVE_MAX_BYTES: usize = 16_384;
const REASON_MAX_BYTES: usize = 4_096;
const CLEANUP_MAX_RESOURCES: usize = 25;

pub(crate) async fn run_proposals(
    runtime: &RuntimeDirArgs,
    action: WorkflowProposalsAction,
) -> i32 {
    let request = match action {
        WorkflowProposalsAction::Create(args) => return create_proposal(runtime, args).await,
        action => proposal_request(action),
    };
    match request {
        Ok((verb, payload, deadline)) => send(runtime, verb, payload, deadline).await,
        Err(error) => usage(error),
    }
}

async fn create_proposal(runtime: &RuntimeDirArgs, args: WorkflowProposalCreateArgs) -> i32 {
    let objective = match text(
        args.objective.clone(),
        args.objective_stdin,
        OBJECTIVE_MAX_BYTES,
    ) {
        Ok(objective) => objective,
        Err(error) => return usage(error),
    };
    // The proposal freezes the commit the source workspace is at now, exactly
    // as the desktop's New Run form does.
    let source = match request_value_with_capability(
        runtime,
        RUNTIME_HOST_WORKFLOW_LIFECYCLE_CAPABILITY,
        "workflows.source",
        json!({"workspaceId": args.workspace_id}),
        Some(READ_DEADLINE_MS),
    )
    .await
    {
        Ok(source) => source,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    match proposal_document(&args, objective, &source) {
        Ok(document) => {
            let payload = json!({"document": document});
            send(
                runtime,
                "workflows.createProposal",
                payload,
                READ_DEADLINE_MS,
            )
            .await
        }
        Err(error) => usage(error),
    }
}

pub(crate) async fn run_execution(
    runtime: &RuntimeDirArgs,
    action: WorkflowExecutionAction,
) -> i32 {
    match execution_request(action, &mut std::io::stdin().lock()) {
        Ok((verb, payload)) => send(runtime, verb, payload, READ_DEADLINE_MS).await,
        Err(error) => usage(error),
    }
}

pub(crate) async fn run_cleanup(runtime: &RuntimeDirArgs, action: WorkflowCleanupAction) -> i32 {
    match cleanup_request(action) {
        Ok((verb, payload, deadline)) => send(runtime, verb, payload, deadline).await,
        Err(error) => usage(error),
    }
}

fn proposal_request(action: WorkflowProposalsAction) -> Result<(&'static str, Value, u64)> {
    Ok(match action {
        WorkflowProposalsAction::List {
            before_created_at,
            before_id,
        } => (
            "workflows.proposals",
            json!({"beforeCreatedAt": before_created_at, "beforeId": before_id}),
            READ_DEADLINE_MS,
        ),
        WorkflowProposalsAction::Status { id } => (
            "workflows.proposalStatus",
            json!({"id": id}),
            READ_DEADLINE_MS,
        ),
        WorkflowProposalsAction::Cancel {
            id,
            expected_sequence: Some(sequence),
        } => (
            "workflows.retryProposalCancellation",
            json!({"id": id, "expectedSequence": sequence}),
            READ_DEADLINE_MS,
        ),
        WorkflowProposalsAction::Cancel { id, .. } => (
            "workflows.cancelProposal",
            json!({"id": id}),
            READ_DEADLINE_MS,
        ),
        WorkflowProposalsAction::StartCoordinator { id } => (
            "workflows.startCoordinator",
            json!({"id": id}),
            LONG_DEADLINE_MS,
        ),
        WorkflowProposalsAction::Create(_) => bail!("proposal creation needs the runtime"),
    })
}

fn proposal_document(
    args: &WorkflowProposalCreateArgs,
    objective: String,
    source: &Value,
) -> Result<String> {
    let recipe_source: Value = serde_json::from_str(&args.recipe_source)
        .map_err(|_| anyhow!("--recipe-source must be the recipe's source JSON"))?;
    let mut roles = BTreeMap::new();
    for entry in &args.role_profiles {
        let (role, profile) = entry
            .split_once('=')
            .filter(|(role, profile)| !role.is_empty() && !profile.is_empty())
            .ok_or_else(|| anyhow!("--role-profile takes role=profileId, not `{entry}`"))?;
        if roles.insert(role.to_owned(), profile.to_owned()).is_some() {
            bail!("role `{role}` has more than one --role-profile");
        }
    }
    if !source["workspace"].is_object() || !source["sha"].is_string() {
        bail!("the runtime returned no workflow source for this workspace");
    }
    let document = serde_json::to_string(&json!({
        "expectedSource": source["workspace"],
        "request": {
            "requestId": args.request_id,
            "workspaceId": args.workspace_id,
            "runId": args.run,
            "expectedRevision": args.expected_revision,
            "proposal": {
                "objective": objective,
                "sourceSha": source["sha"],
                "recipeSource": recipe_source,
                "expectedRecipeDigest": args.recipe_digest,
                "coordinatorProfileId": args.coordinator_profile_id,
                "roleProfiles": roles,
                "maxConcurrent": args.max_concurrent,
                "tasks": [],
            },
        },
    }))?;
    if document.len() > WORKFLOW_PLAN_MAX_BYTES {
        bail!("workflow proposal exceeds the byte limit");
    }
    Ok(document)
}

fn execution_request(
    action: WorkflowExecutionAction,
    stdin: &mut impl Read,
) -> Result<(&'static str, Value)> {
    Ok(match action {
        WorkflowExecutionAction::Show { run, revision } => (
            "workflows.execution",
            json!({"runId": run, "revision": revision}),
        ),
        WorkflowExecutionAction::Control {
            run,
            revision,
            expected_sequence,
            action,
            request_id,
        } => {
            let action = match action {
                WorkflowExecutionVerb::Start => "start",
                WorkflowExecutionVerb::Pause => "pause",
                WorkflowExecutionVerb::Cancel => "cancel",
            };
            let document = json!({
                "requestId": request_id,
                "runId": run,
                "revision": revision,
                "expectedSequence": expected_sequence,
                "action": action,
            });
            (
                "workflows.controlExecution",
                json!({"document": document.to_string()}),
            )
        }
        WorkflowExecutionAction::Correct {
            run,
            revision,
            plan_digest,
            request_id,
            reason,
            reason_stdin,
        } => {
            let reason = match reason {
                Some(reason) => reason,
                None if reason_stdin => read_limited(stdin, REASON_MAX_BYTES)?,
                None => bail!("--reason or --reason-stdin is required"),
            };
            if reason.trim().is_empty() || reason.len() > REASON_MAX_BYTES {
                bail!("give a reason of at most {REASON_MAX_BYTES} bytes");
            }
            let document = json!({
                "requestId": request_id,
                "runId": run,
                "revision": revision,
                "planDigest": plan_digest,
                "reason": reason,
            });
            (
                "workflows.createCorrection",
                json!({"document": document.to_string()}),
            )
        }
    })
}

fn cleanup_request(action: WorkflowCleanupAction) -> Result<(&'static str, Value, u64)> {
    Ok(match action {
        WorkflowCleanupAction::Resources { run, before_row } => (
            "workflows.cleanupResources",
            json!({"runId": run, "beforeRow": before_row}),
            READ_DEADLINE_MS,
        ),
        WorkflowCleanupAction::List { run, before_row } => (
            "workflows.cleanups",
            json!({"runId": run, "beforeRow": before_row}),
            READ_DEADLINE_MS,
        ),
        WorkflowCleanupAction::Preview {
            run,
            workspaces,
            remove_branches,
            id,
        } => {
            if workspaces.is_empty() || workspaces.len() > CLEANUP_MAX_RESOURCES {
                bail!("select between one and {CLEANUP_MAX_RESOURCES} workspaces");
            }
            if let Some(stray) = remove_branches.iter().find(|id| !workspaces.contains(id)) {
                bail!("--remove-branch {stray} is not one of the selected workspaces");
            }
            let resources: Vec<Value> = workspaces
                .iter()
                .map(|workspace| {
                    json!({
                        "workspaceId": workspace,
                        "removeBranch": remove_branches.contains(workspace),
                    })
                })
                .collect();
            let id = id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
            let document = json!({"id": id, "runId": run, "resources": resources});
            (
                "workflows.previewCleanup",
                json!({"document": document.to_string()}),
                READ_DEADLINE_MS,
            )
        }
        WorkflowCleanupAction::Status { id } => (
            "workflows.cleanupStatus",
            json!({"id": id}),
            READ_DEADLINE_MS,
        ),
        WorkflowCleanupAction::Apply(confirm) => (
            "workflows.applyCleanup",
            json!({"id": confirm.id, "digest": confirm.digest}),
            LONG_DEADLINE_MS,
        ),
        WorkflowCleanupAction::Retry(confirm) => (
            "workflows.retryCleanup",
            json!({"id": confirm.id, "digest": confirm.digest}),
            LONG_DEADLINE_MS,
        ),
        WorkflowCleanupAction::Abandon(confirm) => (
            "workflows.abandonCleanup",
            json!({"id": confirm.id, "digest": confirm.digest}),
            LONG_DEADLINE_MS,
        ),
    })
}

fn text(inline: Option<String>, from_stdin: bool, max_bytes: usize) -> Result<String> {
    let value = match inline {
        Some(value) => value,
        None if from_stdin => read_limited(&mut std::io::stdin().lock(), max_bytes)?,
        None => bail!("the text is required"),
    };
    if value.trim().is_empty() || value.len() > max_bytes || value.contains('\0') {
        bail!("give a text of at most {max_bytes} bytes");
    }
    Ok(value)
}

fn read_limited(stdin: &mut impl Read, max_bytes: usize) -> Result<String> {
    let mut bytes = Vec::new();
    stdin.take(max_bytes as u64 + 1).read_to_end(&mut bytes)?;
    Ok(String::from_utf8(bytes)?)
}

async fn send(runtime: &RuntimeDirArgs, verb: &str, payload: Value, deadline_ms: u64) -> i32 {
    match request_value_with_capability(
        runtime,
        RUNTIME_HOST_WORKFLOW_LIFECYCLE_CAPABILITY,
        verb,
        payload,
        Some(deadline_ms),
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

fn usage(error: anyhow::Error) -> i32 {
    eprintln!("{error}");
    crate::USAGE_EXIT_CODE
}

#[cfg(test)]
#[path = "lifecycle_tests.rs"]
mod tests;
