use super::*;

fn init_repo_with_submodule() -> tempfile::TempDir {
    let child = init_repo();
    let parent = init_repo();
    let child_path = path_str(child.path());
    run_git(
        parent.path(),
        &[
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            &child_path,
            "modules/sample",
        ],
    );
    run_git(parent.path(), &["commit", "-am", "add submodule"]);
    configure_git_identity(&parent.path().join("modules/sample"));
    parent
}

#[test]
fn reports_and_loads_tracked_and_untracked_submodule_changes() {
    let parent = init_repo_with_submodule();
    let child = parent.path().join("modules/sample");
    std::fs::write(child.join("README.md"), "changed inside\n").expect("modify tracked file");
    std::fs::write(child.join("new.txt"), "new inside\n").expect("write untracked file");
    run_git(&child, &["add", "README.md"]);

    let status = git_status(path_str(parent.path())).unwrap();
    let entry = status
        .entries
        .iter()
        .find(|entry| entry.path == "modules/sample" && entry.area == GitChangeArea::Unstaged)
        .expect("submodule status entry");
    let submodule = entry.submodule.as_ref().expect("submodule metadata");
    assert!(!submodule.commit_changed);
    assert!(submodule.tracked_changes);
    assert!(submodule.untracked_changes);
    assert_eq!(entry.added, None);
    assert_eq!(entry.removed, None);

    let inner = git_submodule_status(
        path_str(parent.path()),
        "modules/sample".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();
    assert!(inner
        .entries
        .iter()
        .any(|entry| { entry.path == "README.md" && entry.area == GitChangeArea::Staged }));
    assert!(inner
        .entries
        .iter()
        .any(|entry| { entry.path == "new.txt" && entry.area == GitChangeArea::Untracked }));

    let diff = git_diff(
        path_str(parent.path()),
        "modules/sample/README.md".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert_eq!(diff.files[0].path, "modules/sample/README.md");
    assert!(diff_text(&diff.files[0]).contains("+changed inside"));
}

#[test]
fn exposes_pointer_and_inner_diffs_for_staged_submodule_commit() {
    let parent = init_repo_with_submodule();
    let child = parent.path().join("modules/sample");
    commit_file(&child, "README.md", "next commit\n", "advance submodule");

    let unstaged = git_status(path_str(parent.path())).unwrap();
    let entry = unstaged
        .entries
        .iter()
        .find(|entry| entry.path == "modules/sample" && entry.area == GitChangeArea::Unstaged)
        .expect("unstaged pointer");
    assert!(entry.submodule.as_ref().unwrap().commit_changed);
    let pointer = git_diff(
        path_str(parent.path()),
        "modules/sample".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();
    assert!(pointer.files[0].is_gitlink);
    assert!(diff_text(&pointer.files[0]).contains("Subproject commit"));

    run_git(parent.path(), &["add", "modules/sample"]);
    let staged = git_submodule_status(
        path_str(parent.path()),
        "modules/sample".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert!(staged.entries.iter().any(|entry| entry.path == "README.md"));

    let inner = git_diff(
        path_str(parent.path()),
        "modules/sample/README.md".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert_eq!(inner.files[0].path, "modules/sample/README.md");
    assert!(diff_text(&inner.files[0]).contains("+next commit"));
}

#[test]
fn mixed_pointer_and_worktree_changes_keep_distinct_correct_diffs() {
    let parent = init_repo_with_submodule();
    let child = parent.path().join("modules/sample");
    std::fs::write(child.join("README.md"), "committed in child\n")
        .expect("write committed child change");
    std::fs::write(child.join("range-only.txt"), "range only\n").expect("write range-only file");
    run_git(&child, &["add", "."]);
    run_git(&child, &["commit", "-m", "advance child"]);
    std::fs::write(child.join("README.md"), "dirty in worktree\n")
        .expect("write dirty child change");
    std::fs::write(child.join("untracked.txt"), "untracked in child\n")
        .expect("write untracked child file");

    let inner = git_submodule_status(
        path_str(parent.path()),
        "modules/sample".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();
    assert_eq!(
        inner
            .entries
            .iter()
            .filter(|entry| { entry.path == "README.md" && entry.area == GitChangeArea::Unstaged })
            .count(),
        1
    );
    assert!(inner
        .entries
        .iter()
        .any(|entry| entry.path == "range-only.txt"));

    let worktree_diff = git_diff(
        path_str(parent.path()),
        "modules/sample/README.md".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();
    let worktree_text = diff_text(&worktree_diff.files[0]);
    assert!(worktree_text.contains("+dirty in worktree"));
    assert!(!worktree_text.contains("+committed in child"));

    let range_diff = git_diff(
        path_str(parent.path()),
        "modules/sample/range-only.txt".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();
    assert!(diff_text(&range_diff.files[0]).contains("+range only"));

    let untracked_diff = git_diff(
        path_str(parent.path()),
        "modules/sample/untracked.txt".to_string(),
        GitChangeArea::Untracked,
    )
    .unwrap();
    assert!(diff_text(&untracked_diff.files[0]).contains("+untracked in child"));
}

#[test]
fn staged_gitlink_expansion_ignores_later_child_changes() {
    let parent = init_repo_with_submodule();
    let child = parent.path().join("modules/sample");
    commit_file(
        &child,
        "README.md",
        "committed in child\n",
        "advance submodule",
    );
    run_git(parent.path(), &["add", "modules/sample"]);
    std::fs::write(child.join("README.md"), "later staged child edit\n")
        .expect("write later child edit");
    run_git(&child, &["add", "README.md"]);
    std::fs::write(child.join("untracked.txt"), "later untracked child file\n")
        .expect("write later untracked child file");

    let staged = git_submodule_status(
        path_str(parent.path()),
        "modules/sample".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert!(staged
        .entries
        .iter()
        .all(|entry| entry.area == GitChangeArea::Staged));
    assert!(!staged
        .entries
        .iter()
        .any(|entry| entry.path == "untracked.txt"));

    let diff = git_diff(
        path_str(parent.path()),
        "modules/sample/README.md".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    let text = diff_text(&diff.files[0]);
    assert!(text.contains("+committed in child"));
    assert!(!text.contains("+later staged child edit"));
}

#[test]
fn discarding_gitlink_change_resets_initialized_child_to_parent_index() {
    let parent = init_repo_with_submodule();
    let child_path = parent.path().join("modules/sample");
    let original_oid = Repository::open(&child_path)
        .unwrap()
        .head()
        .unwrap()
        .target()
        .unwrap();
    let original_contents = std::fs::read_to_string(child_path.join("README.md")).unwrap();
    commit_file(
        &child_path,
        "README.md",
        "next commit\n",
        "advance submodule",
    );
    let advanced_oid = Repository::open(&child_path)
        .unwrap()
        .head()
        .unwrap()
        .target()
        .unwrap();

    git_discard(path_str(parent.path()), Some("modules/sample".to_string())).unwrap();

    let child = Repository::open(&child_path).unwrap();
    assert_eq!(child.head().unwrap().target(), Some(original_oid));
    assert!(child.head_detached().unwrap());
    assert_eq!(
        child
            .find_branch("main", BranchType::Local)
            .unwrap()
            .get()
            .target(),
        Some(advanced_oid)
    );
    assert_eq!(
        std::fs::read_to_string(child_path.join("README.md")).unwrap(),
        original_contents
    );
    let status = git_status(path_str(parent.path())).unwrap();
    assert!(!status
        .entries
        .iter()
        .any(|entry| entry.path == "modules/sample"));
}

#[test]
fn discard_all_skips_deleted_submodule_and_restores_supported_files() {
    let parent = init_repo_with_submodule();
    std::fs::write(parent.path().join("README.md"), "dirty parent file\n")
        .expect("write dirty parent file");
    std::fs::remove_dir_all(parent.path().join("modules/sample"))
        .expect("remove submodule checkout");

    git_discard(path_str(parent.path()), None).unwrap();

    assert_eq!(
        std::fs::read_to_string(parent.path().join("README.md")).unwrap(),
        "hello"
    );
    let status = git_status(path_str(parent.path())).unwrap();
    assert_eq!(status.entries.len(), 1);
    assert_eq!(status.entries[0].path, "modules/sample");
    assert!(!status.entries[0].submodule.as_ref().unwrap().inspectable);
}

#[test]
fn discard_all_skips_dirty_moved_submodule_and_restores_supported_files() {
    let parent = init_repo_with_submodule();
    let child_path = parent.path().join("modules/sample");
    commit_file(
        &child_path,
        "README.md",
        "committed in child\n",
        "advance submodule",
    );
    let advanced_oid = Repository::open(&child_path)
        .unwrap()
        .head()
        .unwrap()
        .target()
        .unwrap();
    std::fs::write(child_path.join("README.md"), "dirty child edit\n")
        .expect("write dirty child edit");
    std::fs::write(parent.path().join("README.md"), "dirty parent file\n")
        .expect("write dirty parent file");

    git_discard(path_str(parent.path()), None).unwrap();

    assert_eq!(
        std::fs::read_to_string(parent.path().join("README.md")).unwrap(),
        "hello"
    );
    let child = Repository::open(&child_path).unwrap();
    assert_eq!(child.head().unwrap().target(), Some(advanced_oid));
    assert_eq!(
        std::fs::read_to_string(child_path.join("README.md")).unwrap(),
        "dirty child edit\n"
    );
    let status = git_status(path_str(parent.path())).unwrap();
    assert_eq!(status.entries.len(), 1);
    assert_eq!(status.entries[0].path, "modules/sample");
}

#[test]
fn discarding_gitlink_change_refuses_dirty_child_checkout() {
    let parent = init_repo_with_submodule();
    let child_path = parent.path().join("modules/sample");
    commit_file(
        &child_path,
        "README.md",
        "committed in child\n",
        "advance submodule",
    );
    let advanced_oid = Repository::open(&child_path)
        .unwrap()
        .head()
        .unwrap()
        .target()
        .unwrap();
    std::fs::write(child_path.join("README.md"), "staged child edit\n")
        .expect("write staged child edit");
    run_git(&child_path, &["add", "README.md"]);

    let error =
        git_discard(path_str(parent.path()), Some("modules/sample".to_string())).unwrap_err();

    assert_eq!(error.kind, GitErrorKind::Conflict);
    let child = Repository::open(&child_path).unwrap();
    assert_eq!(child.head().unwrap().target(), Some(advanced_oid));
    assert_eq!(
        std::fs::read_to_string(child_path.join("README.md")).unwrap(),
        "staged child edit\n"
    );
    assert!(git_status(path_str(&child_path))
        .unwrap()
        .entries
        .iter()
        .any(|entry| entry.path == "README.md" && entry.area == GitChangeArea::Staged));
}

#[test]
fn combined_diff_includes_worktree_only_submodule_changes() {
    let parent = init_repo_with_submodule();
    let child_path = parent.path().join("modules/sample");
    std::fs::write(child_path.join("README.md"), "dirty child worktree\n")
        .expect("write dirty child worktree");
    std::fs::write(child_path.join("new.txt"), "untracked child file\n")
        .expect("write untracked child file");

    let diff = git_diff_all(path_str(parent.path()), None).unwrap();

    let tracked = diff
        .files
        .iter()
        .find(|file| file.path == "modules/sample/README.md")
        .expect("tracked child diff");
    assert!(diff_text(tracked).contains("+dirty child worktree"));
    let untracked = diff
        .files
        .iter()
        .find(|file| file.path == "modules/sample/new.txt")
        .expect("untracked child diff");
    assert!(diff_text(untracked).contains("+untracked child file"));
}

#[test]
fn combined_diff_includes_pointer_and_dirty_child_changes() {
    let parent = init_repo_with_submodule();
    let child_path = parent.path().join("modules/sample");
    commit_file(
        &child_path,
        "README.md",
        "committed in child\n",
        "advance submodule",
    );
    std::fs::write(child_path.join("README.md"), "dirty child worktree\n")
        .expect("write dirty child worktree");

    let diff = git_diff_all(path_str(parent.path()), None).unwrap();

    let pointer = diff
        .files
        .iter()
        .find(|file| file.path == "modules/sample")
        .expect("submodule pointer diff");
    assert!(pointer.is_gitlink);
    assert!(diff_text(pointer).contains("Subproject commit"));
    let tracked = diff
        .files
        .iter()
        .find(|file| file.path == "modules/sample/README.md")
        .expect("dirty child diff");
    assert!(diff_text(tracked).contains("+dirty child worktree"));
    assert!(!diff_text(tracked).contains("+committed in child"));
}

#[test]
fn staging_parent_ignores_submodule_worktree_only_changes() {
    let parent = init_repo_with_submodule();
    let child = parent.path().join("modules/sample");
    std::fs::write(child.join("README.md"), "dirty only\n").expect("modify tracked file");

    git_stage(path_str(parent.path()), None).unwrap();

    let repo = Repository::open(parent.path()).expect("open parent");
    let head = repo.head().unwrap().peel_to_tree().unwrap();
    let mut index = repo.index().unwrap();
    let index_tree = repo.find_tree(index.write_tree_to(&repo).unwrap()).unwrap();
    let diff = repo
        .diff_tree_to_tree(Some(&head), Some(&index_tree), None)
        .unwrap();
    assert_eq!(diff.deltas().len(), 0);
}

#[test]
fn stages_and_diffs_deleted_submodule_gitlink() {
    let parent = init_repo_with_submodule();
    std::fs::remove_dir_all(parent.path().join("modules/sample"))
        .expect("remove submodule checkout");

    let unstaged = git_status(path_str(parent.path())).unwrap();
    let entry = unstaged
        .entries
        .iter()
        .find(|entry| entry.path == "modules/sample" && entry.area == GitChangeArea::Unstaged)
        .expect("deleted submodule entry");
    assert!(entry.submodule.as_ref().unwrap().commit_changed);
    assert!(!entry.submodule.as_ref().unwrap().inspectable);

    git_stage(path_str(parent.path()), Some("modules/sample".to_string())).unwrap();
    let staged = git_status(path_str(parent.path())).unwrap();
    assert!(staged.entries.iter().any(|entry| {
        entry.path == "modules/sample"
            && entry.area == GitChangeArea::Staged
            && entry.status == GitChangeStatus::Deleted
    }));
    let diff = git_diff(
        path_str(parent.path()),
        "modules/sample".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert_eq!(diff.files[0].status, GitChangeStatus::Deleted);
    assert_eq!(diff.files[0].added, None);
    assert_eq!(diff.files[0].removed, Some(1));
    assert!(diff_text(&diff.files[0]).contains("deleted file mode 160000"));
}

#[test]
fn rejects_non_root_and_uninitialized_submodule_requests() {
    let parent = init_repo_with_submodule();
    let nested = git_submodule_status(
        path_str(parent.path()),
        "modules/sample/README.md".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap_err();
    assert_eq!(nested.kind, GitErrorKind::WorkspaceScope);

    run_git(
        parent.path(),
        &["submodule", "deinit", "-f", "modules/sample"],
    );
    let uninitialized = git_submodule_status(
        path_str(parent.path()),
        "modules/sample".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap_err();
    assert_eq!(uninitialized.kind, GitErrorKind::NotARepository);
    assert!(uninitialized.context.contains("Not Initialized"));
}
