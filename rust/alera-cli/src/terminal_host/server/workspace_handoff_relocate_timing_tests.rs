use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;
use std::sync::mpsc::Receiver;
use std::time::Duration;

use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::managed_workspace_handoff::{
    hand_off_managed_workspace, ManagedWorkspaceHandOffRequest, ManagedWorkspaceHandOnRequest,
};
use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_prompt_injection::{
    build_agent_prompt_paste_bytes, AGENT_PROMPT_SUBMIT,
};
use crate::terminal_host::server::runtime_mutations::RuntimeMutationRequest;
use crate::terminal_host::session::{Session, TestQueuedWrite};

use super::super::actor_test_harness::{local_client, test_actor};
use super::super::{ServerActor, ServerCommand};
use super::{handoff_chdir_bytes, handoff_notify_message, WorkspaceHandoffDirection};

fn recv_write(rx: &Receiver<TestQueuedWrite>) -> TestQueuedWrite {
    rx.recv_timeout(Duration::from_secs(1))
        .expect("expected a queued terminal write")
}

fn assert_no_write(rx: &Receiver<TestQueuedWrite>) {
    assert!(
        rx.try_recv().is_err(),
        "hand on must not write to the terminal before it succeeds"
    );
}

struct Fixture {
    _root: tempfile::TempDir,
    actor: ServerActor,
    responses: UnboundedReceiver<ClientFrame>,
    commands: UnboundedReceiver<ServerCommand>,
    child: Workspace,
    main_path: String,
}

impl Fixture {
    async fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let repo = root.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);

        let (handle, responses) = ClientHandle::test_channels();
        let mut actor = test_actor(
            &root,
            HashMap::from([(1, local_client(handle))]),
            HashMap::new(),
        )
        .await;
        let (inbox, commands) = tokio::sync::mpsc::unbounded_channel();
        actor.inbox = inbox;

        let workspaces = root.path().join("workspaces");
        std::fs::create_dir(&workspaces).unwrap();
        actor
            .runtime_store
            .set_workspace_directory(Some(&workspaces.to_string_lossy()))
            .await
            .unwrap();

        let now = Utc::now();
        actor
            .runtime_store
            .upsert_project(Project {
                id: "project".into(),
                name: "Project".into(),
                repo_path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        actor
            .runtime_store
            .upsert_workspace(Workspace {
                id: "main".into(),
                instance_id: "main-instance".into(),
                host_id: LOCAL_HOST_ID.into(),
                project_id: "project".into(),
                name: "Main".into(),
                branch: Some("main".into()),
                path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: WorkspaceKind::Main,
                status: WorkspaceStatus::Active,
                source_branch: None,
                reuses_existing_branch: false,
                is_pinned: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
                parent_workspace_id: None,
                section_id: None,
                child_count: 0,
            })
            .await
            .unwrap();

        let child_path = workspaces.join("hand-on-child");
        let created = hand_off_managed_workspace(
            &actor.runtime_store,
            ManagedWorkspaceHandOffRequest {
                id: "main".into(),
                branch: "feat/hand-on".into(),
                name: Some("Hand On Child".into()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(child_path.to_string_lossy().into_owned()),
                defer_setup: true,
                setup_script_directory: None,
            },
        )
        .await
        .unwrap();

        Self {
            _root: root,
            actor,
            responses,
            commands,
            child: created.workspace,
            main_path: repo.to_string_lossy().into_owned(),
        }
    }

    fn insert_main_shell_in_child(&mut self) -> Receiver<TestQueuedWrite> {
        let mut shell = Session::driver_test_stub("main-shell", 80, 24);
        shell.workspace_id = "main".into();
        shell.working_directory = self.child.path.clone();
        let rx = shell.attach_test_input();
        self.actor.sessions.insert("main-shell".into(), shell);
        rx
    }

    fn insert_main_agent_in_child(&mut self) -> Receiver<TestQueuedWrite> {
        let mut agent = Session::driver_test_stub("main-agent", 80, 24);
        agent.workspace_id = "main".into();
        agent.working_directory = self.child.path.clone();
        let rx = agent.attach_test_input();
        self.actor.sessions.insert("main-agent".into(), agent);
        self.actor
            .agent_presence
            .update("main-agent", "codex".into(), AgentPresenceState::Done);
        rx
    }

    fn insert_live_child_shell(&mut self) -> Receiver<TestQueuedWrite> {
        let mut shell = Session::driver_test_stub("child-shell", 80, 24);
        shell.workspace_id = self.child.id.clone();
        shell.working_directory = self.child.path.clone();
        let rx = shell.attach_test_input();
        self.actor.sessions.insert("child-shell".into(), shell);
        rx
    }

    async fn prepare_hand_on(
        &mut self,
        close_sessions: bool,
    ) -> crate::terminal_host::host_error::HostResult<
        crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown,
    > {
        self.actor
            .prepare_runtime_mutation(&RuntimeMutationRequest::HandOnWorkspace {
                request: ManagedWorkspaceHandOnRequest {
                    id: self.child.id.clone(),
                    close_sessions,
                    active_workspace_id: None,
                },
            })
            .await
    }

    async fn request_hand_on(&mut self) -> Value {
        self.actor
            .handle_line(
                1,
                json!({
                    "id": 1,
                    "type": "workspace.handOn",
                    "payload": {
                        "id": self.child.id,
                        "closeSessions": true,
                    },
                })
                .to_string(),
            )
            .await;
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                tokio::select! {
                    command = self.commands.recv() => {
                        self.actor.handle(command.expect("runtime command")).await;
                    }
                    frame = self.responses.recv() => {
                        let response = frame
                            .expect("client frame")
                            .as_json()
                            .expect("json response");
                        if response["id"] == 1 {
                            return response;
                        }
                    }
                }
            }
        })
        .await
        .expect("workspace.handOn should finish")
    }
}

#[tokio::test]
async fn prepare_hand_on_does_not_relocate_sessions() {
    let mut fixture = Fixture::new().await;
    let shell_rx = fixture.insert_main_shell_in_child();
    let agent_rx = fixture.insert_main_agent_in_child();
    let child_path = fixture.child.path.clone();

    fixture.prepare_hand_on(true).await.unwrap();

    assert_no_write(&shell_rx);
    assert_no_write(&agent_rx);
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("main-shell")
            .unwrap()
            .working_directory,
        child_path
    );
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("main-agent")
            .unwrap()
            .working_directory,
        child_path
    );
}

#[tokio::test]
async fn prepare_hand_on_failure_does_not_relocate_sessions() {
    let mut fixture = Fixture::new().await;
    let child_rx = fixture.insert_live_child_shell();
    let shell_rx = fixture.insert_main_shell_in_child();
    let child_path = fixture.child.path.clone();

    let error = match fixture.prepare_hand_on(false).await {
        Err(error) => error,
        Ok(_) => panic!("expected prepare to fail while a child session is live"),
    };
    assert!(error.to_string().to_lowercase().contains("live"), "{error}");

    assert_no_write(&child_rx);
    assert_no_write(&shell_rx);
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("child-shell")
            .unwrap()
            .working_directory,
        child_path
    );
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("main-shell")
            .unwrap()
            .working_directory,
        child_path
    );
}

#[tokio::test]
async fn failed_hand_on_does_not_relocate_sessions() {
    let mut fixture = Fixture::new().await;
    std::fs::write(
        PathBuf::from(&fixture.main_path).join("main-dirty.txt"),
        "nope\n",
    )
    .unwrap();
    let shell_rx = fixture.insert_main_shell_in_child();
    let agent_rx = fixture.insert_main_agent_in_child();
    let child_path = fixture.child.path.clone();

    let response = fixture.request_hand_on().await;
    assert_eq!(response["ok"], false, "{response}");
    assert!(
        response["error"]
            .as_str()
            .unwrap_or_default()
            .to_lowercase()
            .contains("local changes"),
        "{response}"
    );

    assert_no_write(&shell_rx);
    assert_no_write(&agent_rx);
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("main-shell")
            .unwrap()
            .working_directory,
        child_path
    );
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("main-agent")
            .unwrap()
            .working_directory,
        child_path
    );
}

#[tokio::test]
async fn successful_hand_on_relocates_and_notifies() {
    let mut fixture = Fixture::new().await;
    let shell_rx = fixture.insert_main_shell_in_child();
    let agent_rx = fixture.insert_main_agent_in_child();
    let child_path = fixture.child.path.clone();
    let main_path = fixture.main_path.clone();

    let response = fixture.request_hand_on().await;
    assert_eq!(response["ok"], true, "{response}");

    assert_eq!(recv_write(&shell_rx).bytes, handoff_chdir_bytes(&main_path));
    let agent_write = recv_write(&agent_rx);
    let expected =
        handoff_notify_message(WorkspaceHandoffDirection::HandOn, &child_path, &main_path);
    assert_eq!(agent_write.bytes, build_agent_prompt_paste_bytes(&expected));
    assert_eq!(
        agent_write.deferred_bytes.as_deref(),
        Some(AGENT_PROMPT_SUBMIT)
    );
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("main-shell")
            .unwrap()
            .working_directory,
        main_path
    );
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("main-agent")
            .unwrap()
            .working_directory,
        main_path
    );
}

fn init_git_repo(repo: &Path) {
    run_git(repo, &["init"]);
    run_git(repo, &["config", "user.email", "test@example.com"]);
    run_git(repo, &["config", "user.name", "Test"]);
    std::fs::write(repo.join("README.md"), "hello\n").unwrap();
    run_git(repo, &["add", "README.md"]);
    run_git(repo, &["commit", "-m", "initial"]);
    run_git(repo, &["branch", "-M", "main"]);
}

#[allow(clippy::disallowed_methods)]
fn run_git(repo: &Path, args: &[&str]) {
    let output = StdCommand::new("git")
        .args(args)
        .current_dir(repo)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {} failed\nstdout:\n{}\nstderr:\n{}",
        args.join(" "),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
