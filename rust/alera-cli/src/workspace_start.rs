use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::agent_profile_commands::print_json;
use crate::agent_profile_launch::{launch_profile, resolve_selected_profile};
use crate::cli::{RuntimeDirArgs, WorkspaceStartArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::ai_assist_capabilities::RUNTIME_HOST_AI_ASSIST_WORKSPACE_IDENTITY_CAPABILITY;
use crate::terminal_host::protocol::RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY;
use crate::workspace_context::{resolve_optional_workspace_context, WorkspaceContext};

const IDENTITY_GENERATE_TIMEOUT_MS: u64 = 11 * 60 * 1000;

#[derive(Debug, Clone)]
pub struct InferredWorkspaceCreate {
    pub id: Option<String>,
    pub project_id: Option<String>,
    pub branch: Option<String>,
    pub source_branch: Option<String>,
    pub name: Option<String>,
    pub workspace_root: Option<String>,
    pub path: Option<String>,
    pub parent_workspace_id: Option<String>,
    pub no_parent: bool,
    pub from_workspace: Option<String>,
}

pub async fn run(runtime: RuntimeDirArgs, args: WorkspaceStartArgs, json_output: bool) -> i32 {
    match run_inner(&runtime, args, json_output).await {
        Ok(true) => 0,
        Ok(false) => 1,
        Err(error) => crate::print_error(error),
    }
}

async fn run_inner(
    runtime: &RuntimeDirArgs,
    args: WorkspaceStartArgs,
    json_output: bool,
) -> Result<bool> {
    let prompt = args.prompt.read()?;
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    )
    .await?;
    let profile = resolve_selected_profile(&mut client, &args.selector).await?;
    let created = create_inferred_workspace(
        runtime,
        &mut client,
        InferredWorkspaceCreate {
            id: args.id,
            project_id: args.project_id,
            branch: args.branch,
            source_branch: args.source_branch,
            name: args.name,
            workspace_root: args.workspace_root,
            path: args.path,
            parent_workspace_id: args.parent_workspace_id,
            no_parent: args.no_parent,
            from_workspace: args.workspace,
        },
        &prompt,
    )
    .await?;
    let workspace = created
        .get("workspace")
        .cloned()
        .ok_or_else(|| anyhow!("workspace create returned no workspace"))?;
    let workspace_id = workspace
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("workspace create returned no workspace id"))?
        .to_string();
    let launch = launch_profile(
        &mut client,
        &workspace_id,
        &profile.id,
        &profile.name,
        &prompt,
        args.client_mutation_id,
    )
    .await;
    let mut envelope = json!({
        "workspaceId": workspace_id,
        "projectId": workspace.get("projectId"),
        "branch": workspace.get("branch"),
        "path": workspace.get("path"),
        "name": workspace.get("name"),
        "workspace": workspace,
    });
    match launch {
        Ok(launch) => {
            envelope
                .as_object_mut()
                .expect("envelope is an object")
                .extend(launch.to_value().as_object().cloned().unwrap_or_default());
            if json_output {
                print_json(&envelope)?;
            } else {
                println!(
                    "workspace started: {} ({}) with {} (tab {})",
                    envelope["name"].as_str().unwrap_or("workspace"),
                    workspace_id,
                    launch.profile_name,
                    launch.tab_id
                );
            }
            Ok(true)
        }
        Err(error) => {
            envelope["launchError"] = json!(error.to_string());
            if json_output {
                print_json(&envelope)?;
            } else {
                eprintln!(
                    "workspace created: {workspace_id}, but the agent profile did not launch: {error}"
                );
            }
            Ok(false)
        }
    }
}

pub async fn create_inferred_workspace(
    runtime: &RuntimeDirArgs,
    client: &mut RuntimeHostRpcClient,
    request: InferredWorkspaceCreate,
    prompt_for_identity: &str,
) -> Result<Value> {
    let context = if needs_workspace_context(&request) {
        resolve_optional_workspace_context(runtime, request.from_workspace.as_deref()).await?
    } else {
        None
    };
    let project_id = first_non_empty([
        request.project_id.as_deref(),
        context.as_ref().map(|value| value.project_id.as_str()),
    ])
    .ok_or_else(|| {
        anyhow!(
            "--project-id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
        )
    })?;
    let source_branch = first_non_empty([
        request.source_branch.as_deref(),
        context.as_ref().and_then(WorkspaceContext::source_branch),
    ]);
    let parent_workspace_id = if request.no_parent {
        None
    } else {
        first_non_empty([
            request.parent_workspace_id.as_deref(),
            context.as_ref().map(|value| value.workspace_id.as_str()),
        ])
    };
    let (branch, name) = resolve_identity(
        client,
        &project_id,
        prompt_for_identity,
        request.branch,
        request.name,
    )
    .await?;
    let source_branch = source_branch.ok_or_else(|| {
        anyhow!("--source-branch is required (or run inside a workspace that has a branch).")
    })?;
    let payload = json!({
        "id": request.id,
        "projectId": project_id,
        "name": name,
        "branch": branch,
        "sourceBranch": source_branch,
        "reuseExistingBranch": false,
        "workspaceRoot": crate::host_accessible_optional_string_path(request.workspace_root)?,
        "path": crate::host_accessible_optional_string_path(request.path)?,
        "parentWorkspaceId": parent_workspace_id,
    });
    client
        .request_value("workspace.createManaged", &payload)
        .await
        .context("could not create managed workspace")
}

async fn resolve_identity(
    client: &mut RuntimeHostRpcClient,
    project_id: &str,
    prompt: &str,
    branch: Option<String>,
    name: Option<String>,
) -> Result<(String, String)> {
    let mut branch = nonempty(branch);
    let mut name = nonempty(name);
    if branch.is_some() && name.is_some() {
        return Ok((branch.unwrap(), name.unwrap()));
    }
    match generate_identity(client, project_id, prompt).await {
        Ok((generated_name, generated_branch)) => {
            if branch.is_none() {
                branch = Some(generated_branch);
            }
            if name.is_none() {
                name = Some(generated_name);
            }
        }
        Err(error) if branch.is_none() => {
            bail!("--branch is required because workspace identity generation failed: {error}");
        }
        Err(_) => {}
    }
    let branch = branch.expect("branch is present after generation or the error above");
    Ok((branch.clone(), name.unwrap_or(branch)))
}

async fn generate_identity(
    client: &mut RuntimeHostRpcClient,
    project_id: &str,
    prompt: &str,
) -> Result<(String, String)> {
    crate::agent_profile_commands::ensure_capabilities(
        client,
        &[RUNTIME_HOST_AI_ASSIST_WORKSPACE_IDENTITY_CAPABILITY],
    )
    .await?;
    let payload = client
        .request_value_with_deadline(
            "aiText.workspaceIdentity.generate",
            &json!({
                "operationId": Uuid::new_v4().to_string(),
                "projectId": project_id,
                "prompt": prompt,
            }),
            IDENTITY_GENERATE_TIMEOUT_MS,
        )
        .await?;
    let workspace_name = payload
        .get("workspaceName")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("workspace identity generation returned no workspaceName"))?;
    let branch_name = payload
        .get("branchName")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("workspace identity generation returned no branchName"))?;
    Ok((workspace_name.to_string(), branch_name.to_string()))
}

fn needs_workspace_context(request: &InferredWorkspaceCreate) -> bool {
    first_non_empty([request.project_id.as_deref()]).is_none()
        || first_non_empty([request.source_branch.as_deref()]).is_none()
        || (!request.no_parent
            && first_non_empty([request.parent_workspace_id.as_deref()]).is_none())
}

fn nonempty(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn first_non_empty<'a>(values: impl IntoIterator<Item = Option<&'a str>>) -> Option<String> {
    values.into_iter().find_map(|value| {
        value
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string)
    })
}
