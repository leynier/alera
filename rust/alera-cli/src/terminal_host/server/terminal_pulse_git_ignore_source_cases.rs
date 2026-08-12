use std::time::{Duration, Instant};
use std::{sync::atomic::AtomicBool, sync::Arc};

use git2::Repository;

use super::super::{GitConfigEnvironment, WorkspacePulseWatcher};

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

#[test]
fn shell_xdg_config_controls_ignore_discovery_and_reconciliation() {
    let root = tempfile::tempdir().unwrap();
    let workspace = root.path().join("workspace");
    std::fs::create_dir(&workspace).unwrap();
    Repository::init(&workspace).unwrap();
    let ignored = workspace.join("ignored");
    std::fs::create_dir(&ignored).unwrap();
    std::fs::write(ignored.join("hidden.txt"), "hidden").unwrap();

    let xdg = root.path().join("shell-xdg");
    std::fs::create_dir_all(xdg.join("git")).unwrap();
    let exclude = root.path().join("shell-global-ignore");
    std::fs::write(&exclude, "ignored/\n").unwrap();
    std::fs::write(
        xdg.join("git/config"),
        format!("[core]\n\texcludesFile = {}\n", exclude.display()),
    )
    .unwrap();
    let environment = GitConfigEnvironment::new(
        Some(root.path().join("shell-home")),
        Some(xdg),
        None,
        None,
        false,
    );
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking_with_environment(
        "workspace-1".to_string(),
        workspace.clone(),
        1,
        inbox,
        environment,
        std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
    )
    .unwrap();

    std::fs::write(&exclude, "").unwrap();

    assert_file_changed(&mut commands, "shell XDG exclude edit");
    std::fs::write(ignored.join("visible.txt"), "visible").unwrap();
    assert_file_changed(&mut commands, "file unignored through shell XDG config");
}

#[test]
fn changing_an_included_config_reconciles_its_exclude_file() {
    let root = tempfile::tempdir().unwrap();
    let workspace = root.path().join("workspace");
    std::fs::create_dir(&workspace).unwrap();
    let repository = Repository::init(&workspace).unwrap();
    let ignored = workspace.join("ignored");
    std::fs::create_dir(&ignored).unwrap();
    std::fs::write(ignored.join("hidden.txt"), "hidden").unwrap();
    let exclude = root.path().join("included-ignore");
    std::fs::write(&exclude, "ignored/\n").unwrap();
    let included = root.path().join("included-config");
    std::fs::write(
        &included,
        format!("[core]\n\texcludesFile = {}\n", exclude.display()),
    )
    .unwrap();
    repository
        .config()
        .unwrap()
        .set_str("include.path", "../../included-config")
        .unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        workspace.clone(),
        1,
        inbox,
    )
    .unwrap();

    std::fs::write(&included, "").unwrap();

    assert_file_changed(&mut commands, "included Git config edit");
    std::fs::write(ignored.join("visible.txt"), "visible").unwrap();
    assert_file_changed(&mut commands, "file unignored through included config");
}

#[test]
fn default_ignore_file_is_not_parsed_as_git_config() {
    let root = tempfile::tempdir().unwrap();
    let workspace = root.path().join("workspace");
    std::fs::create_dir(&workspace).unwrap();
    Repository::init(&workspace).unwrap();
    let xdg = root.path().join("xdg");
    std::fs::create_dir_all(xdg.join("git")).unwrap();
    std::fs::write(xdg.join("git/ignore"), "ignored/\n").unwrap();
    let environment =
        GitConfigEnvironment::new(Some(root.path().join("home")), Some(xdg), None, None, false);
    let (inbox, _commands) = tokio::sync::mpsc::unbounded_channel();

    let watcher = WorkspacePulseWatcher::start_blocking_with_environment(
        "workspace-1".to_string(),
        workspace,
        1,
        inbox,
        environment,
        Arc::new(AtomicBool::new(false)),
    );

    assert!(watcher.is_ok());
}

#[test]
fn future_exclude_source_is_observed_from_its_existing_ancestor() {
    let root = tempfile::tempdir().unwrap();
    let workspace = root.path().join("workspace");
    std::fs::create_dir(&workspace).unwrap();
    let repository = Repository::init(&workspace).unwrap();
    let ignored = workspace.join("ignored");
    std::fs::create_dir(&ignored).unwrap();
    std::fs::write(ignored.join("visible.txt"), "visible").unwrap();
    let exclude = root.path().join("future/config/exclude");
    repository
        .config()
        .unwrap()
        .set_str("core.excludesFile", exclude.to_str().unwrap())
        .unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    let _watcher = WorkspacePulseWatcher::start_blocking(
        "workspace-1".to_string(),
        workspace.clone(),
        1,
        inbox,
    )
    .unwrap();

    std::fs::create_dir_all(exclude.parent().unwrap()).unwrap();
    std::fs::write(&exclude, "ignored/\n").unwrap();
    wait_for_git_source_reconciliation();
    drain_commands(&mut commands);
    std::fs::write(ignored.join("hidden.txt"), "hidden").unwrap();

    assert_no_file_changed(&mut commands, "newly created exclude source");
}

#[test]
fn watcher_setup_honors_an_existing_cancellation() {
    let root = tempfile::tempdir().unwrap();
    let workspace = root.path().join("workspace");
    std::fs::create_dir(&workspace).unwrap();
    Repository::init(&workspace).unwrap();
    let cancelled = Arc::new(AtomicBool::new(true));
    let (inbox, _commands) = tokio::sync::mpsc::unbounded_channel();

    let result = WorkspacePulseWatcher::start_blocking_with_environment(
        "workspace-1".to_string(),
        workspace,
        1,
        inbox,
        GitConfigEnvironment::from_process(),
        cancelled,
    );

    let error = result.err().expect("cancelled setup should fail");
    assert!(error.to_string().contains("setup was cancelled"));
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

fn wait_for_git_source_reconciliation() {
    std::thread::sleep(Duration::from_millis(400));
}

fn drain_commands(
    commands: &mut tokio::sync::mpsc::UnboundedReceiver<
        crate::terminal_host::server::ServerCommand,
    >,
) {
    while commands.try_recv().is_ok() {}
}

fn assert_no_file_changed(
    commands: &mut tokio::sync::mpsc::UnboundedReceiver<
        crate::terminal_host::server::ServerCommand,
    >,
    context: &str,
) {
    let deadline = Instant::now() + Duration::from_millis(500);
    while Instant::now() < deadline {
        if let Ok(command) = commands.try_recv() {
            assert!(
                !matches!(
                    command,
                    crate::terminal_host::server::ServerCommand::TerminalPulseFileChanged { .. }
                ),
                "file change was unexpectedly reported after {context}"
            );
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}
