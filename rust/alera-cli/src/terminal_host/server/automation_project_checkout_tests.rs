use super::*;
use alera_core::runtime::{
    AutomationOccurrence, AutomationRunStatus, AutomationRunTrigger, WorkspaceTabRecord,
};

#[path = "automation_precheck_execution_tests.rs"]
mod precheck_execution;

#[cfg(unix)]
#[path = "automation_checkout_stalled_ssh_tests.rs"]
mod stalled_ssh;

async fn empty_project() -> (Harness, AutomationDefinition) {
    let fixture = harness().await;
    fixture
        .actor
        .runtime_store
        .remove_workspace("workspace-1", true)
        .await
        .unwrap();
    let mut project = fixture
        .actor
        .runtime_store
        .find_project("project-1")
        .await
        .unwrap()
        .unwrap();
    project.kind = ProjectKind::Folder;
    fixture
        .actor
        .runtime_store
        .upsert_project(project)
        .await
        .unwrap();
    fixture
        .actor
        .runtime_store
        .set_automation_agent_policy(AutomationAgentPolicy {
            profile_id: "profile-1".into(),
            may_execute: true,
            may_activate_or_edit_active: false,
            updated_at: Utc::now(),
        })
        .await
        .unwrap();
    let mut definition = draft_definition();
    definition.target = AutomationTarget::ProjectCheckout {
        project_id: "project-1".into(),
        host_id: "local".into(),
        name_template: "run-{{run.number}}".into(),
        agent_profile_id: "profile-1".into(),
    };
    let definition = fixture
        .actor
        .runtime_store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    (fixture, definition)
}

#[tokio::test]
async fn project_checkout_target_resolves_without_any_workspace_and_requires_declaration() {
    let (fixture, definition) = empty_project().await;
    let location = fixture
        .actor
        .automation_target_location(&definition)
        .await
        .unwrap();
    assert!(location.workspace.is_none());
    assert_eq!(location.project.id, "project-1");
    assert_eq!(location.host_id, "local");
    assert_eq!(
        fixture
            .actor
            .automation_definition_project(&definition)
            .await
            .unwrap()
            .as_deref(),
        Some("project-1")
    );
    assert!(fixture
        .actor
        .ensure_agent_policy(&definition, &definition.created_by, true)
        .await
        .unwrap_err()
        .to_string()
        .contains("no automation declaration"));
    declare(&fixture.repo_path);
    fixture
        .actor
        .ensure_agent_policy(&definition, &definition.created_by, true)
        .await
        .unwrap();
    assert!(fixture
        .actor
        .runtime_store
        .list_workspaces("project-1")
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn project_checkout_run_allocation_preserves_files_and_default_task_history() {
    let (mut fixture, definition) = empty_project().await;
    declare(&fixture.repo_path);
    std::fs::write(fixture.repo_path.join("shared.txt"), "uncommitted content").unwrap();
    let mut ids = Vec::new();
    for index in 0..2 {
        let occurrence = AutomationOccurrence {
            automation_id: definition.id.clone(),
            key: format!("project-run-{index}"),
            scheduled_at: Utc::now(),
            local_time: "2026-09-12T00:00".into(),
        };
        let mut run = fixture
            .actor
            .runtime_store
            .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
            .await
            .unwrap();
        run.status = AutomationRunStatus::Dispatching;
        let run = fixture
            .actor
            .runtime_store
            .save_automation_run(&run)
            .await
            .unwrap();
        let (bound, task) = fixture
            .actor
            .allocate_project_checkout_automation_workspace(&definition, &run)
            .await
            .unwrap();
        let (_, resumed) = fixture
            .actor
            .allocate_project_checkout_automation_workspace(&definition, &bound)
            .await
            .unwrap();
        assert_eq!(resumed.instance_id, task.instance_id);
        assert!(task.parent_workspace_id.is_none());
        assert_eq!(task.kind, WorkspaceKind::Main);
        let tab_id = format!("tab-{index}");
        let tab = WorkspaceTabRecord {
            id: tab_id.clone(),
            workspace_id: task.id.clone(),
            kind: "terminal".into(),
            title: "History".into(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: json!({"automationRunId": bound.id,"automationOwned":true}),
        };
        fixture
            .actor
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .unwrap();
        let mut completed = bound;
        completed.tab_id = Some(tab_id.clone());
        completed.owned_tab = true;
        fixture
            .actor
            .cleanup_automation_owned_target(&completed, AutomationRunStatus::Success)
            .await;
        assert!(fixture
            .actor
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .unwrap()
            .is_some());
        assert!(fixture
            .actor
            .runtime_store
            .find_workspace(&task.id)
            .await
            .unwrap()
            .is_some());
        ids.push(task.id);
    }
    assert_ne!(ids[0], ids[1]);
    assert_eq!(
        std::fs::read_to_string(fixture.repo_path.join("shared.txt")).unwrap(),
        "uncommitted content"
    );
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .list_workspaces("project-1")
            .await
            .unwrap()
            .len(),
        2
    );
}

#[tokio::test]
async fn project_checkout_missing_host_registration_does_not_fall_back_to_local() {
    let (fixture, mut definition) = empty_project().await;
    if let AutomationTarget::ProjectCheckout { host_id, .. } = &mut definition.target {
        *host_id = "ssh-host".into();
    }
    assert!(fixture
        .actor
        .automation_target_location(&definition)
        .await
        .unwrap_err()
        .to_string()
        .contains("Register a project checkout"));
    assert!(fixture
        .actor
        .runtime_store
        .list_workspaces("project-1")
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn runtime_reports_project_dependencies_and_rejects_removal_without_tasks() {
    let (mut fixture, definition) = empty_project().await;
    fixture
        .actor
        .runtime_store
        .approve_automation(
            &definition.id,
            definition.revision,
            definition.created_by.clone(),
        )
        .await
        .unwrap();
    let (handle, mut responses) = ClientHandle::test_channels();
    fixture.actor.clients.insert(77, local_client(handle));
    fixture
        .actor
        .handle_line(
            77,
            json!({"id":1, "type":"project.removalDependencies", "payload":{"id":"project-1"}})
                .to_string(),
        )
        .await;
    let response = responses.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["ok"], true);
    let dependencies = &response["payload"];
    assert_eq!(dependencies[0]["id"], definition.id);
    assert_eq!(dependencies[0]["requiresPause"], true);
    let request = super::super::runtime_mutations::RuntimeMutationRequest::RemoveProject {
        project_id: "project-1".into(),
    };
    let error = match fixture.actor.prepare_runtime_mutation(&request).await {
        Err(error) => error,
        Ok(_) => panic!("active automation must protect its empty project"),
    };
    assert!(error.to_string().contains(&definition.id));
    assert!(fixture
        .actor
        .runtime_store
        .find_project("project-1")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn offline_cli_project_removal_refuses_dependencies_without_implicit_cancellation() {
    use clap::Parser;
    let (fixture, definition) = empty_project().await;
    fixture
        .actor
        .runtime_store
        .approve_automation(
            &definition.id,
            definition.revision,
            definition.created_by.clone(),
        )
        .await
        .unwrap();
    let cli = crate::cli::Cli::try_parse_from([
        "alera",
        "project",
        "--runtime-dir",
        fixture._runtime_dir.path().to_str().unwrap(),
        "remove",
        "--id",
        "project-1",
    ])
    .unwrap();
    let crate::cli::Command::Project(command) = cli.command else {
        panic!("project command expected");
    };
    assert_eq!(
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            crate::run_project_command(command)
        )
        .await
        .unwrap(),
        1
    );
    assert!(fixture
        .actor
        .runtime_store
        .find_project("project-1")
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .find_automation(&definition.id)
            .await
            .unwrap()
            .unwrap()
            .state,
        AutomationState::Active
    );
}

#[tokio::test]
async fn deferred_checkout_preparation_keeps_actor_responsive_and_honors_cancellation() {
    deferred_preparation_rejection("cancel").await;
}

#[tokio::test]
async fn deferred_checkout_preparation_rejects_a_changed_definition() {
    deferred_preparation_rejection("edit").await;
}

#[tokio::test]
async fn deferred_checkout_preparation_failure_does_not_allocate_a_task() {
    deferred_preparation_rejection("failure").await;
}

#[tokio::test]
async fn deferred_checkout_preparation_timeout_releases_pending_job_without_allocating() {
    deferred_preparation_rejection("timeout").await;
}

async fn deferred_preparation_rejection(scenario: &'static str) {
    let (mut fixture, definition) = empty_project().await;
    declare(&fixture.repo_path);
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "deferred-cancel".into(),
        scheduled_at: Utc::now(),
        local_time: "fixture".into(),
    };
    let mut run = fixture
        .actor
        .runtime_store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatching;
    run.attempt_count = 1;
    let run = fixture
        .actor
        .runtime_store
        .save_automation_run(&run)
        .await
        .unwrap();
    let project = fixture
        .actor
        .runtime_store
        .find_project("project-1")
        .await
        .unwrap()
        .unwrap();
    let candidate = crate::shared_workspace::prepare_fresh_shared_workspace(
        &fixture.actor.runtime_store,
        crate::shared_workspace::SharedWorkspaceCreateRequest {
            project_id: project.id.clone(),
            host_id: Some("local".into()),
            id: None,
            name: Some("candidate".into()),
            parent_workspace_id: None,
        },
    )
    .await
    .unwrap();
    let (release, wait) = tokio::sync::oneshot::channel();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    fixture.actor.inbox = inbox;
    fixture.actor.defer_automation_checkout_preparation(
        definition.clone(),
        run.clone(),
        project,
        async move {
            if scenario == "timeout" {
                std::future::pending::<()>().await;
            }
            wait.await.unwrap();
            if scenario == "failure" {
                Err(crate::terminal_host::host_error::HostError::state(
                    "Fixture SSH inspection failed",
                ))
            } else {
                Ok(candidate)
            }
        },
    );
    assert!(fixture.actor.automation_checkout_jobs.contains(&run.id));
    assert_eq!(fixture.actor.managed_workspace_jobs, 0);
    tokio::time::timeout(
        std::time::Duration::from_secs(1),
        fixture.actor.handle_request(1, "status.get", &json!({})),
    )
    .await
    .unwrap()
    .unwrap();
    match scenario {
        "cancel" => {
            fixture
                .actor
                .runtime_store
                .request_automation_cancel(&run.id, definition.created_by.clone())
                .await
                .unwrap();
        }
        "edit" => {
            let mut updated = definition.clone();
            updated.name = "Changed During Preparation".into();
            fixture
                .actor
                .runtime_store
                .upsert_automation(updated, definition.created_by.clone())
                .await
                .unwrap();
        }
        "failure" | "timeout" => {}
        _ => unreachable!(),
    }
    release.send(()).unwrap();
    let completion_deadline = if scenario == "timeout" { 65 } else { 3 };
    let command = tokio::time::timeout(
        std::time::Duration::from_secs(completion_deadline),
        commands.recv(),
    )
    .await
    .unwrap()
    .unwrap();
    fixture.actor.handle(command).await;
    let current = fixture
        .actor
        .runtime_store
        .find_automation_run(&run.id)
        .await
        .unwrap()
        .unwrap();
    let (status, reason) = match scenario {
        "cancel" => (
            AutomationRunStatus::Cancelled,
            "cancelled during checkout preparation",
        ),
        "edit" => (
            AutomationRunStatus::Blocked,
            "definition changed during checkout preparation",
        ),
        "failure" => (
            AutomationRunStatus::Blocked,
            "Fixture SSH inspection failed",
        ),
        "timeout" => (
            AutomationRunStatus::Blocked,
            "SSH automation checkout preparation timed out",
        ),
        _ => unreachable!(),
    };
    assert_eq!(current.status, status);
    assert!(current.error.as_deref().unwrap().contains(reason));
    assert_eq!(current.attempt_count, 1);
    assert!(current.workspace_id.is_none());
    assert!(fixture
        .actor
        .runtime_store
        .list_workspaces("project-1")
        .await
        .unwrap()
        .is_empty());
    assert!(fixture.actor.automation_checkout_jobs.is_empty());
}
