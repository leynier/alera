use std::collections::HashMap;
use std::path::{Path, PathBuf};

use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationAgentPolicy, AutomationDefinition,
    AutomationMisfirePolicy, AutomationOverlapPolicy, AutomationSchedule, AutomationSetupPolicy,
    AutomationState, AutomationTarget, Project, ProjectKind, Workspace, WorkspaceKind,
    WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::json;

use super::actor_test_harness::{local_client, test_actor};
use super::ServerActor;
use crate::terminal_host::client::ClientHandle;

struct Harness {
    _runtime_dir: tempfile::TempDir,
    repo_path: PathBuf,
    actor: ServerActor,
}

async fn harness() -> Harness {
    let runtime_dir = tempfile::tempdir().unwrap();
    let repo_path = runtime_dir.path().join("repo");
    std::fs::create_dir(&repo_path).unwrap();
    let (handle, _events) = ClientHandle::test_channels();
    let actor = test_actor(
        &runtime_dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let now = Utc::now();
    sqlx::query(
        "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
         VALUES ('profile-1', 'Profile 1', 'codex', 'codex', datetime('now'), datetime('now'))",
    )
    .execute(actor.runtime_store.pool())
    .await
    .unwrap();
    let repo = repo_path.to_string_lossy().into_owned();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project-1".into(),
            name: "Project".into(),
            repo_path: repo.clone(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace(Workspace {
            id: "workspace-1".into(),
            instance_id: "instance-1".into(),
            host_id: LOCAL_HOST_ID.into(),
            project_id: "project-1".into(),
            name: "Workspace".into(),
            branch: Some("main".into()),
            path: repo,
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Main,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: true,
            is_pinned: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    Harness {
        _runtime_dir: runtime_dir,
        repo_path,
        actor,
    }
}

fn draft_definition() -> AutomationDefinition {
    let now = Utc::now();
    let actor = AutomationActor {
        kind: AutomationActorKind::LocalCli,
        id: None,
        label: None,
    };
    AutomationDefinition {
        id: "automation-1".into(),
        slug: "review".into(),
        name: "Review".into(),
        description: String::new(),
        project_id: None,
        tag_ids: Vec::new(),
        prompt_template: "Review {{workspace.name}}".into(),
        schedule: AutomationSchedule::Recurring {
            cron: "0 * * * *".into(),
            timezone: "UTC".into(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        },
        target: AutomationTarget::FreshTab {
            workspace_id: "workspace-1".into(),
            agent_profile_id: "profile-1".into(),
        },
        setup_policy: AutomationSetupPolicy::Wait,
        cleanup_policy: None,
        overlap_policy: AutomationOverlapPolicy::Skip,
        queue_cap: 10,
        inactivity_timeout_seconds: 7200,
        heartbeat_interval_seconds: 60,
        misfire_grace_seconds: 900,
        misfire_policy: AutomationMisfirePolicy::Skip,
        retry_max_attempts: 3,
        retry_backoff_seconds: 60,
        circuit_failure_threshold: 3,
        circuit_open_seconds: 900,
        precheck: None,
        notify_on_success: false,
        circuit_opened: false,
        circuit_opened_at: None,
        state: AutomationState::Draft,
        revision: 0,
        approved_revision: None,
        created_by: actor.clone(),
        modified_by: actor,
        created_at: now,
        updated_at: now,
    }
}

fn declare(repo: &Path) {
    std::fs::write(repo.join("alera.toml"), "[automation]\ndeclared = true\n").unwrap();
}

async fn upsert_draft(actor: &mut ServerActor) -> AutomationDefinition {
    let saved = actor
        .handle_automation_request(
            1,
            "automation.upsert",
            &json!({ "automation": draft_definition() }),
        )
        .await
        .unwrap();
    serde_json::from_value(saved).unwrap()
}

#[tokio::test]
async fn draft_create_edit_trash_and_restore_work_without_alera_toml_declaration() {
    let mut harness = harness().await;
    assert!(!harness.repo_path.join("alera.toml").exists());

    let created = upsert_draft(&mut harness.actor).await;
    assert_eq!(created.state, AutomationState::Draft);

    let mut edited = created.clone();
    edited.description = "A draft edit".into();
    let saved = harness
        .actor
        .handle_automation_request(1, "automation.upsert", &json!({ "automation": edited }))
        .await
        .unwrap();
    assert_eq!(saved["state"], "draft");
    assert_eq!(saved["description"], "A draft edit");

    let trashed = harness
        .actor
        .handle_automation_request(1, "automation.trash", &json!({ "id": created.id }))
        .await
        .unwrap();
    assert_eq!(trashed["state"], "trashed");

    let restored = harness
        .actor
        .handle_automation_request(1, "automation.restore", &json!({ "id": created.id }))
        .await
        .unwrap();
    assert_eq!(restored["state"], "draft");
}

#[tokio::test]
async fn approve_and_pause_work_without_alera_toml_declaration() {
    let mut harness = harness().await;
    let created = upsert_draft(&mut harness.actor).await;

    let approved = harness
        .actor
        .handle_automation_request(
            1,
            "automation.approve",
            &json!({ "id": created.id, "revision": created.revision }),
        )
        .await
        .unwrap();
    assert_eq!(approved["state"], "active");
    assert_eq!(approved["approvedRevision"], created.revision);

    let paused = harness
        .actor
        .handle_automation_request(1, "automation.pause", &json!({ "id": created.id }))
        .await
        .unwrap();
    assert_eq!(paused["state"], "paused");
}

#[tokio::test]
async fn manual_execution_without_declaration_is_blocked() {
    let mut harness = harness().await;
    let created = upsert_draft(&mut harness.actor).await;
    harness
        .actor
        .runtime_store
        .set_automation_agent_policy(AutomationAgentPolicy {
            profile_id: "profile-1".into(),
            may_activate_or_edit_active: true,
            may_execute: true,
            updated_at: Utc::now(),
        })
        .await
        .unwrap();

    let error = harness
        .actor
        .handle_automation_request(
            1,
            "automation.runNow",
            &json!({
                "id": created.id,
                "draftTest": true,
                "precheck": false,
                "overlap": "skip",
            }),
        )
        .await
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("has no automation declaration in alera.toml"),
        "{error}"
    );
}

#[tokio::test]
async fn execution_policy_accepts_a_declared_repository() {
    let mut harness = harness().await;
    let created = upsert_draft(&mut harness.actor).await;
    declare(&harness.repo_path);
    harness
        .actor
        .runtime_store
        .set_automation_agent_policy(AutomationAgentPolicy {
            profile_id: "profile-1".into(),
            may_activate_or_edit_active: true,
            may_execute: true,
            updated_at: Utc::now(),
        })
        .await
        .unwrap();
    let actor = harness.actor.automation_actor(1, &json!({}));
    harness
        .actor
        .ensure_agent_policy(&created, &actor, true)
        .await
        .unwrap();
}
