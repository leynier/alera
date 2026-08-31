use std::fs;

use super::{builtin_workflow_recipes, RuntimeStore, WorkflowRecipeSnapshot, WorkflowRecipeSource};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

async fn workspace(store: &RuntimeStore, path: &std::path::Path) {
    sqlx::query("INSERT INTO projects (id, name, repoPath, createdAt, updatedAt, kind) VALUES ('project', 'Project', ?, '2026-08-30T00:00:00Z', '2026-08-30T00:00:00Z', 'gitRepository')")
        .bind(path.to_str().unwrap()).execute(store.pool()).await.unwrap();
    sqlx::query("INSERT INTO workspaces (id, instanceId, hostId, projectId, name, path, createdAt, updatedAt, kind, status) VALUES ('workspace', 'instance', 'local', 'project', 'Workspace', ?, '2026-08-30T00:00:00Z', '2026-08-30T00:00:00Z', 'main', 'active')")
        .bind(path.to_str().unwrap()).execute(store.pool()).await.unwrap();
}

#[tokio::test]
async fn workflow_catalog_keeps_homonymous_origins_and_invalid_project_entries_explicit() {
    let (_dir, store) = store().await;
    let project = tempfile::tempdir().unwrap();
    workspace(&store, project.path()).await;
    let recipe = builtin_workflow_recipes()[0].clone();
    store
        .save_personal_workflow_recipe(recipe.portable_document().unwrap(), None)
        .await
        .unwrap();
    let catalog = project.path().join(".alera/workflows");
    fs::create_dir_all(&catalog).unwrap();
    fs::write(
        catalog.join("quick.yaml"),
        recipe.portable_document().unwrap(),
    )
    .unwrap();
    fs::write(catalog.join("invalid.yaml"), "version: [").unwrap();
    let result = store.workflow_catalog(Some("workspace")).await.unwrap();
    assert_eq!(result.entries.len(), 5);
    assert_eq!(
        result
            .entries
            .iter()
            .filter(|entry| entry.name.as_deref() == Some("Quick Fix"))
            .count(),
        3
    );
    assert_eq!(
        result
            .entries
            .iter()
            .filter(|entry| entry.error.is_some())
            .count(),
        1
    );
    for source in [
        WorkflowRecipeSource::BuiltIn {
            id: "quick-fix".into(),
        },
        WorkflowRecipeSource::Personal {
            id: "quick-fix".into(),
        },
        WorkflowRecipeSource::Project {
            workspace_id: "workspace".into(),
            path: ".alera/workflows/quick.yaml".into(),
        },
    ] {
        let selected = store.workflow_catalog_recipe(&source).await.unwrap();
        assert_eq!(selected.source, source);
        assert_eq!(selected.recipe, recipe);
    }
    assert!(result.project_error.is_none());
    assert!(store.workflow_catalog(Some("missing")).await.is_err());
}

#[tokio::test]
async fn workflow_catalog_schema_diagnostics_do_not_echo_private_values() {
    let (_dir, store) = store().await;
    let project = tempfile::tempdir().unwrap();
    workspace(&store, project.path()).await;
    let mut recipe = builtin_workflow_recipes()[0].clone();
    recipe.contracts[0].input_schema = serde_json::json!({
        "type":"object", "properties":{"secret":{"type":"string", "minLength":"private-secret-marker"}}
    });
    let catalog = project.path().join(".alera/workflows");
    fs::create_dir_all(&catalog).unwrap();
    fs::write(
        catalog.join("invalid.yaml"),
        serde_json::to_string(&recipe).unwrap(),
    )
    .unwrap();
    let result = store.workflow_catalog(Some("workspace")).await.unwrap();
    let error = result
        .entries
        .iter()
        .find_map(|entry| entry.error.as_deref())
        .unwrap();
    assert!(error.contains("invalid contract schema"), "{error}");
    assert!(!serde_json::to_string(&result)
        .unwrap()
        .contains("private-secret-marker"));
}

#[tokio::test]
async fn workflow_catalog_saves_are_compare_and_swap_and_do_not_mutate_frozen_snapshots() {
    let (_dir, store) = store().await;
    let recipe = builtin_workflow_recipes()[0].clone();
    let document = recipe.portable_document().unwrap();
    let saved = store
        .save_personal_workflow_recipe(document.clone(), None)
        .await
        .unwrap();
    let frozen = WorkflowRecipeSnapshot::freeze(saved.source.clone(), saved.recipe).unwrap();
    assert!(store
        .save_personal_workflow_recipe(document.clone(), None)
        .await
        .is_err());
    let mut changed = recipe;
    changed.name = "Different".into();
    let (first, second) = tokio::join!(
        store.save_personal_workflow_recipe(changed.portable_document().unwrap(), Some(1)),
        store.save_personal_workflow_recipe(document, Some(1))
    );
    assert_ne!(first.is_ok(), second.is_ok());
    let current = store.workflow_catalog_recipe(&saved.source).await.unwrap();
    assert_eq!(current.catalog_revision, Some(2));
    frozen.validate().unwrap();
    assert_eq!(frozen.recipe.name, "Quick Fix");
    assert_eq!(builtin_workflow_recipes()[0].name, "Quick Fix");
}

#[tokio::test]
async fn workflow_catalog_survives_orchestration_resets_and_runtime_reopen() {
    let (dir, store) = store().await;
    let recipe = builtin_workflow_recipes()[0].clone();
    let saved = store
        .save_personal_workflow_recipe(recipe.portable_document().unwrap(), None)
        .await
        .unwrap();
    store.reset_orchestration_tasks().await.unwrap();
    store.reset_orchestration_messages().await.unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .workflow_catalog_recipe(&saved.source)
            .await
            .unwrap(),
        saved
    );
    assert!(reopened
        .save_personal_workflow_recipe("hooks: run".into(), None)
        .await
        .is_err());
    assert_eq!(
        reopened.workflow_catalog(None).await.unwrap().entries.len(),
        3
    );
}

#[tokio::test]
async fn workflow_catalog_refuses_folder_remote_and_retired_workspaces() {
    let (_dir, store) = store().await;
    let project = tempfile::tempdir().unwrap();
    workspace(&store, project.path()).await;
    for (sql, restore) in [
        (
            "UPDATE projects SET kind = 'folder'",
            "UPDATE projects SET kind = 'gitRepository'",
        ),
        (
            "UPDATE workspaces SET hostId = 'remote'",
            "UPDATE workspaces SET hostId = 'local'",
        ),
        (
            "UPDATE workspaces SET status = 'removed'",
            "UPDATE workspaces SET status = 'active'",
        ),
    ] {
        sqlx::query(sql).execute(store.pool()).await.unwrap();
        assert!(store.workflow_catalog(Some("workspace")).await.is_err());
        sqlx::query(restore).execute(store.pool()).await.unwrap();
    }
}

#[tokio::test]
async fn workflow_catalog_enforces_personal_capacity_without_blocking_updates() {
    let (_dir, store) = store().await;
    let mut recipe = builtin_workflow_recipes()[0].clone();
    for index in 0..128 {
        recipe.id = format!("personal-{index}");
        sqlx::query(
            "INSERT INTO personalWorkflowRecipes (id, revision, document) VALUES (?, 1, ?)",
        )
        .bind(&recipe.id)
        .bind(recipe.portable_document().unwrap())
        .execute(store.pool())
        .await
        .unwrap();
    }
    assert!(store
        .save_personal_workflow_recipe(
            builtin_workflow_recipes()[0].portable_document().unwrap(),
            None
        )
        .await
        .is_err());
    let updated = store
        .save_personal_workflow_recipe(recipe.portable_document().unwrap(), Some(1))
        .await
        .unwrap();
    assert_eq!(updated.catalog_revision, Some(2));
    assert_eq!(
        store.workflow_catalog(None).await.unwrap().entries.len(),
        130
    );
}

#[cfg(unix)]
#[tokio::test]
async fn workflow_catalog_directory_escape_does_not_hide_other_origins() {
    let (_dir, store) = store().await;
    let project = tempfile::tempdir().unwrap();
    workspace(&store, project.path()).await;
    let outside = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(outside.path(), project.path().join(".alera")).unwrap();
    let catalog = store.workflow_catalog(Some("workspace")).await.unwrap();
    assert!(catalog.project_error.is_some());
    assert_eq!(catalog.entries.len(), 2);
}
