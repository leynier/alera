use std::time::{Duration, Instant};

use git2::Repository;

use super::super::WorkspacePulseWatcher;

#[test]
fn changing_the_active_global_exclude_reconciles_pruned_directories() {
    let fixture = GlobalExcludeFixture::new("ignored/\n");
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        fixture.workspace.clone(),
        1,
        inbox,
    )
    .unwrap();

    std::fs::write(&fixture.exclude, "").unwrap();

    assert_file_changed(&mut commands, "global exclude edit");
    std::fs::write(fixture.workspace.join("ignored/visible.txt"), "visible").unwrap();
    assert_file_changed(&mut commands, "newly unignored file");
}

#[test]
fn repointing_core_excludes_file_reconciles_the_new_rules() {
    let fixture = GlobalExcludeFixture::new("ignored/\n");
    let replacement = fixture.root.path().join("replacement-ignore");
    std::fs::write(&replacement, "").unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        fixture.workspace.clone(),
        1,
        inbox,
    )
    .unwrap();

    fixture
        .repository
        .config()
        .unwrap()
        .set_str("core.excludesFile", replacement.to_str().unwrap())
        .unwrap();

    assert_file_changed(&mut commands, "core.excludesFile repoint");
    std::fs::write(fixture.workspace.join("ignored/visible.txt"), "visible").unwrap();
    assert_file_changed(&mut commands, "file visible through replacement exclude");
}

struct GlobalExcludeFixture {
    root: tempfile::TempDir,
    workspace: std::path::PathBuf,
    exclude: std::path::PathBuf,
    repository: Repository,
}

impl GlobalExcludeFixture {
    fn new(rule: &str) -> Self {
        let root = tempfile::tempdir().unwrap();
        let workspace = root.path().join("workspace");
        std::fs::create_dir(&workspace).unwrap();
        let repository = Repository::init(&workspace).unwrap();
        let exclude = root.path().join("global-ignore");
        std::fs::write(&exclude, rule).unwrap();
        repository
            .config()
            .unwrap()
            .set_str("core.excludesFile", exclude.to_str().unwrap())
            .unwrap();
        let ignored = workspace.join("ignored");
        std::fs::create_dir(&ignored).unwrap();
        std::fs::write(ignored.join("hidden.txt"), "hidden").unwrap();
        Self {
            root,
            workspace,
            exclude,
            repository,
        }
    }
}

fn assert_file_changed(
    commands: &mut tokio::sync::mpsc::UnboundedReceiver<
        crate::terminal_host::server::ServerCommand,
    >,
    context: &str,
) {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        if let Ok(command) = commands.try_recv() {
            if matches!(
                command,
                crate::terminal_host::server::ServerCommand::TerminalPulseFileChanged {
                    workspace_id,
                    watcher_generation: 1,
                    ..
                } if workspace_id == "workspace-1"
            ) {
                return;
            }
        }
        assert!(
            Instant::now() < deadline,
            "file change was not reported after {context}"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
}
