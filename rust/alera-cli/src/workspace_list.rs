//! `alera workspace list`, with the sidebar's filters: section, tag,
//! archived, parent, and host.

use serde_json::{json, Value};

use crate::cli::{RuntimeDirArgs, WorkspaceListArgs};

pub async fn run(runtime: RuntimeDirArgs, args: WorkspaceListArgs, json_output: bool) -> i32 {
    if !args.all && args.project_id.is_none() {
        eprintln!("Missing --project-id or --all.");
        return crate::USAGE_EXIT_CODE;
    }
    match list(&runtime, &args).await {
        Ok(mut answer) => {
            if let Some(items) = answer["items"].as_array_mut() {
                items.retain(|item| matches(item, &args));
            }
            answer["filters"] = filters(&args);
            crate::print_value(&answer, json_output, "workspaces listed");
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn list(runtime: &RuntimeDirArgs, args: &WorkspaceListArgs) -> anyhow::Result<Value> {
    let store = alera_core::runtime::RuntimeStore::open(&crate::runtime_dir(runtime)).await?;
    if let Some(answer) = crate::hub_federation::read_from_hub(
        runtime,
        &store,
        "workspace.list",
        json!({ "projectId": args.project_id, "hostId": args.host_id }),
    )
    .await?
    {
        return Ok(json!({
            "kind": "workspaces",
            "items": answer["items"],
            "source": "hub",
            "originHostId": answer["originHostId"],
        }));
    }
    let mut workspaces = match &args.project_id {
        Some(project_id) if !args.all => store.list_workspaces(project_id).await?,
        _ => store.list_all_workspaces().await?,
    };
    if let Some(host_id) = &args.host_id {
        let host_id = crate::ssh_remote::normalized_host_id(Some(host_id));
        workspaces.retain(|workspace| workspace.host_id == host_id);
    }
    Ok(json!({ "kind": "workspaces", "items": workspaces }))
}

fn filters(args: &WorkspaceListArgs) -> Value {
    json!({
        "hostId": args.host_id
            .as_deref()
            .map(|host_id| crate::ssh_remote::normalized_host_id(Some(host_id))),
        "sectionId": args.section_id,
        "tagId": args.tag_id,
        "archived": args.archived,
        "parentWorkspaceId": args.parent_workspace_id,
    })
}

/// Filters apply to the listed JSON so a hub's answer is filtered the same
/// way as this runtime's own records.
fn matches(item: &Value, args: &WorkspaceListArgs) -> bool {
    let section_matches = match args.section_id.as_deref() {
        None => true,
        Some("none") => item["sectionId"].is_null(),
        Some(section_id) => item["sectionId"].as_str() == Some(section_id),
    };
    let tag_matches = args.tag_id.as_deref().is_none_or(|tag_id| {
        item["tagIds"]
            .as_array()
            .is_some_and(|tags| tags.iter().any(|tag| tag.as_str() == Some(tag_id)))
    });
    let archived_matches = args
        .archived
        .is_none_or(|archived| item["isArchived"].as_bool().unwrap_or(false) == archived);
    let parent_matches = args
        .parent_workspace_id
        .as_deref()
        .is_none_or(|parent| item["parentWorkspaceId"].as_str() == Some(parent));
    section_matches && tag_matches && archived_matches && parent_matches
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(section: Option<&str>, tag: Option<&str>, archived: Option<bool>) -> WorkspaceListArgs {
        WorkspaceListArgs {
            project_id: None,
            all: true,
            host_id: None,
            section_id: section.map(str::to_string),
            tag_id: tag.map(str::to_string),
            archived,
            parent_workspace_id: None,
        }
    }

    #[test]
    fn filters_match_sections_tags_archive_and_parents() {
        let item = json!({
            "id": "w", "sectionId": "s1", "tagIds": ["t1"], "isArchived": true,
            "parentWorkspaceId": "p",
        });
        let others = json!({ "id": "o", "sectionId": null, "tagIds": [], "isArchived": false });
        assert!(matches(&item, &args(Some("s1"), Some("t1"), Some(true))));
        assert!(!matches(&item, &args(Some("s2"), None, None)));
        assert!(!matches(&item, &args(None, Some("t2"), None)));
        assert!(!matches(&item, &args(None, None, Some(false))));
        assert!(matches(&others, &args(Some("none"), None, Some(false))));
        assert!(!matches(&item, &args(Some("none"), None, None)));
        let mut by_parent = args(None, None, None);
        by_parent.parent_workspace_id = Some("p".into());
        assert!(matches(&item, &by_parent));
        assert!(!matches(&others, &by_parent));
    }
}
