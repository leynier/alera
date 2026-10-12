use chrono::Utc;
use serde_json::json;
use tempfile::TempDir;

use super::{
    AutomationActor, AutomationActorKind, AutomationBoundTarget, AutomationCleanupPolicy,
    AutomationDefinition, AutomationReusePolicy, AutomationTarget, Project, ProjectKind,
    RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, WorkspaceTabRecord, LOCAL_HOST_ID,
};

fn actor() -> AutomationActor {
    AutomationActor {
        kind: AutomationActorKind::LocalCli,
        id: None,
        label: None,
    }
}

fn definition(policy: AutomationReusePolicy) -> AutomationDefinition {
    let now = Utc::now();
    serde_json::from_value(json!({
        "id": "automation-1",
        "slug": "review",
        "name": "Review",
        "promptTemplate": "Review",
        "schedule": {"recurring": {"cron": "0 * * * *", "timezone": "UTC"}},
        "target": {"freshTab": {"workspaceId": "workspace-1", "agentProfileId": "profile-1"}},
        "reusePolicy": policy,
        "state": "draft",
        "revision": 0,
        "createdBy": actor(),
        "modifiedBy": actor(),
        "createdAt": now,
        "updatedAt": now,
    }))
    .unwrap()
}

fn binding(tab: Option<&str>) -> AutomationBoundTarget {
    AutomationBoundTarget {
        workspace_id: "workspace-1".into(),
        tab_id: tab.map(str::to_string),
        conversation_id: tab.map(|_| "conversation-1".to_string()),
        agent_profile_id: Some("profile-1".into()),
        bound_run_id: "run-1".into(),
        bound_at: Utc::now(),
        last_run_id: Some("run-1".into()),
        last_verified_at: None,
    }
}

async fn store() -> (TempDir, RuntimeStore) {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let now = Utc::now();
    for profile in ["profile-1", "profile-2"] {
        sqlx::query(
            "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
             VALUES (?, ?, 'codex', 'codex', datetime('now'), datetime('now'))",
        )
        .bind(profile)
        .bind(profile)
        .execute(store.pool())
        .await
        .unwrap();
    }
    store
        .upsert_project(Project {
            id: "project-1".into(),
            name: "Project".into(),
            repo_path: directory.path().to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::Folder,
        })
        .await
        .unwrap();
    store
        .upsert_workspace(Workspace {
            id: "workspace-1".into(),
            instance_id: "instance-1".into(),
            host_id: LOCAL_HOST_ID.into(),
            project_id: "project-1".into(),
            name: "Workspace".into(),
            branch: None,
            path: directory.path().to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Main,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: true,
            is_pinned: false,
            is_archived: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab-1".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Agent".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"terminalSessionId": "tab-1"}),
        })
        .await
        .unwrap();
    store
        .upsert_automation(
            definition(AutomationReusePolicy::ReuseConversation),
            actor(),
        )
        .await
        .unwrap();
    (directory, store)
}

async fn bound(store: &RuntimeStore) -> Option<AutomationBoundTarget> {
    store
        .find_automation("automation-1")
        .await
        .unwrap()
        .unwrap()
        .bound_target
}

async fn audit_actions(store: &RuntimeStore) -> Vec<String> {
    store
        .list_automation_audit_events(Some("automation-1"), 100)
        .await
        .unwrap()
        .into_iter()
        .map(|event| event.action)
        .collect()
}

#[tokio::test]
async fn binding_writes_keep_the_revision_and_record_audits() {
    let (_directory, store) = store().await;
    let before = store
        .find_automation("automation-1")
        .await
        .unwrap()
        .unwrap();
    assert!(store
        .bind_automation_target("automation-1", &binding(Some("tab-1")), "created")
        .await
        .unwrap());
    let later = Utc::now();
    assert!(store
        .touch_automation_bound_target("automation-1", "run-2", later)
        .await
        .unwrap());
    let after = store
        .find_automation("automation-1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(after.revision, before.revision);
    assert_eq!(after.updated_at, before.updated_at);
    let stored = after.bound_target.unwrap();
    assert_eq!(stored.tab_id.as_deref(), Some("tab-1"));
    assert_eq!(stored.last_run_id.as_deref(), Some("run-2"));
    assert_eq!(stored.last_verified_at, Some(later));

    assert!(store
        .release_automation_bound_tab("automation-1", "takenOver")
        .await
        .unwrap());
    let released = bound(&store).await.unwrap();
    assert_eq!(released.workspace_id, "workspace-1");
    assert_eq!(released.tab_id, None);
    assert_eq!(released.conversation_id, None);
    assert!(!store
        .release_automation_bound_tab("automation-1", "takenOver")
        .await
        .unwrap());

    assert!(store
        .clear_automation_bound_target("automation-1", "unbound")
        .await
        .unwrap());
    assert_eq!(bound(&store).await, None);
    assert!(!store
        .clear_automation_bound_target("automation-1", "unbound")
        .await
        .unwrap());
    assert!(!store
        .touch_automation_bound_target("automation-1", "run-3", Utc::now())
        .await
        .unwrap());
    let actions = audit_actions(&store).await;
    for action in ["targetBound", "boundTabReleased", "targetUnbound"] {
        assert_eq!(
            actions.iter().filter(|item| *item == action).count(),
            1,
            "{action}: {actions:?}"
        );
    }
}

#[tokio::test]
async fn removing_the_bound_tab_releases_it_and_retiring_the_workspace_clears_the_binding() {
    let (_directory, store) = store().await;
    store
        .bind_automation_target("automation-1", &binding(Some("tab-1")), "created")
        .await
        .unwrap();
    store.remove_workspace_tab("tab-1").await.unwrap();
    let released = bound(&store).await.unwrap();
    assert_eq!(released.tab_id, None);
    assert_eq!(released.workspace_id, "workspace-1");

    store.remove_workspace("workspace-1", true).await.unwrap();
    assert_eq!(bound(&store).await, None);
    assert!(audit_actions(&store)
        .await
        .contains(&"targetUnbound".to_string()));
}

#[tokio::test]
async fn bulk_helpers_return_the_automations_they_changed() {
    let (_directory, store) = store().await;
    store
        .bind_automation_target("automation-1", &binding(Some("tab-1")), "created")
        .await
        .unwrap();
    assert_eq!(
        store
            .release_automation_bound_tabs_for_tab("other-tab", "tabClosed")
            .await
            .unwrap(),
        Vec::<String>::new()
    );
    assert_eq!(
        store
            .release_automation_bound_tabs_for_tab("tab-1", "tabClosed")
            .await
            .unwrap(),
        vec!["automation-1".to_string()]
    );
    assert_eq!(
        store
            .clear_automation_bound_targets_for_workspace("workspace-1", "workspaceGone")
            .await
            .unwrap(),
        vec!["automation-1".to_string()]
    );
}

#[tokio::test]
async fn upsert_owns_the_binding_and_drops_it_when_the_target_or_policy_changes() {
    let (_directory, store) = store().await;
    store
        .bind_automation_target("automation-1", &binding(Some("tab-1")), "created")
        .await
        .unwrap();

    let mut edited = definition(AutomationReusePolicy::ReuseConversation);
    edited.prompt_template = "Review again".into();
    let mut forged = binding(Some("forged-tab"));
    forged.workspace_id = "forged".into();
    edited.bound_target = Some(forged);
    let saved = store.upsert_automation(edited, actor()).await.unwrap();
    assert_eq!(
        saved.bound_target.unwrap().tab_id.as_deref(),
        Some("tab-1"),
        "a prompt edit keeps the stored binding and ignores the client's"
    );

    let mut retargeted = definition(AutomationReusePolicy::ReuseConversation);
    retargeted.target = AutomationTarget::FreshTab {
        workspace_id: "workspace-1".into(),
        agent_profile_id: "profile-2".into(),
    };
    let saved = store.upsert_automation(retargeted, actor()).await.unwrap();
    assert_eq!(saved.bound_target, None);

    store
        .bind_automation_target("automation-1", &binding(Some("tab-1")), "created")
        .await
        .unwrap();
    let mut disabled = definition(AutomationReusePolicy::NewEachRun);
    disabled.target = saved.target.clone();
    let saved = store.upsert_automation(disabled, actor()).await.unwrap();
    assert_eq!(saved.bound_target, None);

    let mut fresh = definition(AutomationReusePolicy::ReuseConversation);
    fresh.id = "automation-2".into();
    fresh.slug = "fresh".into();
    fresh.bound_target = Some(binding(Some("tab-1")));
    let created = store.upsert_automation(fresh, actor()).await.unwrap();
    assert_eq!(created.bound_target, None, "a client cannot seed a binding");
    let unbound = store
        .list_automation_audit_events(Some("automation-1"), 100)
        .await
        .unwrap()
        .into_iter()
        .filter(|event| event.action == "targetUnbound")
        .map(|event| {
            event.details["reason"]
                .as_str()
                .unwrap_or_default()
                .to_string()
        })
        .collect::<Vec<_>>();
    assert_eq!(unbound.len(), 2);
    assert!(unbound.contains(&"targetChanged".to_string()));
    assert!(unbound.contains(&"reuseDisabled".to_string()));
}

#[tokio::test]
async fn reuse_policy_is_material_and_validated_while_the_binding_is_not() {
    let (_directory, store) = store().await;
    let saved = store
        .find_automation("automation-1")
        .await
        .unwrap()
        .unwrap();
    let mut bound_copy = saved.clone();
    bound_copy.bound_target = Some(binding(None));
    assert_eq!(
        saved.material_fingerprint(),
        bound_copy.material_fingerprint()
    );
    let mut other_policy = saved.clone();
    other_policy.reuse_policy = AutomationReusePolicy::ReuseWorkspace;
    assert_ne!(
        saved.material_fingerprint(),
        other_policy.material_fingerprint()
    );
    let saved = store
        .upsert_automation(other_policy, actor())
        .await
        .unwrap();
    let edit = store
        .list_automation_audit_events(Some("automation-1"), 100)
        .await
        .unwrap()
        .into_iter()
        .find(|event| event.action == "edit" && event.revision == Some(saved.revision))
        .unwrap();
    assert_eq!(edit.details["material"], true);
    assert_eq!(edit.details["changedFields"], json!(["reusePolicy"]));

    let mut cleanup = definition(AutomationReusePolicy::ReuseWorkspace);
    cleanup.cleanup_policy = Some(AutomationCleanupPolicy::OnSuccess);
    assert!(store.upsert_automation(cleanup, actor()).await.is_err());
}
