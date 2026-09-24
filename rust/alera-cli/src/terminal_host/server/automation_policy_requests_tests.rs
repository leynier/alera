use std::collections::HashMap;
use std::path::PathBuf;

use alera_core::runtime::{AutomationAgentPolicy, AutomationProjectPolicy, Project, ProjectKind};
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
    Harness {
        _runtime_dir: runtime_dir,
        repo_path,
        actor,
    }
}

async fn insert_profile(actor: &ServerActor, id: &str, name: &str) {
    sqlx::query(
        "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
         VALUES (?, ?, 'codex', 'codex', datetime('now'), datetime('now'))",
    )
    .bind(id)
    .bind(name)
    .execute(actor.runtime_store.pool())
    .await
    .unwrap();
}

#[tokio::test]
async fn policy_show_without_ids_lists_empty_agent_and_project_policies() {
    let mut harness = harness().await;

    let listed = harness
        .actor
        .handle_automation_request(1, "automation.policy", &json!({}))
        .await
        .unwrap();

    assert_eq!(listed["agents"], json!([]));
    assert_eq!(listed["projects"], json!([]));
}

#[tokio::test]
async fn policy_show_without_ids_lists_all_persisted_policies() {
    let mut harness = harness().await;
    insert_profile(&harness.actor, "profile-b", "Profile B").await;
    insert_profile(&harness.actor, "profile-a", "Profile A").await;
    let now = Utc::now();
    harness
        .actor
        .runtime_store
        .upsert_project(Project {
            id: "project-1".into(),
            name: "Project".into(),
            repo_path: harness.repo_path.to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    std::fs::write(
        harness.repo_path.join("alera.toml"),
        "[automation]\ndeclared = true\n",
    )
    .unwrap();
    harness
        .actor
        .runtime_store
        .set_automation_agent_policy(AutomationAgentPolicy {
            profile_id: "profile-b".into(),
            may_activate_or_edit_active: true,
            may_execute: false,
            updated_at: now,
        })
        .await
        .unwrap();
    harness
        .actor
        .runtime_store
        .set_automation_agent_policy(AutomationAgentPolicy {
            profile_id: "profile-a".into(),
            may_activate_or_edit_active: false,
            may_execute: true,
            updated_at: now,
        })
        .await
        .unwrap();
    harness
        .actor
        .runtime_store
        .set_automation_project_policy(AutomationProjectPolicy {
            project_id: "project-1".into(),
            repo_declared: false,
            local_approved: true,
            restrictive: true,
            updated_at: now,
        })
        .await
        .unwrap();

    let listed = harness
        .actor
        .handle_automation_request(
            1,
            "automation.policy",
            &json!({"kind": "show", "profileId": "", "projectId": ""}),
        )
        .await
        .unwrap();

    assert_eq!(listed["agents"][0]["profileId"], "profile-a");
    assert_eq!(listed["agents"][0]["mayExecute"], true);
    assert_eq!(listed["agents"][1]["profileId"], "profile-b");
    assert_eq!(listed["agents"].as_array().unwrap().len(), 2);
    assert_eq!(listed["projects"][0]["projectId"], "project-1");
    assert_eq!(listed["projects"][0]["localApproved"], true);
    assert_eq!(listed["projects"][0]["repoDeclared"], true);
}

#[tokio::test]
async fn policy_show_with_profile_id_still_returns_agent_and_effective() {
    let mut harness = harness().await;
    insert_profile(&harness.actor, "profile-1", "Profile 1").await;
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

    let shown = harness
        .actor
        .handle_automation_request(
            1,
            "automation.policy",
            &json!({"kind": "show", "profileId": "profile-1"}),
        )
        .await
        .unwrap();

    assert_eq!(shown["agent"]["profileId"], "profile-1");
    assert_eq!(shown["effective"]["targetProfile"]["mayExecute"], true);
    assert!(shown.get("agents").is_none());
}
