//! Terminal viewport driver state (the mobile presence lock): a mobile client
//! that attaches, writes, or resizes a session claims the viewport and the PTY
//! follows the phone's dims; the desktop sees a `terminalDriverChanged` event,
//! and takes the seat back through `terminal.reclaim`, which restores the last
//! desktop dims. Modeled on Orca's mobile presence lock.

use serde_json::{json, Value};

use crate::terminal_host::protocol::event;
use crate::terminal_host::session::SessionDriver;

use super::{ClientKind, ServerActor};

impl ServerActor {
    /// Marks the mobile client behind [`client_id`] as the driver of
    /// [`session_id`], applying its viewport when given. First claim away from
    /// the desktop snapshots the current dims for the later restore.
    pub(super) fn claim_mobile_driver(
        &mut self,
        client_id: u64,
        session_id: &str,
        viewport: Option<(u16, u16)>,
    ) {
        let Some(client) = self.clients.get(&client_id) else {
            return;
        };
        if client.kind != ClientKind::Mobile {
            return;
        }
        let Some(device_id) = client.mobile_device_id.clone() else {
            return;
        };
        let device_name = client
            .mobile_device_name
            .clone()
            .unwrap_or_else(|| device_id.clone());
        let Some(session) = self.sessions.get_mut(session_id) else {
            return;
        };
        let next = SessionDriver::Mobile {
            client_id,
            device_id,
            device_name,
        };
        let driver_changed = session.driver != next;
        if driver_changed && !matches!(session.driver, SessionDriver::Mobile { .. }) {
            // Remember what the desktop had so reclaim can restore it.
            if session.desktop_dims.is_none() {
                session.desktop_dims = Some(session.current_dims);
            }
        }
        session.driver = next;
        let dims_changed = viewport.is_some_and(|dims| dims != session.current_dims);
        if let Some((cols, rows)) = viewport {
            session.resize(cols, rows);
        }
        if driver_changed || dims_changed {
            self.broadcast_driver_changed(session_id);
        }
    }

    /// Desktop "Take Back": restore the desktop dims and seat the desktop as
    /// driver. Idempotent; returns whether there was a mobile claim or held
    /// phone-fit override to undo.
    pub(super) fn reclaim_terminal_for_desktop(&mut self, session_id: &str) -> bool {
        let Some(session) = self.sessions.get_mut(session_id) else {
            return false;
        };
        let had_claim = matches!(session.driver, SessionDriver::Mobile { .. })
            || session.desktop_dims.is_some();
        if !had_claim {
            return false;
        }
        if let Some((cols, rows)) = session.desktop_dims.take() {
            session.resize(cols, rows);
        }
        session.driver = SessionDriver::Desktop;
        self.broadcast_driver_changed(session_id);
        true
    }

    /// Releases every session the disconnecting or detaching client was
    /// driving, restoring the desktop dims. Called on `detach` and on client
    /// disposal so an app kill or network drop frees the desktop.
    pub(super) fn release_mobile_driver_for_client(&mut self, client_id: u64) {
        let driven: Vec<String> = self
            .sessions
            .iter()
            .filter_map(|(id, session)| match &session.driver {
                SessionDriver::Mobile {
                    client_id: driver_client,
                    ..
                } if *driver_client == client_id => Some(id.clone()),
                _ => None,
            })
            .collect();
        for session_id in driven {
            if let Some(session) = self.sessions.get_mut(&session_id) {
                if let Some((cols, rows)) = session.desktop_dims.take() {
                    session.resize(cols, rows);
                }
                session.driver = SessionDriver::Idle;
            }
            self.broadcast_driver_changed(&session_id);
        }
    }

    /// Per-session variant of the release used by `detach`: only the session
    /// being detached is freed, other tabs the phone drives keep their claim.
    pub(super) fn release_mobile_driver_for_session(&mut self, client_id: u64, session_id: &str) {
        let mut released = false;
        if let Some(session) = self.sessions.get_mut(session_id) {
            let driven_by_client = matches!(
                &session.driver,
                SessionDriver::Mobile { client_id: driver_client, .. }
                    if *driver_client == client_id
            );
            if driven_by_client {
                if let Some((cols, rows)) = session.desktop_dims.take() {
                    session.resize(cols, rows);
                }
                session.driver = SessionDriver::Idle;
                released = true;
            }
        }
        if released {
            self.broadcast_driver_changed(session_id);
        }
    }

    pub(super) fn terminal_driver_list_payload(&self) -> Value {
        json!(self
            .sessions
            .iter()
            .map(|(id, session)| {
                json!({
                    "sessionId": id,
                    "driver": session.driver.payload(),
                })
            })
            .collect::<Vec<_>>())
    }

    pub(super) fn broadcast_driver_changed(&mut self, session_id: &str) {
        let Some(session) = self.sessions.get(session_id) else {
            return;
        };
        let (cols, rows) = session.current_dims;
        let payload = json!({
            "sessionId": session_id,
            "driver": session.driver.payload(),
            "cols": cols,
            "rows": rows,
        });
        self.broadcast_authenticated(event("terminalDriverChanged", payload));
    }
}

// Contract tests mirroring Orca's mobile-presence-lock scenarios: claim
// snapshots desktop dims, local resizes are recorded but suppressed while the
// phone drives, reclaim restores and is idempotent, disconnect releases, and
// the most recent mobile actor wins.
#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};
    use std::sync::atomic::AtomicU64;
    use std::sync::Arc;

    use tokio::sync::mpsc;

    use alera_core::runtime::RuntimeStore;

    use crate::terminal_host::client::ClientHandle;
    use crate::terminal_host::history_store::TerminalHostHistoryStore;
    use crate::terminal_host::orchestration::agent_presence::AgentPresenceRegistry;
    use crate::terminal_host::orchestration::message_waiters::MessageWaiterRegistry;
    use crate::terminal_host::protocol::TerminalHostConfig;
    use crate::terminal_host::session::{Session, SessionDriver};

    use super::super::{ClientKind, ClientState, ServerActor};

    fn mobile_client(handle: ClientHandle, device: &str) -> ClientState {
        ClientState {
            handle,
            authenticated: true,
            kind: ClientKind::Mobile,
            mobile_device_id: Some(device.to_string()),
            mobile_device_name: Some(format!("{device} phone")),
        }
    }

    fn local_client(handle: ClientHandle) -> ClientState {
        ClientState {
            handle,
            authenticated: true,
            kind: ClientKind::Local,
            mobile_device_id: None,
            mobile_device_name: None,
        }
    }

    async fn actor(dir: &tempfile::TempDir, clients: HashMap<u64, ClientState>) -> ServerActor {
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::from([("s1".to_string(), Session::driver_test_stub("s1", 120, 40))]),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            agent_quota_cache: None,
            clients,
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            inbox,
            next_client_id: Arc::new(AtomicU64::new(10)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        }
    }

    fn mobile_driver(device: &str, client_id: u64) -> SessionDriver {
        SessionDriver::Mobile {
            client_id,
            device_id: device.to_string(),
            device_name: format!("{device} phone"),
        }
    }

    #[tokio::test]
    async fn mobile_claim_snapshots_desktop_dims_and_applies_viewport() {
        let dir = tempfile::tempdir().unwrap();
        let (handle, mut out_rx) = ClientHandle::test_channels();
        let mut actor = actor(&dir, HashMap::from([(2, mobile_client(handle, "a"))])).await;

        actor.claim_mobile_driver(2, "s1", Some((48, 22)));

        let session = &actor.sessions["s1"];
        assert_eq!(session.driver, mobile_driver("a", 2));
        assert_eq!(session.desktop_dims, Some((120, 40)));
        assert_eq!(session.current_dims, (48, 22));
        let event = out_rx.try_recv().expect("driver change broadcast");
        assert_eq!(event["event"], "terminalDriverChanged");
        assert_eq!(event["payload"]["sessionId"], "s1");
        assert_eq!(event["payload"]["driver"]["kind"], "mobile");
        assert_eq!(event["payload"]["driver"]["deviceName"], "a phone");
        assert_eq!(event["payload"]["cols"], 48);
        assert_eq!(event["payload"]["rows"], 22);
    }

    #[tokio::test]
    async fn most_recent_mobile_actor_wins_and_keeps_the_first_snapshot() {
        let dir = tempfile::tempdir().unwrap();
        let (handle_a, _rx_a) = ClientHandle::test_channels();
        let (handle_b, _rx_b) = ClientHandle::test_channels();
        let mut actor = actor(
            &dir,
            HashMap::from([
                (2, mobile_client(handle_a, "a")),
                (3, mobile_client(handle_b, "b")),
            ]),
        )
        .await;

        actor.claim_mobile_driver(2, "s1", Some((48, 22)));
        actor.claim_mobile_driver(3, "s1", Some((52, 24)));

        let session = &actor.sessions["s1"];
        assert_eq!(session.driver, mobile_driver("b", 3));
        // The restore target stays the original desktop dims, not phone a's.
        assert_eq!(session.desktop_dims, Some((120, 40)));
        assert_eq!(session.current_dims, (52, 24));
    }

    #[tokio::test]
    async fn reclaim_restores_desktop_dims_and_is_idempotent() {
        let dir = tempfile::tempdir().unwrap();
        let (handle, _rx) = ClientHandle::test_channels();
        let mut actor = actor(&dir, HashMap::from([(2, mobile_client(handle, "a"))])).await;
        actor.claim_mobile_driver(2, "s1", Some((48, 22)));

        assert!(actor.reclaim_terminal_for_desktop("s1"));
        let session = &actor.sessions["s1"];
        assert_eq!(session.driver, SessionDriver::Desktop);
        assert_eq!(session.current_dims, (120, 40));
        assert_eq!(session.desktop_dims, None);

        assert!(!actor.reclaim_terminal_for_desktop("s1"));
        assert!(!actor.reclaim_terminal_for_desktop("missing"));
    }

    #[tokio::test]
    async fn release_for_client_restores_dims_and_goes_idle() {
        let dir = tempfile::tempdir().unwrap();
        let (handle, _rx) = ClientHandle::test_channels();
        let mut actor = actor(&dir, HashMap::from([(2, mobile_client(handle, "a"))])).await;
        actor.claim_mobile_driver(2, "s1", Some((48, 22)));

        actor.release_mobile_driver_for_client(2);

        let session = &actor.sessions["s1"];
        assert_eq!(session.driver, SessionDriver::Idle);
        assert_eq!(session.current_dims, (120, 40));
        assert_eq!(session.desktop_dims, None);
    }

    #[tokio::test]
    async fn session_scoped_release_only_frees_that_session() {
        let dir = tempfile::tempdir().unwrap();
        let (handle, _rx) = ClientHandle::test_channels();
        let mut actor = actor(&dir, HashMap::from([(2, mobile_client(handle, "a"))])).await;
        actor
            .sessions
            .insert("s2".to_string(), Session::driver_test_stub("s2", 100, 30));
        actor.claim_mobile_driver(2, "s1", Some((48, 22)));
        actor.claim_mobile_driver(2, "s2", Some((48, 22)));

        actor.release_mobile_driver_for_session(2, "s1");

        assert_eq!(actor.sessions["s1"].driver, SessionDriver::Idle);
        assert_eq!(actor.sessions["s2"].driver, mobile_driver("a", 2));
        // A release for a session the client does not drive is a no-op.
        actor.release_mobile_driver_for_session(99, "s2");
        assert_eq!(actor.sessions["s2"].driver, mobile_driver("a", 2));
    }

    #[tokio::test]
    async fn local_clients_never_claim_and_driver_list_reports_state() {
        let dir = tempfile::tempdir().unwrap();
        let (handle, _rx) = ClientHandle::test_channels();
        let mut actor = actor(&dir, HashMap::from([(1, local_client(handle))])).await;

        actor.claim_mobile_driver(1, "s1", Some((48, 22)));
        assert_eq!(actor.sessions["s1"].driver, SessionDriver::Idle);
        assert_eq!(actor.sessions["s1"].current_dims, (120, 40));

        let list = actor.terminal_driver_list_payload();
        let entries = list.as_array().unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0]["sessionId"], "s1");
        assert_eq!(entries[0]["driver"]["kind"], "idle");
    }
}
