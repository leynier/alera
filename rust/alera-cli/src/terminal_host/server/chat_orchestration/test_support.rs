use std::sync::{Arc, Mutex};
use std::time::Duration;

use alera_core::runtime::{
    ChatOrchestrationNewWorkspace, ChatOrchestrationTaskStatus, Project, ProjectKind, RuntimeStore,
    Workspace, WorkspaceKind, WorkspaceStatus,
};
use async_trait::async_trait;
use serde_json::{json, Value};
use tokio::sync::{mpsc, Notify};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_remote::{RemoteChatDirectory, RemoteChatRouter};
use crate::terminal_host::server::agent_chat_runtime::commands::{CallerCtx, SendInput};
use crate::terminal_host::server::agent_chat_runtime::events::NullSink;
use crate::terminal_host::server::agent_chat_runtime::{
    AgentChatRuntime, CreateChatInput, InstanceDirectory,
};
use crate::terminal_host::server::chat_orchestration_remote::RoutedChatRuntime;

use super::mock_provider::{MockProviderControl, MockProviderFactory};
use super::satellite_fixture::SatelliteTransport;
use super::{
    ChatCredentialLaunchHook, ChatOrchestrationRuntime, ChatOrchestrationService,
    ChatTargetResolver, OrchestrationCaller, OrchestrationEventSink, ResolvedChatTarget,
};

pub(super) const TEST_DEADLINE: Duration = Duration::from_secs(5);

pub(super) fn human(scope: &str) -> OrchestrationCaller {
    OrchestrationCaller::human(CallerCtx {
        scope: scope.into(),
        actor: scope.into(),
        mobile: scope.starts_with("mobile:"),
    })
}

pub(super) fn error_code(error: &HostError) -> &str {
    match error {
        HostError::Conflict { code, .. } => code,
        other => panic!("expected conflict: {other}"),
    }
}

pub(crate) struct TestHarness {
    pub directory: tempfile::TempDir,
    pub store: RuntimeStore,
    pub runtime: AgentChatRuntime,
    pub factory: Arc<MockProviderFactory>,
    pub(super) targets: Arc<FakeChatTargetResolver>,
    pub service: ChatOrchestrationService,
    pub(super) satellites: Arc<SatelliteTransport>,
    pub events: mpsc::UnboundedReceiver<(Value, ChatOrchestrationTaskStatus)>,
}

impl TestHarness {
    pub async fn new() -> Self {
        let directory = tempfile::tempdir().unwrap();
        Self::open(directory).await
    }

    pub async fn open(directory: tempfile::TempDir) -> Self {
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        add_workspace(&store, "ws-a", "project-a", "local").await;
        add_workspace(&store, "ws-b", "project-b", "ssh-b").await;
        let factory = Arc::new(MockProviderFactory::default());
        let runtime = AgentChatRuntime::new(
            store.clone(),
            factory.clone(),
            Arc::new(store.clone()),
            Box::new(NullSink),
            Arc::new(InstanceDirectory::default()),
        )
        .with_flush_delay(Duration::ZERO);
        let credentials =
            ChatCredentialLaunchHook::new(store.clone(), directory.path().into()).unwrap();
        runtime.register_launch_hook(credentials.clone());
        let satellites =
            SatelliteTransport::new(store.clone(), directory.path().into(), factory.clone());
        let routed = RoutedChatRuntime::new(
            runtime.clone(),
            RemoteChatRouter {
                store: store.clone(),
                directory: RemoteChatDirectory::default(),
                transport: satellites.clone(),
            },
        );
        let targets = Arc::new(FakeChatTargetResolver {
            store: store.clone(),
            runtime: routed.clone(),
            created: Mutex::new(Vec::new()),
            pause_creation: Mutex::new(None),
            creation_error: Mutex::new(None),
        });
        let (sender, events) = mpsc::unbounded_channel();
        let service = ChatOrchestrationService::new(
            store.clone(),
            runtime.clone(),
            targets.clone(),
            credentials,
        )
        .with_runtime(routed)
        .with_events(Arc::new(CommittedEventSink {
            store: store.clone(),
            sender,
        }));
        Self {
            directory,
            store,
            runtime,
            factory,
            targets,
            service,
            satellites,
            events,
        }
    }

    pub async fn restart(self) -> Self {
        self.runtime.shutdown().await;
        self.satellites.shutdown().await;
        self.store.pool().close().await;
        Self::open(self.directory).await
    }

    pub async fn create_chat(&self, workspace_id: &str, runtime_mode: &str) -> String {
        let response = self
            .service
            .runtime
            .create(
                CreateChatInput {
                    workspace_id: workspace_id.into(),
                    provider_instance_id: Some("codex".into()),
                    runtime_mode: Some(runtime_mode.into()),
                    ..Default::default()
                },
                human("desktop").ctx,
                None,
            )
            .await
            .unwrap();
        response["chatId"].as_str().unwrap().into()
    }

    pub async fn send_human(&self, chat_id: &str, id: &str, text: &str) -> Value {
        self.service
            .runtime
            .send(
                chat_id,
                SendInput {
                    client_message_id: id.into(),
                    text: text.into(),
                    attachments: Vec::new(),
                    delivery: "auto".into(),
                    model: None,
                    interaction_mode: None,
                    runtime_mode_ceiling: None,
                    origin: None,
                },
                human("desktop").ctx,
            )
            .await
            .unwrap()
    }

    pub async fn control(&self, chat_id: &str) -> Arc<MockProviderControl> {
        tokio::time::timeout(TEST_DEADLINE, self.factory.control(chat_id))
            .await
            .unwrap()
    }

    pub async fn agent(&self, chat_id: &str) -> OrchestrationCaller {
        let control = self.control(chat_id).await;
        tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
            .await
            .unwrap();
        let path = self
            .factory
            .launches
            .lock()
            .unwrap()
            .iter()
            .rev()
            .find(|launch| launch.chat_id == chat_id)
            .unwrap()
            .env["ALERA_CHAT_CREDENTIAL_FILE"]
            .clone();
        let token = std::fs::read_to_string(path).unwrap();
        let binding = self.service.bind_credential(&token).await.unwrap();
        OrchestrationCaller::agent(
            CallerCtx {
                scope: format!("chat:{chat_id}"),
                actor: format!("agent:{chat_id}"),
                mobile: false,
            },
            binding,
        )
    }

    pub async fn task_status(&self, task_id: &str, status: ChatOrchestrationTaskStatus) {
        tokio::time::timeout(TEST_DEADLINE, async {
            loop {
                if self
                    .store
                    .chat_orchestration_task(task_id)
                    .await
                    .unwrap()
                    .unwrap()
                    .status
                    == status
                {
                    return;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("task {task_id} did not reach {status:?}"));
    }

    pub async fn finish(self) {
        self.runtime.shutdown().await;
        self.satellites.shutdown().await;
        self.store.pool().close().await;
    }
}

pub(super) async fn add_workspace(store: &RuntimeStore, id: &str, project_id: &str, host_id: &str) {
    let now = chrono::Utc::now();
    store
        .upsert_project(Project {
            id: project_id.into(),
            name: project_id.into(),
            repo_path: format!("/tmp/{project_id}"),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    store
        .upsert_workspace(Workspace {
            id: id.into(),
            instance_id: format!("instance-{id}"),
            host_id: host_id.into(),
            project_id: project_id.into(),
            name: id.into(),
            branch: Some("main".into()),
            path: format!("/tmp/{project_id}/{id}"),
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
}

pub(super) struct CreationGate {
    pub entered: Notify,
    pub resume: Notify,
}

pub(super) struct FakeChatTargetResolver {
    store: RuntimeStore,
    runtime: Arc<dyn ChatOrchestrationRuntime>,
    pub created: Mutex<Vec<ChatOrchestrationNewWorkspace>>,
    pub pause_creation: Mutex<Option<Arc<CreationGate>>>,
    pub creation_error: Mutex<Option<HostError>>,
}

#[async_trait]
impl ChatTargetResolver for FakeChatTargetResolver {
    async fn resolve_existing_chat(&self, chat_id: &str) -> HostResult<ResolvedChatTarget> {
        let chat = self.runtime.snapshot(chat_id).await?;
        self.resolve_existing_workspace(chat["workspaceId"].as_str().unwrap())
            .await
    }
    async fn resolve_existing_workspace(
        &self,
        workspace_id: &str,
    ) -> HostResult<ResolvedChatTarget> {
        let workspace = self
            .store
            .find_workspace(workspace_id)
            .await
            .unwrap()
            .ok_or_else(|| {
                HostError::conflict("invalid_target", "Unknown workspace.", json!({}))
            })?;
        Ok(ResolvedChatTarget {
            workspace_id: workspace.id,
            project_id: Some(workspace.project_id),
            host_id: workspace.host_id,
        })
    }
    async fn create_workspace(
        &self,
        spec: &ChatOrchestrationNewWorkspace,
    ) -> HostResult<ResolvedChatTarget> {
        let id = {
            let mut created = self.created.lock().unwrap();
            created.push(spec.clone());
            format!("created-{}", created.len())
        };
        if let Some(error) = self.creation_error.lock().unwrap().clone() {
            return Err(error);
        }
        add_workspace(&self.store, &id, &spec.project_id, &spec.host_id).await;
        let gate = self.pause_creation.lock().unwrap().clone();
        if let Some(gate) = gate {
            gate.entered.notify_one();
            gate.resume.notified().await;
        }
        Ok(ResolvedChatTarget {
            workspace_id: id,
            project_id: Some(spec.project_id.clone()),
            host_id: spec.host_id.clone(),
        })
    }
}

struct CommittedEventSink {
    store: RuntimeStore,
    sender: mpsc::UnboundedSender<(Value, ChatOrchestrationTaskStatus)>,
}

#[async_trait]
impl OrchestrationEventSink for CommittedEventSink {
    async fn changed(&self, change: Value) {
        let task = self
            .store
            .chat_orchestration_task(change["taskId"].as_str().unwrap())
            .await
            .unwrap()
            .expect("task must exist before publishing its invalidation");
        let _ = self.sender.send((change, task.status));
    }
}
