use super::workflow_plan_tests::{fixture, valid_profile};
use super::*;

#[tokio::test]
async fn approved_desktop_proposal_requires_explicit_start() {
    let (dir, store, mut request) = fixture(false).await;
    let tasks = std::mem::take(&mut request.proposal.tasks);
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let plan = store
        .submit_workflow_proposal(&draft.id, tasks)
        .await
        .unwrap();
    assert!(store
        .workflow_execution(&plan.run_id)
        .await
        .unwrap()
        .is_none());
    super::workflow_plan_tests::decision(
        dir.path(),
        &store,
        &plan,
        crate::workflow_approval::WorkflowDecision::Approve,
    )
    .await;
    let execution = store
        .workflow_execution(&plan.run_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(execution.status, "paused");
    assert_eq!(execution.revision, plan.revision);
    assert_eq!(execution.sequence, 0);
    let started = store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "explicit-start".into(),
            run_id: plan.run_id,
            revision: plan.revision,
            expected_sequence: execution.sequence,
            action: WorkflowExecutionAction::Start,
        })
        .await
        .unwrap();
    assert_eq!(started.status, "running");
}

#[tokio::test]
async fn workflow_proposal_listing_is_bounded_and_resumable() {
    let (_dir, store, mut request) = fixture(false).await;
    request.proposal.tasks.clear();
    request.proposal.objective = "Long objective ".repeat(100);
    for index in 0..27 {
        request.request_id = format!("proposal-{index:03}");
        store
            .create_workflow_proposal(request.clone(), valid_profile)
            .await
            .unwrap();
    }
    let first = store
        .workflow_proposals(WorkflowProposalQuery::default())
        .await
        .unwrap();
    assert_eq!(first.entries.len(), 25);
    assert!(first.has_more);
    assert!(first
        .entries
        .iter()
        .all(|entry| entry.objective.chars().count() == 256));
    let cursor = first.entries.last().unwrap();
    let second = store
        .workflow_proposals(WorkflowProposalQuery {
            before_created_at: Some(cursor.created_at.clone()),
            before_id: Some(cursor.id.clone()),
        })
        .await
        .unwrap();
    assert_eq!(second.entries.len(), 2);
    assert!(!second.has_more);
    assert!(second
        .entries
        .iter()
        .all(|entry| !first.entries.iter().any(|previous| previous.id == entry.id)));
    assert!(store
        .workflow_proposals(WorkflowProposalQuery {
            before_id: Some("invalid".into()),
            before_created_at: None
        })
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_source_preview_excludes_dirty_files_and_binds_workspace_identity() {
    let (_dir, store, mut request) = fixture(false).await;
    request.proposal.tasks.clear();
    let source = store.workflow_source_snapshot("workspace").await.unwrap();
    assert!(!source.has_uncommitted_changes);
    assert_eq!(source.sha, request.proposal.source_sha);
    let path = std::path::Path::new(&source.workspace.path).join("user-notes.txt");
    std::fs::write(&path, "User work must stay intact").unwrap();
    let dirty = store.workflow_source_snapshot("workspace").await.unwrap();
    assert!(dirty.has_uncommitted_changes);
    assert_eq!(dirty.sha, source.sha);
    let mut stale = source.workspace.clone();
    stale.instance_id = "replaced".into();
    assert!(store
        .create_workflow_proposal_at_source(request.clone(), valid_profile, Some(stale))
        .await
        .is_err());
    store
        .create_workflow_proposal_at_source(request, valid_profile, Some(source.workspace))
        .await
        .unwrap();
    assert_eq!(
        std::fs::read_to_string(path).unwrap(),
        "User work must stay intact"
    );
}

#[tokio::test]
async fn workflow_proposal_survives_restart_without_executable_tasks() {
    let (dir, store, mut request) = fixture(false).await;
    let tasks = std::mem::take(&mut request.proposal.tasks);
    let (first, replay) = tokio::join!(
        store.create_workflow_proposal(request.clone(), valid_profile),
        store.create_workflow_proposal(request.clone(), valid_profile),
    );
    let first = first.unwrap();
    assert_eq!(first.id, replay.unwrap().id);
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let replay = reopened
        .create_workflow_proposal(request.clone(), valid_profile)
        .await
        .unwrap();
    assert_eq!(first.selection.digest, replay.selection.digest);
    let prepared = reopened
        .submit_workflow_proposal(&first.id, tasks.clone())
        .await
        .unwrap();
    let replay = reopened
        .submit_workflow_proposal(&first.id, tasks.clone())
        .await
        .unwrap();
    assert_eq!(prepared.run_id, replay.run_id);
    let status = reopened.workflow_proposal_status(&first.id).await.unwrap();
    assert_eq!(status.run_id.as_deref(), Some(prepared.run_id.as_str()));
    assert_eq!(status.revision, Some(prepared.revision));
    assert_eq!(prepared.status, "prepared");
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
    let mut changed_tasks = tasks;
    changed_tasks[0].title = "Different proposal".into();
    assert!(reopened
        .submit_workflow_proposal(&first.id, changed_tasks)
        .await
        .is_err());
    request.proposal.objective = "Changed selection".into();
    assert!(reopened
        .create_workflow_proposal(request, valid_profile)
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_proposal_preserves_selected_profile_and_rejects_invalid_dag() {
    let (_dir, store, mut request) = fixture(false).await;
    let tasks = std::mem::take(&mut request.proposal.tasks);
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let mut profile = store.find_agent_profile("profile").await.unwrap().unwrap();
    let revision = profile.revision;
    profile.command = "codex --changed".into();
    store
        .upsert_agent_profile(profile, Some(revision))
        .await
        .unwrap();
    assert!(store
        .submit_workflow_proposal(&draft.id, Vec::new())
        .await
        .is_err());
    let mut cyclic = tasks.clone();
    let successor = cyclic[1].id.clone();
    cyclic[0].depends_on.push(successor);
    assert!(store
        .submit_workflow_proposal(&draft.id, cyclic)
        .await
        .is_err());
    let prepared = store
        .submit_workflow_proposal(&draft.id, tasks)
        .await
        .unwrap();
    assert_eq!(prepared.plan.profiles["profile"].command, "codex");
}

#[tokio::test]
async fn workflow_proposal_rejects_selection_changes_and_missing_source() {
    let (_dir, store, mut request) = fixture(false).await;
    assert!(store
        .create_workflow_proposal(request.clone(), valid_profile)
        .await
        .is_err());
    request.proposal.tasks.clear();
    let mut invalid = request.clone();
    invalid.request_id = "unsafe;command".into();
    assert!(store
        .create_workflow_proposal(invalid, valid_profile)
        .await
        .is_err());
    let mut invalid = request.clone();
    invalid.proposal.expected_recipe_digest = "stale".into();
    assert!(store
        .create_workflow_proposal(invalid, valid_profile)
        .await
        .is_err());
    let mut invalid = request.clone();
    invalid.proposal.role_profiles.clear();
    assert!(store
        .create_workflow_proposal(invalid, valid_profile)
        .await
        .is_err());
    request.proposal.source_sha = "0".repeat(40);
    assert!(store
        .create_workflow_proposal(request, valid_profile)
        .await
        .is_err());
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowProposalDrafts")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
}
