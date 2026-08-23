use chrono::Utc;
use serde_json::json;

use super::{AgentProfile, AgentProfileLaunchMode, RuntimeStore, WorkspaceTabRecord};
use crate::runtime::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationMisfirePolicy,
    AutomationOverlapPolicy, AutomationSchedule, AutomationSetupPolicy, AutomationState,
    AutomationTarget,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn profile(id: &str, name: &str) -> AgentProfile {
    let now = Utc::now();
    AgentProfile {
        id: id.to_string(),
        name: name.to_string(),
        sort_order: 0,
        agent_type: "codex".to_string(),
        command: "codex".to_string(),
        launch_mode: AgentProfileLaunchMode::Command,
        managed_config: None,
        custom_prompt: String::new(),
        description: String::new(),
        quota_group: None,
        revision: 0,
        created_at: now,
        updated_at: now,
    }
}

fn automation(profile_id: &str) -> AutomationDefinition {
    let now = Utc::now();
    let actor = AutomationActor {
        kind: AutomationActorKind::LocalCli,
        id: None,
        label: None,
    };
    AutomationDefinition {
        id: "automation-profile-removal".into(),
        slug: "profile-removal".into(),
        name: "Profile Removal".into(),
        description: String::new(),
        project_id: None,
        tag_ids: Vec::new(),
        prompt_template: "Sensitive prompt that must not appear in impact".into(),
        schedule: AutomationSchedule::OneTime {
            at: now,
            timezone: "UTC".into(),
        },
        target: AutomationTarget::FreshTab {
            workspace_id: "workspace-1".into(),
            agent_profile_id: profile_id.into(),
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
        state: AutomationState::Draft,
        revision: 0,
        approved_revision: None,
        created_by: actor.clone(),
        modified_by: actor,
        created_at: now,
        updated_at: now,
    }
}

#[tokio::test]
async fn removal_impact_rejects_a_stale_revision() {
    let (_dir, store) = store().await;
    let created = store
        .upsert_agent_profile(profile("prof_a", "Original"), None)
        .await
        .unwrap();
    store
        .upsert_agent_profile(created.clone(), Some(created.revision))
        .await
        .unwrap();

    let error = store
        .agent_profile_removal_impact("prof_a", 0)
        .await
        .unwrap_err();

    assert!(error.to_string().contains("revision conflict"));
}

#[tokio::test]
async fn automation_reference_exposes_only_its_id_and_blocks_removal() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_a", "Codex Sol"), None)
        .await
        .unwrap();
    let definition = automation("prof_a");
    store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();

    let impact = store
        .agent_profile_removal_impact("prof_a", 0)
        .await
        .unwrap();
    assert_eq!(impact.automation_ids, ["automation-profile-removal"]);
    let encoded = serde_json::to_string(&impact).unwrap();
    assert!(!encoded.contains("Sensitive prompt"));
    assert!(store.remove_agent_profile("prof_a", 0).await.is_err());
}

#[tokio::test]
async fn snapshot_tab_reference_exposes_only_tab_identity_and_blocks_removal() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_a", "Codex Sol"), None)
        .await
        .unwrap();
    let now = Utc::now();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "snapshot-tab".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Sensitive title".into(),
            created_at: now,
            updated_at: now,
            payload: json!({
                "agentProfileLaunchV1": {
                    "version": 1,
                    "profile": {"id": "prof_a", "name": "Codex Sol", "revision": 0},
                    "launch": {"kind": "command", "command": "secret command"}
                },
                "initialPrompt": "secret prompt"
            }),
        })
        .await
        .unwrap();

    let impact = store
        .agent_profile_removal_impact("prof_a", 0)
        .await
        .unwrap();

    assert_eq!(impact.tabs.len(), 1);
    assert_eq!(impact.tabs[0].workspace_id, "workspace-1");
    assert_eq!(impact.tabs[0].tab_id, "snapshot-tab");
    let encoded = serde_json::to_string(&impact).unwrap();
    assert!(!encoded.contains("Sensitive title"));
    assert!(!encoded.contains("secret command"));
    assert!(!encoded.contains("secret prompt"));
    assert!(store.remove_agent_profile("prof_a", 0).await.is_err());
}

#[tokio::test]
async fn active_execution_policy_reference_exposes_only_run_id_and_blocks_removal() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_a", "Codex Sol"), None)
        .await
        .unwrap();
    let run = store
        .create_orchestration_coordinator_run("Sensitive run spec", Some("coord"), 2_000)
        .await
        .unwrap();
    store
        .propose_orchestration_execution_policy(
            &run.id,
            r#"{"version":1,"stages":[{"id":"impl","profile":"Codex Sol","fallbacks":[]}]}"#,
        )
        .await
        .unwrap();
    store
        .resolve_orchestration_execution_policy(&run.id, true)
        .await
        .unwrap();

    let impact = store
        .agent_profile_removal_impact("prof_a", 0)
        .await
        .unwrap();
    assert_eq!(
        impact.execution_policy_run_ids,
        std::slice::from_ref(&run.id)
    );
    let encoded = serde_json::to_string(&impact).unwrap();
    assert!(!encoded.contains("Sensitive run spec"));
    assert!(store.remove_agent_profile("prof_a", 0).await.is_err());

    store
        .finish_orchestration_coordinator_run(
            &run.id,
            crate::runtime::OrchestrationCoordinatorStatus::Completed,
        )
        .await
        .unwrap();
    assert!(store.remove_agent_profile("prof_a", 0).await.unwrap());
}

#[tokio::test]
async fn database_guards_reject_references_committed_after_profile_removal() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_a", "Codex Sol"), None)
        .await
        .unwrap();
    assert!(store.remove_agent_profile("prof_a", 0).await.unwrap());

    let now = Utc::now();
    let tab_error = store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "late-tab".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Late tab".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"agentProfileId": "prof_a"}),
        })
        .await
        .unwrap_err();
    assert!(tab_error.to_string().contains("reference does not exist"));

    let snapshot_tab_error = store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "late-snapshot-tab".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Late snapshot tab".into(),
            created_at: now,
            updated_at: now,
            payload: json!({
                "agentProfileLaunchV1": {
                    "version": 1,
                    "profile": {"id": "prof_a", "name": "Deleted", "revision": 0}
                }
            }),
        })
        .await
        .unwrap_err();
    assert!(snapshot_tab_error
        .to_string()
        .contains("reference does not exist"));

    let definition = automation("prof_a");
    assert_eq!(
        serde_json::to_value(&definition)
            .unwrap()
            .pointer("/target/freshTab/agent_profile_id"),
        Some(&json!("prof_a"))
    );
    let automation_error = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap_err();
    assert!(automation_error
        .to_string()
        .contains("reference does not exist"));
    assert!(store
        .set_default_agent_profile_id(Some("prof_a"))
        .await
        .is_err());
    assert!(store
        .set_automation_agent_policy(crate::runtime::AutomationAgentPolicy {
            profile_id: "prof_a".into(),
            may_activate_or_edit_active: false,
            may_execute: false,
            updated_at: now,
        })
        .await
        .is_err());
    let run = store
        .create_orchestration_coordinator_run("run", Some("coord"), 2_000)
        .await
        .unwrap();
    assert!(store
        .propose_orchestration_execution_policy(
            &run.id,
            r#"{"version":1,"stages":[{"id":"impl","profile":"Codex Sol","fallbacks":[]}]}"#,
        )
        .await
        .is_err());
}
