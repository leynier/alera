use std::collections::HashMap;

use alera_core::runtime::{Project, ProjectKind, Workspace};
use chrono::Utc;
use serde_json::json;

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::mobile_gateway_surface::{mobile_request_allowed, MOBILE_HELLO_CAPABILITIES};
use crate::terminal_host::client::ClientHandle;

#[tokio::test]
async fn sections_publish_to_desktop_and_mobile_and_preserve_legacy_preferences() {
    let dir = tempfile::tempdir().unwrap();
    let (desktop, mut desktop_events) = ClientHandle::test_channels();
    let (mobile, mut mobile_events) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(desktop)),
            (2, mobile_client(mobile, "phone")),
        ]),
        HashMap::new(),
    )
    .await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "p".into(),
            name: "Project".into(),
            repo_path: "/p".into(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::Folder,
        })
        .await
        .unwrap();
    let workspace: Workspace = serde_json::from_value(json!({
        "id": "w", "instanceId": "instance", "hostId": "local", "projectId": "p", "name": "Workspace", "path": "/p",
        "createdAt": now, "updatedAt": now, "kind": "main", "status": "active", "reusesExistingBranch": false,
    })).unwrap();
    actor
        .runtime_store
        .upsert_workspace(workspace)
        .await
        .unwrap();
    assert!(actor
        .workspace_section_request(99, "workspaceSection.list", &json!({}))
        .await
        .is_err());
    let created = actor
        .workspace_section_request(
            1,
            "workspaceSection.create",
            &json!({"workspaceId": "w", "name": "Work"}),
        )
        .await
        .unwrap();
    for events in [&mut desktop_events, &mut mobile_events] {
        let first = events.try_recv().unwrap().as_json().unwrap();
        let second = events.try_recv().unwrap().as_json().unwrap();
        assert_eq!(first["event"], "workspacesChanged");
        assert_eq!(second["event"], "workspaceSectionsChanged");
    }
    let snapshot = actor.workspace_sidebar_snapshot(2).await.unwrap();
    assert_eq!(snapshot["sections"][0]["id"], created["id"]);
    assert_eq!(snapshot["workspaces"][0]["sectionId"], created["id"]);
    let prefs = json!({"groupBy": "section", "sectionSort": "recent", "collapsedSectionIds": [created["id"]], "othersSectionCollapsed": true,
        "projectSort": "name", "workspaceSort": "name", "workspaceKindFilter": "all"});
    let saved = actor
        .update_workbench_view_prefs(1, &json!({"prefs": prefs}))
        .await
        .unwrap();
    let mut legacy = prefs.clone();
    for field in [
        "sectionSort",
        "collapsedSectionIds",
        "othersSectionCollapsed",
    ] {
        legacy.as_object_mut().unwrap().remove(field);
    }
    legacy["groupBy"] = json!("project");
    let updated = actor
        .update_workbench_view_prefs(
            2,
            &json!({"prefs": legacy, "expectedRevision": saved["revision"]}),
        )
        .await
        .unwrap();
    assert_eq!(updated["prefs"]["sectionSort"], "recent");
    assert_eq!(
        updated["prefs"]["collapsedSectionIds"],
        prefs["collapsedSectionIds"]
    );
    assert_eq!(updated["prefs"]["othersSectionCollapsed"], true);
    actor
        .workspace_section_request(
            2,
            "workspaceSection.setForWorkspace",
            &json!({"workspaceId": "w", "sectionId": null}),
        )
        .await
        .unwrap();
    assert!(actor
        .runtime_store
        .list_workspace_sections()
        .await
        .unwrap()
        .is_empty());
    assert!(actor
        .runtime_store
        .find_workspace("w")
        .await
        .unwrap()
        .is_some());
}

#[test]
fn sections_are_advertised_and_allowed_on_mobile() {
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&"workspaceSectionsV1"));
    for verb in [
        "workspaceSection.list",
        "workspaceSection.create",
        "workspaceSection.setForWorkspace",
        "workspaceSection.remove",
    ] {
        assert!(mobile_request_allowed(verb));
    }
}
