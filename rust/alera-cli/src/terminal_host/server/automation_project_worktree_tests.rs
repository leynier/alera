use super::*;
use crate::terminal_host::server::automation_dispatch::AutomationWorktree;
use crate::terminal_host::server::mobile_source_control_snapshot::tests::init_repo;
use alera_core::runtime::{AutomationOccurrence, AutomationRun, AutomationRunTrigger};

async fn project_worktree(fixture: &mut Harness) -> AutomationDefinition {
    let mut definition = draft_definition();
    definition.project_id = Some("project-1".into());
    definition.setup_policy = AutomationSetupPolicy::Skip;
    definition.target = AutomationTarget::ProjectWorktree {
        project_id: "project-1".into(),
        source_branch: "main".into(),
        name_template: "run-{{run.number}}".into(),
        agent_profile_id: "profile-1".into(),
    };
    fixture
        .actor
        .runtime_store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap()
}

async fn started_run(fixture: &Harness, definition: &AutomationDefinition) -> AutomationRun {
    let run = fixture
        .actor
        .runtime_store
        .create_automation_run(
            definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "manual-test".into(),
                scheduled_at: Utc::now(),
                local_time: "test".into(),
            },
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();
    fixture
        .actor
        .runtime_store
        .begin_automation_attempt(&run.id, 3)
        .await
        .unwrap()
}

fn worktree_target(definition: &AutomationDefinition) -> AutomationWorktree<'_> {
    let AutomationTarget::ProjectWorktree {
        project_id,
        source_branch,
        name_template,
        ..
    } = &definition.target
    else {
        unreachable!("project worktree definition")
    };
    AutomationWorktree {
        project_id,
        source_branch,
        name_template,
        parent_workspace_id: None,
    }
}

#[tokio::test]
async fn project_worktree_target_resolves_to_the_local_project_folder() {
    let mut fixture = harness().await;
    let definition = project_worktree(&mut fixture).await;
    let location = fixture
        .actor
        .automation_target_location(&definition)
        .await
        .unwrap();
    assert!(location.workspace.is_none());
    assert_eq!(location.project.id, "project-1");
    assert_eq!(location.host_id, LOCAL_HOST_ID);
    assert_eq!(location.path, fixture.repo_path.to_string_lossy());
    let mut without_project = definition.clone();
    without_project.project_id = None;
    assert_eq!(
        fixture
            .actor
            .automation_definition_project(&without_project)
            .await
            .unwrap()
            .as_deref(),
        Some("project-1")
    );
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
    let error = fixture
        .actor
        .automation_target_location(&definition)
        .await
        .unwrap_err();
    assert!(error.wire_message().contains("git repository"));
}

#[tokio::test]
async fn project_worktree_run_owns_a_new_parentless_worktree_and_reuses_it_on_retry() {
    let mut fixture = harness().await;
    init_repo(&fixture.repo_path);
    let workspaces = fixture.repo_path.parent().unwrap().join("workspaces");
    fixture
        .actor
        .runtime_store
        .set_workspace_directory(Some(&workspaces.to_string_lossy()))
        .await
        .unwrap();
    let definition = project_worktree(&mut fixture).await;
    let mut run = started_run(&fixture, &definition).await;
    let workspace = fixture
        .actor
        .project_worktree_automation_workspace(&definition, &mut run, worktree_target(&definition))
        .await
        .unwrap()
        .expect("worktree created");
    assert_eq!(workspace.project_id, "project-1");
    assert!(workspace.parent_workspace_id.is_none());
    assert_eq!(workspace.name, "run-1");
    let branch = format!("automation/{}/{}", definition.slug, &run.id[..8]);
    assert_eq!(workspace.branch.as_deref(), Some(branch.as_str()));
    assert_ne!(workspace.path, fixture.repo_path.to_string_lossy());
    assert!(run.owned_workspace);
    assert_eq!(run.workspace_id.as_deref(), Some(workspace.id.as_str()));
    assert_eq!(run.workspace_branch.as_deref(), Some(branch.as_str()));

    let reused = fixture
        .actor
        .project_worktree_automation_workspace(&definition, &mut run, worktree_target(&definition))
        .await
        .unwrap()
        .expect("worktree reused");
    assert_eq!(reused.id, workspace.id);
    let worktrees = fixture
        .actor
        .runtime_store
        .list_workspaces("project-1")
        .await
        .unwrap()
        .len();
    assert_eq!(worktrees, 2, "main workspace plus one run worktree");
}

#[tokio::test]
async fn project_worktree_run_files_its_workspace_under_the_chosen_tags_and_section() {
    let mut fixture = harness().await;
    init_repo(&fixture.repo_path);
    let workspaces = fixture.repo_path.parent().unwrap().join("workspaces");
    let store = fixture.actor.runtime_store.clone();
    store
        .set_workspace_directory(Some(&workspaces.to_string_lossy()))
        .await
        .unwrap();
    let plain = project_worktree(&mut fixture).await;
    let mut first_run = started_run(&fixture, &plain).await;
    let first = fixture
        .actor
        .project_worktree_automation_workspace(&plain, &mut first_run, worktree_target(&plain))
        .await
        .unwrap()
        .expect("first worktree");
    assert!(first.tag_ids.is_empty());
    assert!(first.section_id.is_none());
    let section = store
        .create_workspace_section("Automations", &first.id)
        .await
        .unwrap();
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

    let mut placed = plain.clone();
    placed.id = "automation-placed".into();
    placed.slug = "placed".into();
    if let AutomationTarget::ProjectWorktree { name_template, .. } = &mut placed.target {
        *name_template = "placed-{{run.number}}".into();
    }
    placed.workspace_placement = alera_core::runtime::AutomationWorkspacePlacement {
        tag_ids: vec![tag.id.clone(), "deleted-tag".into()],
        section_id: Some(section.id.clone()),
    };
    let placed = store
        .upsert_automation(placed.clone(), placed.created_by.clone())
        .await
        .unwrap();
    let mut run = started_run(&fixture, &placed).await;
    let workspace = fixture
        .actor
        .project_worktree_automation_workspace(&placed, &mut run, worktree_target(&placed))
        .await
        .unwrap()
        .expect("placed worktree");
    let saved = store.find_workspace(&workspace.id).await.unwrap().unwrap();
    assert_eq!(saved.tag_ids, vec![tag.id]);
    assert_eq!(saved.section_id.as_deref(), Some(section.id.as_str()));
}

#[tokio::test]
async fn project_worktree_target_refuses_a_project_with_no_folder_on_this_computer() {
    let mut fixture = harness().await;
    let mut definition = project_worktree(&mut fixture).await;
    let store = fixture.actor.runtime_store.clone();
    let mut project = store.find_project("project-1").await.unwrap().unwrap();
    project.id = "project-remote".into();
    project.repo_path = "/remote/project".into();
    store.upsert_project(project).await.unwrap();
    store
        .register_project_checkout("project-remote", "ssh", "/remote/project")
        .await
        .unwrap();
    definition.project_id = Some("project-remote".into());
    if let AutomationTarget::ProjectWorktree { project_id, .. } = &mut definition.target {
        *project_id = "project-remote".into();
    }
    let error = fixture
        .actor
        .automation_target_location(&definition)
        .await
        .unwrap_err();
    assert!(error.wire_message().contains("no folder on this computer"));
}
