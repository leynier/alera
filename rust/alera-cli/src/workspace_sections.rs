//! `alera workspace section` commands.
//!
//! Prefer a live host RPC so connected apps refresh from `workspaceSectionsChanged`.
//! Fall back to `RuntimeStore` when no host is connected, matching `workspace pin`.

use std::path::Path;

use alera_core::runtime::{RuntimeStore, WorkspaceSection};
use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

use crate::cli::{
    IdArgs, RuntimeDirArgs, WorkspaceSectionAction, WorkspaceSectionCommand,
    WorkspaceSectionCreateArgs, WorkspaceSectionWorkspaceArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;

pub async fn run(
    runtime: RuntimeDirArgs,
    command: WorkspaceSectionCommand,
    json_output: bool,
) -> i32 {
    match execute(&crate::runtime_dir(&runtime), command.action).await {
        Ok((value, message)) => {
            crate::print_value(&value, json_output, &message);
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn execute(runtime_dir: &Path, action: WorkspaceSectionAction) -> Result<(Value, String)> {
    let mut backend = Backend::open(runtime_dir).await?;
    match action {
        WorkspaceSectionAction::List => {
            let items = backend.list().await?;
            Ok((
                json!({ "kind": "workspaceSections", "items": items, "filters": {} }),
                "workspace sections listed".to_string(),
            ))
        }
        WorkspaceSectionAction::Create(WorkspaceSectionCreateArgs {
            name,
            workspace_id,
            tree,
        }) => {
            let section = backend.create(&name, &workspace_id).await?;
            let descendants = tree_rest(runtime_dir, &workspace_id, tree).await?;
            for descendant in &descendants {
                backend.set(descendant, Some(&section.id)).await?;
            }
            let mut value = json!(section);
            value["treeWorkspaceIds"] = json!(descendants);
            Ok((value, "workspace section created".to_string()))
        }
        WorkspaceSectionAction::Set(args) => {
            let mut payload = assign(
                &mut backend,
                &args.workspace_id,
                args.section,
                args.section_id,
            )
            .await?;
            let section_id = payload["sectionId"].as_str().map(str::to_string);
            let descendants = tree_rest(runtime_dir, &args.workspace_id, args.tree).await?;
            for descendant in &descendants {
                backend.set(descendant, section_id.as_deref()).await?;
            }
            payload["treeWorkspaceIds"] = json!(descendants);
            Ok((payload, "workspace section assigned".to_string()))
        }
        WorkspaceSectionAction::Clear(WorkspaceSectionWorkspaceArgs { workspace_id, tree }) => {
            backend.set(&workspace_id, None).await?;
            let descendants = tree_rest(runtime_dir, &workspace_id, tree).await?;
            for descendant in &descendants {
                backend.set(descendant, None).await?;
            }
            let mut payload = set_for_workspace_payload(&workspace_id, None);
            payload["treeWorkspaceIds"] = json!(descendants);
            Ok((payload, "workspace section cleared".to_string()))
        }
        WorkspaceSectionAction::Remove(IdArgs { id }) => {
            backend.remove(&id).await?;
            Ok((json!({ "id": id }), "workspace section removed".to_string()))
        }
    }
}

/// The descendants a Tree action also applies to, without the workspace.
async fn tree_rest(runtime_dir: &Path, workspace_id: &str, tree: bool) -> Result<Vec<String>> {
    if !tree {
        return Ok(Vec::new());
    }
    let workspaces = crate::workspace_tree::all_workspaces(runtime_dir).await?;
    Ok(crate::workspace_tree::tree_ids(&workspaces, workspace_id)
        .into_iter()
        .skip(1)
        .collect())
}

async fn assign(
    backend: &mut Backend,
    workspace_id: &str,
    section: Option<String>,
    section_id: Option<String>,
) -> Result<Value> {
    let section_id =
        resolve_section_ref(backend, section.as_deref(), section_id.as_deref()).await?;
    backend.set(workspace_id, Some(&section_id)).await?;
    Ok(set_for_workspace_payload(workspace_id, Some(&section_id)))
}

async fn resolve_section_ref(
    backend: &mut Backend,
    name: Option<&str>,
    section_id: Option<&str>,
) -> Result<String> {
    match (nonempty(name), nonempty(section_id)) {
        (None, None) => bail!("Pass --section or --section-id."),
        (Some(_), Some(_)) => bail!("Pass only one of --section or --section-id."),
        (None, Some(id)) => Ok(id.to_string()),
        (Some(name), None) => {
            let sections = backend.list().await?;
            resolve_section_id(&sections, name)
        }
    }
}

pub(crate) async fn resolve_optional_section_id(
    client: &mut RuntimeHostRpcClient,
    name: Option<&str>,
    section_id: Option<&str>,
) -> Result<Option<String>> {
    match (nonempty(name), nonempty(section_id)) {
        (None, None) => Ok(None),
        (Some(_), Some(_)) => bail!("Pass only one of --section or --section-id."),
        (None, Some(id)) => {
            let sections = list_sections_from_client(client).await?;
            Ok(Some(require_section_id(&sections, id)?))
        }
        (Some(name), None) => {
            let sections = list_sections_from_client(client).await?;
            Ok(Some(resolve_section_id(&sections, name)?))
        }
    }
}

async fn list_sections_from_client(
    client: &mut RuntimeHostRpcClient,
) -> Result<Vec<WorkspaceSection>> {
    client.request("workspaceSection.list", &json!({})).await
}

pub(crate) async fn set_for_workspace_on_client(
    client: &mut RuntimeHostRpcClient,
    workspace_id: &str,
    section_id: Option<&str>,
) -> Result<()> {
    client
        .request_value(
            "workspaceSection.setForWorkspace",
            &set_for_workspace_payload(workspace_id, section_id),
        )
        .await?;
    Ok(())
}

pub(crate) fn created_workspace_id(created: &Value) -> Result<&str> {
    created
        .get("workspace")
        .and_then(|workspace| workspace.get("id"))
        .and_then(Value::as_str)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| anyhow!("workspace create returned no workspace id"))
}

pub(crate) fn resolve_section_id(sections: &[WorkspaceSection], name: &str) -> Result<String> {
    let needle = name.trim();
    if needle.is_empty() {
        bail!("Section name cannot be empty.");
    }
    let needle_key = needle.to_lowercase();
    let matches: Vec<&WorkspaceSection> = sections
        .iter()
        .filter(|section| section.name.to_lowercase() == needle_key)
        .collect();
    match matches.as_slice() {
        [section] => Ok(section.id.clone()),
        [] => bail!("No workspace section named {needle}."),
        many => bail!(
            "Workspace section name {needle} is ambiguous ({} matches). Use --section-id.",
            many.len()
        ),
    }
}

pub(crate) fn require_section_id(sections: &[WorkspaceSection], id: &str) -> Result<String> {
    let id = id.trim();
    if id.is_empty() {
        bail!("Section id cannot be empty.");
    }
    if sections.iter().any(|section| section.id == id) {
        Ok(id.to_string())
    } else {
        bail!("No workspace section with id {id}.");
    }
}

pub(crate) fn set_for_workspace_payload(workspace_id: &str, section_id: Option<&str>) -> Value {
    json!({
        "workspaceId": workspace_id,
        "sectionId": section_id,
    })
}

fn nonempty(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
}

enum Backend {
    Host(RuntimeHostRpcClient),
    Store(RuntimeStore),
}

impl Backend {
    async fn open(runtime_dir: &Path) -> Result<Self> {
        if let Some(client) = RuntimeHostRpcClient::connect(runtime_dir).await? {
            return Ok(Self::Host(client));
        }
        Ok(Self::Store(RuntimeStore::open(runtime_dir).await?))
    }

    async fn list(&mut self) -> Result<Vec<WorkspaceSection>> {
        match self {
            Self::Host(client) => client.request("workspaceSection.list", &json!({})).await,
            Self::Store(store) => store.list_workspace_sections().await,
        }
    }

    async fn create(&mut self, name: &str, workspace_id: &str) -> Result<WorkspaceSection> {
        match self {
            Self::Host(client) => {
                client
                    .request(
                        "workspaceSection.create",
                        &json!({ "name": name, "workspaceId": workspace_id }),
                    )
                    .await
            }
            Self::Store(store) => store.create_workspace_section(name, workspace_id).await,
        }
    }

    async fn set(&mut self, workspace_id: &str, section_id: Option<&str>) -> Result<()> {
        match self {
            Self::Host(client) => {
                client
                    .request_value(
                        "workspaceSection.setForWorkspace",
                        &set_for_workspace_payload(workspace_id, section_id),
                    )
                    .await?;
                Ok(())
            }
            Self::Store(store) => store.set_workspace_section(workspace_id, section_id).await,
        }
    }

    async fn remove(&mut self, id: &str) -> Result<()> {
        match self {
            Self::Host(client) => {
                client
                    .request_value("workspaceSection.remove", &json!({ "id": id }))
                    .await?;
                Ok(())
            }
            Self::Store(store) => store.remove_workspace_section(id).await,
        }
    }
}

#[cfg(test)]
#[path = "workspace_sections_tests.rs"]
mod tests;
