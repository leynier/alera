use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus,
};
use async_trait::async_trait;
use tokio::sync::Notify;

use super::super::commands::{CallerCtx, ChatOp, SendInput};
use super::super::events::NullSink;
use super::super::provider_factory::{ProviderLaunch, ProviderLaunchHook};
use super::super::{AgentChatRuntime, CreateChatInput, InstanceDirectory};
use crate::terminal_host::server::chat_orchestration::mock_provider::MockProviderFactory;
use crate::terminal_host::server::chat_orchestration::ChatCredentialLaunchHook;

const TEST_DEADLINE: Duration = Duration::from_secs(5);

#[path = "startup_deferred_tests.rs"]
mod deferred_tests;

#[derive(Default)]
struct FirstStartupGate {
    attempts: AtomicUsize,
    cancelled: AtomicUsize,
    entered: Notify,
    release: Notify,
}

struct PendingPreparation<'a> {
    gate: &'a FirstStartupGate,
    completed: bool,
}

impl Drop for PendingPreparation<'_> {
    fn drop(&mut self) {
        if !self.completed {
            self.gate.cancelled.fetch_add(1, Ordering::SeqCst);
        }
    }
}

#[async_trait]
impl ProviderLaunchHook for FirstStartupGate {
    async fn prepare(&self, _: &mut ProviderLaunch) -> Result<(), String> {
        if self.attempts.fetch_add(1, Ordering::SeqCst) != 0 {
            return Ok(());
        }
        let mut pending = PendingPreparation {
            gate: self,
            completed: false,
        };
        self.entered.notify_one();
        self.release.notified().await;
        pending.completed = true;
        Ok(())
    }
}

struct StartupHarness {
    directory: tempfile::TempDir,
    store: RuntimeStore,
    runtime: AgentChatRuntime,
    factory: Arc<MockProviderFactory>,
    credentials: Arc<ChatCredentialLaunchHook>,
    gate: Arc<FirstStartupGate>,
}

impl StartupHarness {
    async fn new() -> Self {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        let now = chrono::Utc::now();
        store
            .upsert_project(Project {
                id: "startup-project".into(),
                name: "Startup Project".into(),
                repo_path: directory.path().to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        store
            .upsert_workspace(Workspace {
                id: "startup-workspace".into(),
                instance_id: "startup-workspace-instance".into(),
                host_id: "local".into(),
                project_id: "startup-project".into(),
                name: "Startup Workspace".into(),
                branch: Some("main".into()),
                path: directory.path().to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: WorkspaceKind::Linked,
                status: WorkspaceStatus::Active,
                source_branch: None,
                reuses_existing_branch: false,
                is_pinned: false,
                is_archived: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
                parent_workspace_id: None,
                section_id: None,
                child_count: 0,
            })
            .await
            .unwrap();
        let factory = Arc::new(MockProviderFactory::default());
        let runtime = AgentChatRuntime::new(
            store.clone(),
            factory.clone(),
            Arc::new(store.clone()),
            Box::new(NullSink),
            Arc::new(InstanceDirectory::default()),
        )
        .with_flush_delay(Duration::ZERO);
        let gate = Arc::new(FirstStartupGate::default());
        let credentials =
            ChatCredentialLaunchHook::new(store.clone(), directory.path().into()).unwrap();
        runtime.register_launch_hook(gate.clone());
        runtime.register_launch_hook(credentials.clone());
        Self {
            directory,
            store,
            runtime,
            factory,
            credentials,
            gate,
        }
    }

    async fn create_paused_chat(&self) -> String {
        let created = tokio::time::timeout(
            TEST_DEADLINE,
            self.runtime.create(
                CreateChatInput {
                    workspace_id: "startup-workspace".into(),
                    provider_instance_id: Some("codex".into()),
                    runtime_mode: Some("approval-required".into()),
                    ..Default::default()
                },
                CallerCtx::runtime(),
                None,
            ),
        )
        .await
        .unwrap()
        .unwrap();
        self.runtime
            .send(
                created["chatId"].as_str().unwrap(),
                SendInput {
                    client_message_id: "first-startup-message".into(),
                    text: "Start the deferred provider.".into(),
                    attachments: Vec::new(),
                    delivery: "auto".into(),
                    model: None,
                    reasoning_effort: None,
                    interaction_mode: None,
                    runtime_mode_ceiling: None,
                    origin: None,
                },
                CallerCtx::runtime(),
            )
            .await
            .unwrap();
        tokio::time::timeout(TEST_DEADLINE, self.gate.entered.notified())
            .await
            .unwrap();
        created["chatId"].as_str().unwrap().to_owned()
    }

    async fn live_credential_count(&self, chat_id: &str) -> i64 {
        sqlx::query_scalar(
            "SELECT COUNT(*) FROM chatOrchestrationCredentials WHERE chatId = ? AND revokedAt IS NULL",
        )
        .bind(chat_id)
        .fetch_one(self.store.pool())
        .await
        .unwrap()
    }

    async fn assert_cancelled_without_launch(&self, chat_id: &str) {
        assert_eq!(self.gate.cancelled.load(Ordering::SeqCst), 1);
        self.gate.release.notify_one();
        assert!(self.factory.launches.lock().unwrap().is_empty());
        assert_eq!(self.live_credential_count(chat_id).await, 0);
        assert_eq!(
            std::fs::read_dir(self.directory.path().join("agent-chat-mcp"))
                .unwrap()
                .count(),
            0
        );
    }

    async fn finish(self) {
        tokio::time::timeout(TEST_DEADLINE, self.runtime.shutdown())
            .await
            .unwrap();
        self.store.pool().close().await;
    }
}

#[tokio::test]
async fn close_cancels_startup_before_acknowledging_archive() {
    let harness = StartupHarness::new().await;
    let chat_id = harness.create_paused_chat().await;
    let closed = tokio::time::timeout(
        TEST_DEADLINE,
        harness
            .runtime
            .command(&chat_id, ChatOp::Close, CallerCtx::runtime(), None),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(closed["archived"], true);
    harness.assert_cancelled_without_launch(&chat_id).await;
    assert!(
        harness
            .store
            .agent_chat(&chat_id)
            .await
            .unwrap()
            .unwrap()
            .archived
    );
    harness.finish().await;
}

#[tokio::test]
async fn shutdown_cancels_startup_before_returning() {
    let harness = StartupHarness::new().await;
    let chat_id = harness.create_paused_chat().await;
    tokio::time::timeout(TEST_DEADLINE, harness.runtime.shutdown())
        .await
        .unwrap();
    harness.assert_cancelled_without_launch(&chat_id).await;
    harness.finish().await;
}

#[tokio::test]
async fn cancelled_launch_cannot_revoke_reopened_same_generation_credentials() {
    let harness = StartupHarness::new().await;
    let chat_id = harness.create_paused_chat().await;
    let generation = harness
        .store
        .agent_chat(&chat_id)
        .await
        .unwrap()
        .unwrap()
        .generation;
    tokio::time::timeout(
        TEST_DEADLINE,
        harness
            .runtime
            .command(&chat_id, ChatOp::Close, CallerCtx::runtime(), None),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(harness.gate.cancelled.load(Ordering::SeqCst), 1);
    let reopened = tokio::time::timeout(
        TEST_DEADLINE,
        harness.runtime.reopen(&chat_id, CallerCtx::runtime(), None),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(reopened["snapshot"]["archived"], false);
    tokio::time::timeout(
        TEST_DEADLINE,
        harness.runtime.command(
            &chat_id,
            ChatOp::Recover {
                mode: Some("restart".into()),
            },
            CallerCtx::runtime(),
            None,
        ),
    )
    .await
    .unwrap()
    .unwrap();
    let control = tokio::time::timeout(TEST_DEADLINE, harness.factory.control(&chat_id))
        .await
        .unwrap();
    let launch = harness.factory.launches.lock().unwrap()[0].clone();
    assert_eq!(launch.generation, generation);
    let token = std::fs::read_to_string(&launch.env["ALERA_CHAT_CREDENTIAL_FILE"]).unwrap();
    assert_eq!(
        harness.credentials.verify(&token).await.unwrap().generation,
        generation
    );

    harness.gate.release.notify_one();
    tokio::time::timeout(
        TEST_DEADLINE,
        harness.runtime.send(
            &chat_id,
            SendInput {
                client_message_id: "reopened-message".into(),
                text: "Continue in the reopened chat.".into(),
                attachments: Vec::new(),
                delivery: "auto".into(),
                model: None,
                reasoning_effort: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: None,
            },
            CallerCtx::runtime(),
        ),
    )
    .await
    .unwrap()
    .unwrap();
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    assert_eq!(harness.factory.launches.lock().unwrap().len(), 1);
    assert_eq!(harness.live_credential_count(&chat_id).await, 1);
    assert_eq!(
        harness.credentials.verify(&token).await.unwrap().generation,
        generation
    );
    assert_eq!(
        harness
            .store
            .agent_chat(&chat_id)
            .await
            .unwrap()
            .unwrap()
            .generation,
        generation
    );
    harness.finish().await;
}
