use alera_core::runtime::{AgentProfile, AgentProfileLaunchMode};

use super::*;

#[tokio::test]
async fn rejects_workspace_owned_by_an_active_automation_run() {
    let fixture = RemovalFixture::new("automation-run").await;
    let now = Utc::now();
    fixture
        .store
        .upsert_agent_profile(
            AgentProfile {
                id: "profile".to_string(),
                name: "Automation Profile".to_string(),
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
            },
            None,
        )
        .await
        .unwrap();
    let definition = automation_definition(&fixture.workspace_id);
    let actor = definition.created_by.clone();
    fixture
        .store
        .upsert_automation(definition.clone(), actor)
        .await
        .unwrap();
    fixture
        .store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "manual|cleanup-owner".to_string(),
                scheduled_at: Utc::now(),
                local_time: "UTC".to_string(),
            },
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();

    let error = fixture.remove_managed_workspace().await.unwrap_err();

    assert!(error.to_string().contains("active automation"));
    assert!(fixture.worktree_path.exists());
}
