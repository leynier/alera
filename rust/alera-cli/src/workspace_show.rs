//! `alera workspace show`: one workspace with everything the sidebar and its
//! context menu show about it. Read-only; it reads the runtime store, so it
//! works with or without a running host. A satellite asks its hub instead
//! (`workspace.show`), because its store holds only mirrored copies.

use alera_core::runtime::RuntimeStore;
use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::cli::{IdArgs, RuntimeDirArgs};

pub async fn run(runtime: RuntimeDirArgs, args: IdArgs, json_output: bool) -> i32 {
    let result = async {
        let store = RuntimeStore::open(&crate::runtime_dir(&runtime)).await?;
        let id = args.id.trim();
        let forwarded = crate::hub_federation::read_from_hub(
            &runtime,
            &store,
            "workspace.show",
            json!({ "id": id }),
        )
        .await?;
        match forwarded {
            Some(value) => Ok(value),
            None => show(&store, id).await,
        }
    }
    .await;
    match result {
        Ok(value) => {
            let name = value["workspace"]["name"].as_str().unwrap_or_default();
            crate::print_value(&value, json_output, &format!("workspace {name}"));
            0
        }
        Err(error) => crate::print_error(error),
    }
}

pub(crate) async fn show(store: &RuntimeStore, id: &str) -> Result<Value> {
    let workspace = store
        .find_workspace(id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {id}"))?;
    let project = store.find_project(&workspace.project_id).await?;
    let section = match workspace.section_id.as_deref() {
        Some(section_id) => store
            .list_workspace_sections()
            .await?
            .into_iter()
            .find(|section| section.id == section_id)
            .map(|section| json!({ "id": section.id, "name": section.name })),
        None => None,
    };
    let tags: Vec<Value> = store
        .list_tags()
        .await?
        .into_iter()
        .filter(|tag| workspace.tag_ids.contains(&tag.id))
        .map(|tag| json!({ "id": tag.id, "name": tag.name, "color": tag.color }))
        .collect();
    let all = store.list_all_workspaces().await?;
    let summary = |candidate: &alera_core::runtime::Workspace| {
        json!({
            "id": candidate.id,
            "name": candidate.name,
            "branch": candidate.branch,
            "isArchived": candidate.is_archived,
        })
    };
    let parent = workspace
        .parent_workspace_id
        .as_deref()
        .and_then(|parent_id| all.iter().find(|candidate| candidate.id == parent_id))
        .map(summary);
    let children: Vec<Value> = all
        .iter()
        .filter(|candidate| candidate.parent_workspace_id.as_deref() == Some(id))
        .map(summary)
        .collect();
    let slept_tab_ids = store
        .list_slept_workspace_tabs()
        .await?
        .remove(id)
        .unwrap_or_default();
    Ok(json!({
        "workspace": workspace,
        "project": project.map(|project| json!({ "id": project.id, "name": project.name })),
        "section": section,
        "tags": tags,
        "parent": parent,
        "children": children,
        "linkedIssue": store.find_linked_issue(id).await?,
        "linkedPullRequest": store.find_linked_review(id).await?,
        "pullRequestWatch": store.find_pull_request_watch(id).await?,
        "asleep": !slept_tab_ids.is_empty(),
        "sleptTabIds": slept_tab_ids,
        "tabCount": store.list_workspace_tabs(id).await?.len(),
    }))
}
