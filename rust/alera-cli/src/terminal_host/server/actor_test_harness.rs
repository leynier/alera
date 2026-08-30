//! A `ServerActor` wired up for tests, without a socket or a real PTY.
//!
//! Building one takes twenty-odd fields, so every test module that needs an
//! actor would otherwise carry its own copy of the same constructor.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::AtomicU64;
use std::sync::Arc;

use tokio::sync::mpsc;

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::history_store::TerminalHostHistoryStore;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceRegistry;
use crate::terminal_host::orchestration::message_waiters::MessageWaiterRegistry;
use crate::terminal_host::protocol::TerminalHostConfig;
use crate::terminal_host::server::resource_requests::ResourceMonitorState;
use crate::terminal_host::session::Session;
use alera_core::runtime::RuntimeStore;

use super::account_push_state::AccountPushState;
use super::browser_broker::BrowserBroker;
use super::client_delivery::LocalClientRole;
use super::{ClientKind, ClientState, ServerActor};

impl ClientState {
    /// Authenticated loopback client (the desktop app or a CLI).
    pub(super) fn local(handle: ClientHandle, app_client: bool) -> ClientState {
        ClientState {
            handle,
            authenticated: true,
            binary_frames: false,
            supports_mobile_emulator_tab_kind: false,
            supports_codex_tab_kind: false,
            kind: ClientKind::Local,
            local_role: if app_client {
                LocalClientRole::App
            } else {
                LocalClientRole::Cli
            },
            mobile_device_id: None,
            mobile_device_name: None,
            cloud_device_id: None,
            relay_client_id: None,
        }
    }
}

pub(super) fn mobile_client(handle: ClientHandle, device: &str) -> ClientState {
    ClientState {
        handle,
        authenticated: true,
        binary_frames: false,
        supports_mobile_emulator_tab_kind: false,
        supports_codex_tab_kind: false,
        kind: ClientKind::Mobile,
        local_role: LocalClientRole::Cli,
        mobile_device_id: Some(device.to_string()),
        mobile_device_name: Some(format!("{device} phone")),
        cloud_device_id: Some(format!("cloud-{device}")),
        relay_client_id: None,
    }
}

pub(super) fn local_client(handle: ClientHandle) -> ClientState {
    ClientState {
        handle,
        authenticated: true,
        binary_frames: false,
        supports_mobile_emulator_tab_kind: false,
        supports_codex_tab_kind: false,
        kind: ClientKind::Local,
        local_role: LocalClientRole::Cli,
        mobile_device_id: None,
        mobile_device_name: None,
        cloud_device_id: None,
        relay_client_id: None,
    }
}

pub(super) async fn test_actor(
    dir: &tempfile::TempDir,
    clients: HashMap<u64, ClientState>,
    sessions: HashMap<String, Session>,
) -> ServerActor {
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
    let account_push = AccountPushState::new(dir.path().to_path_buf(), runtime_store.clone())
        .await
        .unwrap();
    let (inbox, _rx) = mpsc::unbounded_channel();
    ServerActor {
        runtime_dir: dir.path().to_path_buf(),
        control_file_path: dir.path().join("runtime-host.json"),
        token: "token".to_string(),
        config: TerminalHostConfig::default(),
        store,
        runtime_store,
        automation_wake: Arc::new(tokio::sync::Notify::new()),
        automations_active: false,
        sessions,
        ssh_bootstrap_jobs: HashMap::new(),
        project_clone_jobs: HashMap::new(),
        agent_title_jobs: HashMap::new(),
        managed_workspace_jobs: 0,
        emulator_requests: Default::default(),
        agent_quota_cache: None,
        configuration_transfers: Default::default(),
        account_push,
        clients,
        mobile_prompt_file_uploads: HashMap::new(),
        pending_output_writes: HashMap::new(),
        agent_presence: AgentPresenceRegistry::default(),
        orchestration_waiters: MessageWaiterRegistry::default(),
        orchestration_delivery_in_flight: HashSet::new(),
        orchestration_delivery_backpressured: HashSet::new(),
        orchestration_activity_last_recorded: HashMap::new(),
        coordinators: HashMap::new(),
        resources: ResourceMonitorState::default(),
        terminal_pulses: Default::default(),
        browser: BrowserBroker::default(),
        emulators: None,
        codex: None,
        codex_presence: HashMap::new(),
        codex_presence_scheduled: false,
        codex_pending_messages: HashMap::new(),
        codex_flush_scheduled: HashSet::new(),
        inbox,
        next_client_id: Arc::new(AtomicU64::new(10)),
        mobile_gateway: None,
        shutdown_gen: 0,
        disposed: false,
    }
}
