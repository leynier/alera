use super::*;

#[tokio::test]
async fn project_checkout_places_a_new_task_once_and_leaves_a_resumed_one_alone() {
    let (fixture, mut definition) = empty_project().await;
    declare(&fixture.repo_path);
    let store = fixture.actor.runtime_store.clone();
    let now = Utc::now();
    let tag = store
        .upsert_tag(alera_core::runtime::WorkspaceTag {
            id: "tag-triage".into(),
            name: "Triage".into(),
            color: None,
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();
    definition.workspace_placement.tag_ids = vec![tag.id.clone()];
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "placed-run".into(),
        scheduled_at: Utc::now(),
        local_time: "2026-10-05T00:00".into(),
    };
    let mut run = store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatching;
    let run = store.save_automation_run(&run).await.unwrap();
    let (bound, task) = fixture
        .actor
        .allocate_project_checkout_automation_workspace(&definition, &run)
        .await
        .unwrap();
    let placed = store.find_workspace(&task.id).await.unwrap().unwrap();
    assert_eq!(placed.tag_ids, vec![tag.id.clone()]);

    store.set_workspace_tags(&task.id, &[]).await.unwrap();
    let (_, resumed) = fixture
        .actor
        .allocate_project_checkout_automation_workspace(&definition, &bound)
        .await
        .unwrap();
    assert_eq!(resumed.id, task.id);
    let kept = store.find_workspace(&task.id).await.unwrap().unwrap();
    assert!(kept.tag_ids.is_empty());
}
