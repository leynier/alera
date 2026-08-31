use super::*;

#[tokio::test]
async fn workflow_worktrees_reregistered_alias_cannot_remove_or_rerun_setup() {
    let fixture = Fixture::new("").await;
    let original = fixture.integration().await;
    fixture
        .store
        .remove_workspace(&original.identity.workspace.id, true)
        .await
        .unwrap();
    let mut alias = original.identity.workspace.clone();
    alias.id = Uuid::new_v4().to_string();
    alias.instance_id = Uuid::new_v4().to_string();
    fixture.store.upsert_workspace(alias.clone()).await.unwrap();
    let request = ManagedWorkspaceRemoveRequest {
        id: alias.id.clone(),
        delete_branch: Some(true),
        active_workspace_id: None,
        close_sessions: true,
    };
    assert!(remove_managed_workspace(&fixture.store, request)
        .await
        .is_err());
    assert!(
        crate::worktree_setup::run_workspace_setup(&fixture.store, &alias.id, false)
            .await
            .is_err()
    );
    assert!(Path::new(&alias.path).exists());
    assert!(core_git::branch_exists(
        &original.identity.repo_path,
        alias.branch.as_deref().unwrap()
    )
    .unwrap());
    assert!(fixture
        .store
        .workflow_workspace_owned(&original.identity.workspace.id)
        .await
        .unwrap());
}

#[cfg(unix)]
#[tokio::test]
async fn workflow_worktrees_symlink_root_freezes_the_git_path_before_reconciliation() {
    let fixture = Fixture::new("").await;
    let root = fixture.runtime.parent().unwrap();
    let real = root.join("real-root");
    let alias = root.join("alias-root");
    std::fs::create_dir(&real).unwrap();
    std::os::unix::fs::symlink(&real, &alias).unwrap();
    fixture
        .store
        .set_workspace_directory(alias.to_str())
        .await
        .unwrap();
    let integration = fixture.integration().await;
    let live = core_git::list_worktrees(&integration.identity.repo_path)
        .unwrap()
        .into_iter()
        .find(|entry| Some(&entry.branch) == integration.identity.workspace.branch.as_ref())
        .unwrap();
    assert_eq!(integration.identity.workspace.path, live.path);
    assert!(Path::new(&live.path).starts_with(real.canonicalize().unwrap()));
    let mut reconciled = integration.identity.workspace;
    reconciled.path = live.path;
    reconciled.branch = Some(live.branch);
    fixture.store.upsert_workspace(reconciled).await.unwrap();
}

#[tokio::test]
async fn workflow_worktrees_large_copy_report_keeps_success_and_failed_setup_outcomes() {
    let fixture = Fixture::new("").await;
    std::fs::create_dir(fixture.source.join("cache")).unwrap();
    std::fs::write(fixture.source.join(".gitignore"), "cache/\n").unwrap();
    std::fs::write(fixture.source.join(".worktreeinclude"), "cache/**\n").unwrap();
    for index in 0..2000 {
        std::fs::write(
            fixture
                .source
                .join("cache")
                .join(format!("file-{index:04}-{}.txt", "details".repeat(8))),
            "content",
        )
        .unwrap();
    }
    fixture.integration().await;
    for (task, succeeded) in [("fix", true), ("other", false)] {
        if !succeeded {
            std::fs::write(
                fixture.source.join("alera.toml"),
                "[worktree]\nsetup = [\"exit 7\"]\n",
            )
            .unwrap();
        }
        let record = fixture.task(task).await;
        assert_eq!(
            record.phase,
            if succeeded {
                Phase::Ready
            } else {
                Phase::Attention
            },
            "{record:?}"
        );
        let report = record.setup_report.unwrap();
        assert!(serde_json::to_vec(&report).unwrap().len() < 262_144);
        assert_eq!(report.steps.iter().all(|step| step.succeeded), succeeded);
        assert!(report
            .steps
            .last()
            .unwrap()
            .message
            .as_ref()
            .unwrap()
            .contains("steps omitted"));
        assert_eq!(
            std::fs::read_dir(Path::new(&record.identity.workspace.path).join("cache"))
                .unwrap()
                .count(),
            2000
        );
    }
}
