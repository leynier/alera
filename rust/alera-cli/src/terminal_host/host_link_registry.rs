//! One [`HostLink`] per remote host, opened on demand and shared by every
//! forwarded request. The registry is cloned into spawned tasks so the server
//! actor never awaits an ssh handshake itself.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedSender;

use super::host_error::{HostError, HostResult};
use super::host_link::{HostLink, HostLinkLauncher, HostLinkState};
use super::server::ServerCommand;

#[derive(Default)]
struct HostSlot {
    /// Serialises connects for one host so concurrent callers share one ssh.
    connect: tokio::sync::Mutex<()>,
    connecting: AtomicBool,
    link: Mutex<Option<Arc<HostLink>>>,
    last_error: Mutex<Option<String>>,
}

#[derive(Clone)]
pub(crate) struct HostLinkRegistry {
    store: RuntimeStore,
    inbox: UnboundedSender<ServerCommand>,
    launcher: Arc<HostLinkLauncher>,
    hosts: Arc<Mutex<HashMap<String, Arc<HostSlot>>>>,
    /// Satellite-issued session ids (Quick Open) mapped to the host that owns
    /// them, so follow-up requests that carry only the session id still route.
    remote_sessions: Arc<Mutex<HashMap<String, String>>>,
}

impl HostLinkRegistry {
    pub(crate) fn new(store: RuntimeStore, inbox: UnboundedSender<ServerCommand>) -> Self {
        Self::with_launcher(store, inbox, Arc::new(super::host_link::ssh_launcher))
    }

    pub(crate) fn with_launcher(
        store: RuntimeStore,
        inbox: UnboundedSender<ServerCommand>,
        launcher: Arc<HostLinkLauncher>,
    ) -> Self {
        Self {
            store,
            inbox,
            launcher,
            hosts: Arc::new(Mutex::new(HashMap::new())),
            remote_sessions: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub(crate) fn note_remote_session(&self, session_id: &str, host_id: &str) {
        self.remote_sessions
            .lock()
            .expect("host link sessions poisoned")
            .insert(session_id.to_string(), host_id.to_string());
    }

    pub(crate) fn remote_session_host(&self, session_id: &str) -> Option<String> {
        self.remote_sessions
            .lock()
            .expect("host link sessions poisoned")
            .get(session_id)
            .cloned()
    }

    pub(crate) fn forget_remote_session(&self, session_id: &str) -> Option<String> {
        self.remote_sessions
            .lock()
            .expect("host link sessions poisoned")
            .remove(session_id)
    }

    fn slot(&self, host_id: &str) -> Arc<HostSlot> {
        self.hosts
            .lock()
            .expect("host link registry poisoned")
            .entry(host_id.to_string())
            .or_default()
            .clone()
    }

    fn live_link(slot: &HostSlot) -> Option<Arc<HostLink>> {
        slot.link
            .lock()
            .expect("host slot poisoned")
            .as_ref()
            .filter(|link| !link.is_closed())
            .cloned()
    }

    /// The attached link for `host_id`, connecting first when needed. Must be
    /// awaited from a spawned task, never from the actor loop.
    pub(crate) async fn link(&self, host_id: &str) -> HostResult<Arc<HostLink>> {
        let slot = self.slot(host_id);
        if let Some(link) = Self::live_link(&slot) {
            return Ok(link);
        }
        let _guard = slot.connect.lock().await;
        if let Some(link) = Self::live_link(&slot) {
            return Ok(link);
        }
        slot.connecting.store(true, Ordering::Release);
        self.publish(host_id);
        let result = self.connect(host_id).await;
        match &result {
            Ok(link) => {
                *slot.link.lock().expect("host slot poisoned") = Some(link.clone());
                *slot.last_error.lock().expect("host slot poisoned") = None;
            }
            Err(error) => {
                *slot.link.lock().expect("host slot poisoned") = None;
                *slot.last_error.lock().expect("host slot poisoned") = Some(error.wire_message());
            }
        }
        slot.connecting.store(false, Ordering::Release);
        self.publish(host_id);
        result
    }

    async fn connect(&self, host_id: &str) -> HostResult<Arc<HostLink>> {
        let target = crate::ssh_remote::require_bootstrapped_ssh_target(&self.store, host_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        HostLink::connect_with(&target, self.inbox.clone(), self.launcher.as_ref()).await
    }

    pub(crate) async fn disconnect(&self, host_id: &str) {
        let slot = self.slot(host_id);
        let link = slot.link.lock().expect("host slot poisoned").take();
        *slot.last_error.lock().expect("host slot poisoned") = None;
        if let Some(link) = link {
            link.close().await;
        }
        self.publish(host_id);
    }

    pub(crate) async fn disconnect_all(&self) {
        let ids: Vec<String> = self
            .hosts
            .lock()
            .expect("host link registry poisoned")
            .keys()
            .cloned()
            .collect();
        for id in ids {
            self.disconnect(&id).await;
        }
    }

    /// Called by the actor when the reader task reports the pipe closed.
    pub(crate) fn note_closed(&self, host_id: &str, error: &str) {
        let slot = self.slot(host_id);
        let closed = {
            let mut link = slot.link.lock().expect("host slot poisoned");
            match link.as_ref() {
                Some(current) if current.is_closed() => {
                    *link = None;
                    true
                }
                _ => false,
            }
        };
        if closed {
            *slot.last_error.lock().expect("host slot poisoned") = Some(error.to_string());
        }
    }

    pub(crate) fn state(&self, host_id: &str) -> HostLinkState {
        let slot = self
            .hosts
            .lock()
            .expect("host link registry poisoned")
            .get(host_id)
            .cloned();
        let Some(slot) = slot else {
            return HostLinkState::Disconnected;
        };
        if let Some(link) = Self::live_link(&slot) {
            return HostLinkState::Attached {
                attachment: link.attachment().clone(),
            };
        }
        if slot.connecting.load(Ordering::Acquire) {
            return HostLinkState::Connecting;
        }
        let last_error = slot.last_error.lock().expect("host slot poisoned").clone();
        match last_error {
            Some(error) => HostLinkState::Failed { error },
            None => HostLinkState::Disconnected,
        }
    }

    /// `hostLink.status` payload: every host the registry has seen.
    pub(crate) fn snapshot(&self) -> Value {
        let ids: Vec<String> = self
            .hosts
            .lock()
            .expect("host link registry poisoned")
            .keys()
            .cloned()
            .collect();
        let mut links: Vec<Value> = ids
            .into_iter()
            .map(|id| {
                let mut value = serde_json::to_value(self.state(&id)).unwrap_or(Value::Null);
                if let Some(object) = value.as_object_mut() {
                    object.insert("hostId".into(), json!(id));
                }
                value
            })
            .collect();
        links.sort_by(|a, b| a["hostId"].as_str().cmp(&b["hostId"].as_str()));
        json!({ "links": links })
    }

    fn publish(&self, host_id: &str) {
        let _ = self.inbox.send(ServerCommand::HostLinkStateChanged {
            host_id: host_id.to_string(),
        });
    }
}
