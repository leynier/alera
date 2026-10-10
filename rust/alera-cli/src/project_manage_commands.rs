//! `alera project rename | clone | remove-preview | branches | config`: thin
//! clients of the host verbs the app's project dialogs use.

use std::io::Read as _;

use anyhow::{anyhow, bail, Result};
use serde_json::{json, Map, Value};

use crate::cli::{
    ProjectAction, ProjectCloneAction, ProjectConfigAction, ProjectConfigSetArgs, RuntimeDirArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;

/// A config is a handful of commands and copy rules, like the host's cap on a
/// remote `alera.toml`.
const MAX_CONFIG_BYTES: usize = 64 * 1024;
/// Listing branches on an SSH host runs a command there.
const BRANCHES_DEADLINE_MS: u64 = 60_000;

pub(super) async fn run(runtime: &RuntimeDirArgs, action: ProjectAction, json_output: bool) -> i32 {
    let result = async {
        let mut client = crate::runtime_host_required(runtime).await?;
        execute(&mut client, action).await
    }
    .await;
    match result {
        Ok((value, message)) => {
            crate::print_value(&value, json_output, &message);
            0
        }
        Err(error) => crate::print_error(error),
    }
}

pub(crate) async fn execute(
    client: &mut RuntimeHostRpcClient,
    action: ProjectAction,
) -> Result<(Value, String)> {
    Ok(match action {
        ProjectAction::Rename(args) => (
            client
                .request_value(
                    "project.rename",
                    &json!({"id": args.id, "name": args.name.trim()}),
                )
                .await?,
            "project renamed".into(),
        ),
        ProjectAction::Clone(command) => clone(client, command.action).await?,
        ProjectAction::RemovePreview(args) => {
            let mut preview = client
                .request_value("project.remove.preview", &json!({"id": args.id}))
                .await?;
            preview["automations"] = client
                .request_value("project.removalDependencies", &json!({"id": args.id}))
                .await?;
            // Removing a project never deletes files: its folder and every
            // worktree stay on disk.
            preview["filesDeleted"] = json!(false);
            (preview, "project removal previewed".into())
        }
        ProjectAction::Branches(args) => {
            let mut catalog = client
                .request_value_with_deadline(
                    "project.branches.list",
                    &json!({"projectId": args.project_id, "hostId": args.host_id}),
                    BRANCHES_DEADLINE_MS,
                )
                .await?;
            let config = client
                .request_value(
                    "projectConfig.effective",
                    &json!({"projectId": args.project_id}),
                )
                .await
                .unwrap_or(Value::Null);
            catalog["preferredSourceBranch"] = config["config"]["newWorkspace"]["sourceBranch"]
                .as_str()
                .filter(|branch| !branch.trim().is_empty())
                .map_or(Value::Null, |branch| json!(branch));
            (catalog, "project branches listed".into())
        }
        ProjectAction::Config(command) => match command.action {
            ProjectConfigAction::Show(args) => (
                show_config(client, &args.project_id).await?,
                "project settings".into(),
            ),
            ProjectConfigAction::Set(args) => (
                set_config(client, args).await?,
                "project settings saved".into(),
            ),
            ProjectConfigAction::Remove(args) => {
                client
                    .request_value(
                        "projectConfig.remove",
                        &json!({"projectId": args.project_id}),
                    )
                    .await?;
                (
                    show_config(client, &args.project_id).await?,
                    "project settings reset".into(),
                )
            }
        },
        _ => bail!("Unsupported project action"),
    })
}

async fn clone(
    client: &mut RuntimeHostRpcClient,
    action: ProjectCloneAction,
) -> Result<(Value, String)> {
    Ok(match action {
        ProjectCloneAction::Start(args) => {
            let directory_name = match args.directory_name {
                Some(name) => name,
                None => repository_name(&args.url)?,
            };
            (
                client
                    .request_value(
                        "project.clone.start",
                        &json!({
                            "url": args.url, "parentPath": args.parent_path,
                            "directoryName": directory_name, "name": args.name,
                        }),
                    )
                    .await?,
                "project clone started".into(),
            )
        }
        ProjectCloneAction::List => {
            let jobs = client
                .request_value("project.clone.list", &json!({}))
                .await?;
            (
                json!({"kind": "projectClones", "items": jobs}),
                "project clones listed".into(),
            )
        }
        ProjectCloneAction::Show(args) => {
            let jobs = client
                .request_value("project.clone.list", &json!({}))
                .await?;
            let job = jobs
                .as_array()
                .into_iter()
                .flatten()
                .find(|job| job["id"] == args.id.as_str())
                .cloned()
                .ok_or_else(|| anyhow!("Clone job not found: {}", args.id))?;
            (job, "project clone".into())
        }
        ProjectCloneAction::Cancel(args) => (
            client
                .request_value("project.clone.cancel", &json!({"id": args.id}))
                .await?,
            "project clone cancelling".into(),
        ),
    })
}

/// The folder `git clone` would pick: the last path segment without `.git`.
pub(crate) fn repository_name(url: &str) -> Result<String> {
    let trimmed = url.trim().trim_end_matches('/');
    let last = trimmed.rsplit(['/', ':', '\\']).next().unwrap_or_default();
    let name = last.strip_suffix(".git").unwrap_or(last).trim();
    if name.is_empty() || name == "." || name == ".." {
        bail!("Could not derive a folder name from {url}; pass --directory-name.");
    }
    Ok(name.to_string())
}

async fn show_config(client: &mut RuntimeHostRpcClient, project_id: &str) -> Result<Value> {
    let mut effective = client
        .request_value("projectConfig.effective", &json!({"projectId": project_id}))
        .await?;
    let override_config = client
        .request_value("projectConfig.find", &json!({"projectId": project_id}))
        .await?;
    effective["projectId"] = json!(project_id);
    effective["hasOverride"] = json!(!override_config.is_null());
    Ok(effective)
}

async fn set_config(
    client: &mut RuntimeHostRpcClient,
    args: ProjectConfigSetArgs,
) -> Result<Value> {
    let text = match args.config {
        Some(text) => text,
        None => {
            let mut text = String::new();
            std::io::stdin()
                .take(MAX_CONFIG_BYTES as u64 + 1)
                .read_to_string(&mut text)?;
            text
        }
    };
    let changes = parse_config_changes(&text)?;
    let current = client
        .request_value(
            "projectConfig.effective",
            &json!({"projectId": args.project_id}),
        )
        .await?;
    let config = merge_config(current["config"].clone(), changes);
    client
        .request_value(
            "projectConfig.upsert",
            &json!({"projectId": args.project_id, "config": config}),
        )
        .await?;
    show_config(client, &args.project_id).await
}

pub(crate) fn parse_config_changes(text: &str) -> Result<Map<String, Value>> {
    if text.len() > MAX_CONFIG_BYTES {
        bail!("Project settings must be at most {MAX_CONFIG_BYTES} bytes.");
    }
    let Value::Object(changes) = serde_json::from_str(text)? else {
        bail!("Project settings must be a JSON object.");
    };
    if let Some(key) = changes.keys().find(|key| {
        !matches!(
            key.as_str(),
            "worktree" | "newWorkspace" | "gitHostingProvider"
        )
    }) {
        bail!(
            "Unknown project setting `{key}`: use worktree, newWorkspace, or gitHostingProvider."
        );
    }
    Ok(changes)
}

/// Each section given replaces that section; the others keep their current
/// value, which is what editing one tab of the app's settings dialog does.
pub(crate) fn merge_config(current: Value, changes: Map<String, Value>) -> Value {
    let mut config = match current {
        Value::Object(config) => config,
        _ => Map::new(),
    };
    for (key, value) in changes {
        if value.is_null() || value == "auto" && key == "gitHostingProvider" {
            config.remove(&key);
        } else {
            config.insert(key, value);
        }
    }
    Value::Object(config)
}

#[cfg(test)]
#[path = "project_manage_commands_tests.rs"]
mod tests;
