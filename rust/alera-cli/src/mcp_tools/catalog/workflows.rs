//! Workflow recipes, proposals, plans, execution, and cleanup without human
//! decisions: approving or rejecting a plan, reviews, and signed decisions
//! stay in the Alera app, and no tool here reaches them.

mod execution;
#[cfg(test)]
mod tests;

use alera_core::runtime::{WORKFLOW_DOCUMENT_MAX_BYTES, WORKFLOW_PLAN_MAX_BYTES};
use serde_json::{json, Value};

use super::{execute, read, LAUNCH_TIMEOUT};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec, CLIENT_REQUEST_ID};

const RECIPE_LIMIT: u64 = WORKFLOW_DOCUMENT_MAX_BYTES as u64;
const PLAN_LIMIT: u64 = WORKFLOW_PLAN_MAX_BYTES as u64;
const OBJECTIVE_LIMIT: u64 = 16_384;
const REQUEST_FLAG: &str = "--request-id";

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = recipes();
    tools.extend(proposals());
    tools.extend(execution::tools());
    tools
}

fn recipes() -> Vec<ToolSpec> {
    vec![
        read(
            "list_recipes",
            "List Workflow Recipes",
            "List built-in and personal workflow recipes, plus a workspace's project recipes when workspaceId is given.",
            || object(&[("workspaceId", string("Workspace whose project recipes to include."))], &[]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["recipes", "list"])
                    .option_if("--workspace", arguments.string("workspaceId")))
            },
        ),
        read(
            "show_recipe",
            "Show Workflow Recipe",
            "Show one workflow recipe with its digest, roles, and stages. Name it as list_recipes reports its source.",
            || object(&recipe_source_properties(""), &["origin", "id"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["recipes", "show"])
                    .option("--source", recipe_source(arguments, "", None)?.to_string()))
            },
        ),
        read(
            "validate_recipe",
            "Validate Workflow Recipe",
            "Check a portable workflow recipe (YAML) without saving or running it. Returns its digest and stage order.",
            || object(&[("document", text("Recipe YAML.", RECIPE_LIMIT))], &["document"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["recipes", "validate", "--stdin"])
                    .stdin(arguments.required("document")?))
            },
        ),
        execute(
            "save_personal_recipe",
            "Save Personal Recipe",
            "Create or update a personal workflow recipe from YAML. Updating one needs its current catalog revision.",
            || {
                object(
                    &[
                        ("document", text("Recipe YAML.", RECIPE_LIMIT)),
                        ("expectedRevision", integer("Catalog revision of the recipe being replaced.", 1, u64::MAX >> 11)),
                    ],
                    &["document"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["recipes", "save-personal", "--stdin"])
                    .option_if("--expected-revision", arguments.integer("expectedRevision").map(|value| value.to_string()))
                    .stdin(arguments.required("document")?))
            },
        ),
        read(
            "preview_recipe_export",
            "Preview Recipe Export",
            "Preview writing a recipe into a workspace's project catalog (.alera/workflows). Returns the file before and after and the digest export_recipe needs.",
            export_schema,
            |arguments| export(arguments, false),
        ),
        execute(
            "export_recipe",
            "Export Recipe",
            "Write a recipe into a workspace's project catalog after preview_recipe_export. Fails if the file or document changed since the preview.",
            || {
                let mut schema = export_schema();
                schema["properties"]["expectedDigest"] = string("Digest from preview_recipe_export.");
                schema["required"] = json!(["workspaceId", "filename", "document", "expectedDigest"]);
                schema
            },
            |arguments| export(arguments, true),
        ),
    ]
}

fn proposals() -> Vec<ToolSpec> {
    vec![
        read(
            "list_workflow_proposals",
            "List Workflow Proposals",
            "List workflow proposals, newest first, with their coordinator and cancellation state.",
            || {
                object(
                    &[
                        ("beforeCreatedAt", string("createdAt of the last entry of the previous page.")),
                        ("beforeId", string("id of the last entry of the previous page.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                let (created, id) = (arguments.string("beforeCreatedAt"), arguments.string("beforeId"));
                if created.is_some() != id.is_some() {
                    return Err(ToolInputError("Pass beforeCreatedAt and beforeId together.".into()));
                }
                Ok(Invocation::new("orchestration", &["proposals", "list"])
                    .option_if("--before-created-at", created)
                    .option_if("--before-id", id))
            },
        ),
        read(
            "get_workflow_proposal",
            "Get Workflow Proposal",
            "Show a workflow proposal's lifecycle state, or with frozenSelection its frozen recipe, profiles, and source.",
            || {
                object(
                    &[
                        ("proposalId", string("Proposal id.")),
                        ("frozenSelection", boolean("Return the frozen selection instead of the lifecycle state.")),
                    ],
                    &["proposalId"],
                )
            },
            |arguments| {
                let id = arguments.required("proposalId")?;
                Ok(if arguments.flag("frozenSelection") {
                    Invocation::new("orchestration", &["plans", "proposal"]).option("--id", id)
                } else {
                    Invocation::new("orchestration", &["proposals", "status"]).option("--id", id)
                })
            },
        ),
        ToolSpec {
            client_request_flag: Some(REQUEST_FLAG),
            ..execute(
                "create_workflow_proposal",
                "Create Workflow Proposal",
                "Propose a workflow run from a recipe at the source workspace's current commit. Start its coordinator with start_workflow_coordinator; a person approves the plan in the Alera app.",
                || {
                    let mut properties = vec![
                        ("workspaceId", string("Active local Git workspace the workflow starts from.")),
                        ("objective", text("What the workflow should achieve.", OBJECTIVE_LIMIT)),
                        ("recipeDigest", string("Recipe digest from show_recipe.")),
                        ("coordinatorProfileId", string("Agent profile id for the coordinator, from list_agent_profiles.")),
                        ("roleProfiles", string_items("Agent profile per recipe role, each as role=profileId.")),
                        ("maxConcurrent", integer("Workers that may run at once (default 4).", 1, 16)),
                        ("runId", string("Revise this existing run instead of starting a new one.")),
                        ("expectedRevision", integer("Current revision of runId.", 1, u64::MAX >> 11)),
                    ];
                    properties.extend(recipe_source_properties("recipe"));
                    object(
                        &properties,
                        &["workspaceId", "objective", "recipeOrigin", "recipeId", "recipeDigest", "coordinatorProfileId"],
                    )
                },
                create_proposal,
            )
        },
        execute(
            "submit_workflow_proposal",
            "Submit Workflow Proposal Tasks",
            "Submit the concrete task list for a proposal, as its coordinator would. Does not approve the plan or start workers.",
            || {
                object(
                    &[
                        ("proposalId", string("Proposal id.")),
                        ("tasks", text("JSON array of plan tasks (id, title, spec, stageId, roleId, dependsOn, inputs, correctsTaskId).", PLAN_LIMIT)),
                    ],
                    &["proposalId", "tasks"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["plans", "submit-proposal", "--stdin"])
                    .option("--id", arguments.required("proposalId")?)
                    .stdin(arguments.required("tasks")?))
            },
        ),
        ToolSpec {
            destructive: true,
            idempotent: true,
            ..execute(
                "cancel_workflow_proposal",
                "Cancel Workflow Proposal",
                "Cancel a workflow proposal and its coordinator. Pass expectedSequence to retry a cancellation that did not finish.",
                || {
                    object(
                        &[
                            ("proposalId", string("Proposal id.")),
                            ("expectedSequence", integer("Cancellation sequence from get_workflow_proposal, to retry it.", 0, u64::MAX >> 11)),
                        ],
                        &["proposalId"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("orchestration", &["proposals", "cancel"])
                        .option("--id", arguments.required("proposalId")?)
                        .option_if("--expected-sequence", arguments.integer("expectedSequence").map(|value| value.to_string())))
                },
            )
        },
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "start_workflow_coordinator",
                "Start Workflow Coordinator",
                "Start the coordinator agent of a workflow proposal. The coordinator drafts the plan; it does not approve it.",
                || object(&[("proposalId", string("Proposal id."))], &["proposalId"]),
                |arguments| {
                    Ok(Invocation::new("orchestration", &["proposals", "start-coordinator"])
                        .option("--id", arguments.required("proposalId")?))
                },
            )
        },
        execute(
            "prepare_workflow_plan",
            "Prepare Workflow Plan",
            "Prepare a durable workflow plan for review from a PrepareWorkflowPlan JSON document with a stable requestId. Starts no workers; a person approves it in the Alera app.",
            || object(&[("document", text("PrepareWorkflowPlan JSON document.", PLAN_LIMIT))], &["document"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["plans", "prepare", "--stdin"])
                    .stdin(arguments.required("document")?))
            },
        ),
        read(
            "show_workflow_plan",
            "Show Workflow Plan",
            "Show the current or a past revision of a workflow run's plan, with its digest, tasks, and frozen profiles.",
            || {
                object(
                    &[
                        ("runId", string("Workflow run id.")),
                        ("revision", integer("Plan revision (default current).", 1, u64::MAX >> 11)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["plans", "show"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--revision", arguments.integer("revision").map(|value| value.to_string())))
            },
        ),
    ]
}

fn create_proposal(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    if arguments.string("runId").is_some() != arguments.integer("expectedRevision").is_some() {
        return Err(ToolInputError(
            "Pass runId and expectedRevision together.".into(),
        ));
    }
    let invocation = Invocation::new(
        "orchestration",
        &["proposals", "create", "--objective-stdin"],
    )
    .option("--workspace-id", arguments.required("workspaceId")?)
    .option(
        "--recipe-source",
        recipe_source(arguments, "recipe", arguments.string("workspaceId"))?.to_string(),
    )
    .option("--recipe-digest", arguments.required("recipeDigest")?)
    .option(
        "--coordinator-profile-id",
        arguments.required("coordinatorProfileId")?,
    )
    .option_if(
        "--max-concurrent",
        arguments
            .integer("maxConcurrent")
            .map(|value| value.to_string()),
    )
    .option_if("--run", arguments.string("runId"))
    .option_if(
        "--expected-revision",
        arguments
            .integer("expectedRevision")
            .map(|value| value.to_string()),
    );
    let invocation = arguments
        .list("roleProfiles")
        .unwrap_or_default()
        .into_iter()
        .fold(invocation, |invocation, role| {
            invocation.option("--role-profile", role)
        });
    Ok(with_request_id(invocation, arguments).stdin(arguments.required("objective")?))
}

fn export_schema() -> Value {
    object(
        &[
            (
                "workspaceId",
                string("Active local Git workspace whose project receives the recipe."),
            ),
            (
                "filename",
                string("File name such as release.yaml, inside .alera/workflows."),
            ),
            ("document", text("Recipe YAML.", RECIPE_LIMIT)),
        ],
        &["workspaceId", "filename", "document"],
    )
}

fn export(arguments: &ToolArguments, apply: bool) -> Result<Invocation, ToolInputError> {
    let invocation = Invocation::new("orchestration", &["recipes", "export", "--stdin"])
        .option("--workspace-id", arguments.required("workspaceId")?)
        .option("--filename", arguments.required("filename")?);
    let invocation = if apply {
        invocation
            .option("--expected-digest", arguments.required("expectedDigest")?)
            .flag("--apply")
    } else {
        invocation
    };
    Ok(invocation.stdin(arguments.required("document")?))
}

/// The recipe source properties, prefixed (`recipeOrigin`) or bare (`origin`).
fn recipe_source_properties(prefix: &str) -> Vec<(&'static str, Value)> {
    let names = source_names(prefix);
    vec![
        (
            names[0],
            one_of(
                "Where the recipe lives, as list_recipes reports it.",
                &["builtIn", "personal", "project"],
            ),
        ),
        (
            names[1],
            string("Recipe id, or for a project recipe its path, as list_recipes reports them."),
        ),
        (names[2], string("Workspace of a project recipe.")),
    ]
}

fn source_names(prefix: &str) -> [&'static str; 3] {
    if prefix.is_empty() {
        ["origin", "id", "workspaceId"]
    } else {
        ["recipeOrigin", "recipeId", "recipeWorkspaceId"]
    }
}

/// `{origin, id}`, or `{origin, workspaceId, path}` for a project recipe,
/// whose workspace defaults to `default_workspace`.
fn recipe_source(
    arguments: &ToolArguments,
    prefix: &str,
    default_workspace: Option<String>,
) -> Result<Value, ToolInputError> {
    let names = source_names(prefix);
    let origin = arguments.required(names[0])?;
    let id = arguments.required(names[1])?;
    if origin != "project" {
        return Ok(json!({ "origin": origin, "id": id }));
    }
    let workspace = arguments
        .string(names[2])
        .or(default_workspace)
        .ok_or_else(|| ToolInputError(format!("A project recipe needs `{}`.", names[2])))?;
    Ok(json!({ "origin": origin, "workspaceId": workspace, "path": id }))
}

/// An array of free-form strings.
fn string_items(description: &str) -> Value {
    json!({
        "type": "array",
        "items": { "type": "string", "minLength": 1 },
        "minItems": 1,
        "uniqueItems": true,
        "description": description,
    })
}

/// Commands that dedupe by `--request-id` require one. Without a
/// clientRequestId the call gets a fresh key, so it is not deduplicated.
fn with_request_id(invocation: Invocation, arguments: &ToolArguments) -> Invocation {
    if arguments.string(CLIENT_REQUEST_ID).is_some() {
        invocation
    } else {
        invocation.option(REQUEST_FLAG, format!("mcp-{}", uuid::Uuid::new_v4()))
    }
}
