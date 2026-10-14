//! One [`HostLink`] per remote host, shared by every forwarded request. The
//! registry is cloned into spawned tasks so the server actor never awaits an
//! ssh handshake itself.
//!
//! Connecting runs in its own task ([`super::host_link_connect_attempt`]);
//! keeping links up, retrying and closing idle ones is the supervisor's job
//! ([`super::host_link_supervisor`]). Per-host state lives in
//! [`super::host_link_slot`].

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};
use tokio::sync::Notify;

use super::host_error::{HostError, HostResult};
use super::host_link::{HostLink, HostLinkLauncher, HostLinkState};
use super::host_link_slot::{HostLinkStatus, HostSlot};
use super::host_link_supervisor::HostLinkPolicy;
use super::server::ServerCommand;

#[derive(Clone)]
pub(crate) struct HostLinkRegistry {
    pub(super) store: RuntimeStore,
    pub(super) inbox: crate::terminal_host::ServerInbox,
    pub(super) launcher: Arc<HostLinkLauncher>,
    pub(super) policy: HostLinkPolicy,
    pub(super) wake: Arc<Notify>,
    hosts: Arc<Mutex<HashMap<String, Arc<HostSlot>>>>,
    /// Satellite-issued session ids (Quick Open) mapped to the host that owns
    /// them, so follow-up requests that carry only the session id still route.
    remote_sessions: Arc<Mutex<HashMap<String, String>>>,
    pub(crate) provider_setup_sessions: super::server::remote_provider_setup::RemoteSetupSessions,
}

impl HostLinkRegistry {
    pub(crate) fn new(store: RuntimeStore, inbox: crate::terminal_host::ServerInbox) -> Self {
        Self::with_launcher(store, inbox, Arc::new(super::host_link::ssh_launcher))
    }

    pub(crate) fn with_launcher(
        store: RuntimeStore,
        inbox: crate::terminal_host::ServerInbox,
        launcher: Arc<HostLinkLauncher>,
    ) -> Self {
        Self::with_policy(store, inbox, launcher, HostLinkPolicy::default())
    }

    pub(crate) fn with_policy(
        store: RuntimeStore,
        inbox: crate::terminal_host::ServerInbox,
        launcher: Arc<HostLinkLauncher>,
        policy: HostLinkPolicy,
    ) -> Self {
        Self {
            store,
            inbox,
            launcher,
            policy,
            wake: Arc::new(Notify::new()),
            hosts: Arc::new(Mutex::new(HashMap::new())),
            remote_sessions: Arc::new(Mutex::new(HashMap::new())),
            provider_setup_sessions: Default::default(),
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

    pub(super) fn slot(&self, host_id: &str) -> Arc<HostSlot> {
        self.hosts
            .lock()
            .expect("host link registry poisoned")
            .entry(host_id.to_string())
            .or_default()
            .clone()
    }

    pub(super) fn existing_slot(&self, host_id: &str) -> Option<Arc<HostSlot>> {
        self.hosts
            .lock()
            .expect("host link registry poisoned")
            .get(host_id)
            .cloned()
    }

    pub(super) fn host_ids(&self) -> Vec<String> {
        let mut ids: Vec<String> = self
            .hosts
            .lock()
            .expect("host link registry poisoned")
            .keys()
            .cloned()
            .collect();
        ids.sort();
        ids
    }

    /// The attached link for `host_id`, connecting first when needed. Must be
    /// awaited from a spawned task, never from the actor loop. Dropping the
    /// future does not cancel the connect: other callers and the supervisor
    /// still get its result.
    pub(crate) async fn link(&self, host_id: &str) -> HostResult<Arc<HostLink>> {
        let slot = self.slot(host_id);
        let (outcome, started) = {
            let mut state = slot.lock();
            state.touch();
            if let Some(link) = state.live_link() {
                return Ok(link);
            }
            match &state.attempt {
                Some(attempt) => (attempt.outcome.clone(), false),
                None => (self.start_attempt(host_id, &slot, &mut state), true),
            }
        };
        if started {
            self.publish(host_id, false);
        }
        Self::await_attempt(host_id, outcome).await
    }

    /// The link if it is attached right now, without connecting. Safe to call
    /// from the actor.
    pub(crate) fn attached_link(&self, host_id: &str) -> Option<Arc<HostLink>> {
        let slot = self.existing_slot(host_id)?;
        let mut state = slot.lock();
        let link = state.live_link()?;
        state.touch();
        Some(link)
    }

    /// [`Self::attached_link`] for background polls, which must not keep an
    /// otherwise idle link open.
    pub(crate) fn peek_link(&self, host_id: &str) -> Option<Arc<HostLink>> {
        self.existing_slot(host_id)?.lock().live_link()
    }

    /// Starts a connect unless one is running, the link is up, a retry is
    /// already scheduled, the user paused the host, or its last failure was
    /// one a retry cannot fix. Never waits.
    pub(crate) fn request_connect(&self, host_id: &str) {
        let slot = self.slot(host_id);
        {
            let mut state = slot.lock();
            if state.paused
                || state.live_link().is_some()
                || state.attempt.is_some()
                || state.retry.is_some()
                || state
                    .failure_kind
                    .is_some_and(|kind| !kind.retries() && state.last_error.is_some())
            {
                return;
            }
            self.start_attempt(host_id, &slot, &mut state);
        }
        self.publish(host_id, false);
    }

    /// The user's Connect: the host stays linked until they disconnect it.
    pub(crate) async fn connect_explicitly(&self, host_id: &str) -> HostResult<Arc<HostLink>> {
        {
            let slot = self.slot(host_id);
            let mut state = slot.lock();
            state.explicit = true;
            state.paused = false;
        }
        self.link(host_id).await
    }

    /// Clears a Disconnect, because the user did something that needs the
    /// link (opened a remote terminal).
    pub(crate) fn resume(&self, host_id: &str) {
        let Some(slot) = self.existing_slot(host_id) else {
            return;
        };
        let changed = std::mem::replace(&mut slot.lock().paused, false);
        if changed {
            self.publish(host_id, false);
            self.reevaluate();
        }
    }

    /// The target's endpoint changed: a link to the old address is closed,
    /// and a pause, a failure that stopped retries and the backoff no longer
    /// describe the host.
    pub(crate) async fn target_changed(&self, host_id: &str) {
        if let Some(slot) = self.existing_slot(host_id) {
            let link = {
                let mut state = slot.lock();
                state.paused = false;
                state.failure_kind = None;
                state.last_error = None;
                state.backoff.reset();
                state.bump_generation();
                state.take_link()
            };
            if let Some(link) = link {
                link.close().await;
            }
            self.publish(host_id, false);
        }
        self.reevaluate();
    }

    /// The user's Disconnect: closes the link and pauses the host so nothing
    /// reconnects it until they Connect again.
    pub(crate) async fn disconnect(&self, host_id: &str) {
        let link = {
            let slot = self.slot(host_id);
            let mut state = slot.lock();
            state.bump_generation();
            state.paused = true;
            state.explicit = false;
            state.last_error = None;
            state.failure_kind = None;
            state.backoff.reset();
            state.take_link()
        };
        if let Some(link) = link {
            link.close().await;
        }
        self.publish(host_id, false);
    }

    /// Forgets the host entirely (its target was removed).
    pub(crate) async fn drop_host(&self, host_id: &str) {
        let setup_cleanups = self.provider_setup_sessions.forget_host(host_id);
        let slot = self
            .hosts
            .lock()
            .expect("host link registry poisoned")
            .remove(host_id);
        let Some(slot) = slot else {
            return;
        };
        let link = {
            let mut state = slot.lock();
            state.bump_generation();
            state.take_link()
        };
        if let Some(link) = link {
            super::server::remote_provider_setup::close_removed_host_setups(
                link.clone(),
                setup_cleanups,
            )
            .await;
            link.close().await;
        }
        self.publish(host_id, false);
    }

    /// Hub shutdown: every link closes and nothing retries.
    pub(crate) async fn disconnect_all(&self) {
        let slots: Vec<(String, Arc<HostSlot>)> = self
            .hosts
            .lock()
            .expect("host link registry poisoned")
            .iter()
            .map(|(id, slot)| (id.clone(), slot.clone()))
            .collect();
        for (host_id, slot) in slots {
            let link = {
                let mut state = slot.lock();
                state.bump_generation();
                state.last_error = None;
                state.take_link()
            };
            if let Some(link) = link {
                link.close().await;
            }
            self.publish(&host_id, false);
        }
    }

    /// The pipe behind `host_id`'s link ended. Idempotent: the registry's own
    /// close watcher and the actor both report it.
    pub(crate) fn note_closed(&self, host_id: &str, error: &str) {
        let Some(slot) = self.existing_slot(host_id) else {
            return;
        };
        {
            let mut state = slot.lock();
            if !state.link.as_ref().is_some_and(|link| link.is_closed()) {
                return;
            }
            state.take_link();
            if state.restarting {
                state.last_error = None;
                state.failure_kind = None;
                if state.wants_link() {
                    self.schedule_retry(host_id, &mut state, true);
                }
            } else {
                let kind = super::host_link_failure::classify_attach_failure(error);
                state.last_error = Some(error.to_string());
                state.failure_kind = Some(kind);
                if state.wants_link() && kind.retries() {
                    self.schedule_retry(host_id, &mut state, false);
                }
            }
        }
        self.publish(host_id, false);
    }

    /// A runtime restart begins: an attempt in flight is abandoned and the
    /// next close of the current link is expected rather than a failure.
    pub(crate) fn begin_restart(&self, host_id: &str) {
        let slot = self.slot(host_id);
        let mut state = slot.lock();
        state.bump_generation();
        state.restarting = true;
    }

    pub(crate) fn end_restart(&self, host_id: &str) {
        if let Some(slot) = self.existing_slot(host_id) {
            slot.lock().restarting = false;
        }
    }

    /// Waits for the current link to close. `false` on timeout.
    pub(crate) async fn wait_closed(&self, host_id: &str, deadline: Duration) -> bool {
        let link = self
            .existing_slot(host_id)
            .and_then(|slot| slot.lock().link.clone());
        match link {
            Some(link) => tokio::time::timeout(deadline, link.closed()).await.is_ok(),
            None => true,
        }
    }

    /// Closes the current link without pausing the host, for a restart whose
    /// old runtime kept the link open or answered again with the old version.
    pub(crate) async fn close_for_restart(&self, host_id: &str) {
        let link = self
            .existing_slot(host_id)
            .and_then(|slot| slot.lock().take_link());
        if let Some(link) = link {
            link.close().await;
        }
        self.publish(host_id, false);
    }

    /// The satellite's record for a workspace already mirrored over `link`
    /// with the same registration.
    pub(crate) fn mirrored(
        &self,
        host_id: &str,
        link: &Arc<HostLink>,
        workspace_id: &str,
        registration_hash: u64,
    ) -> Option<Value> {
        let slot = self.existing_slot(host_id)?;
        let state = slot.lock();
        let current = state.link.as_ref()?;
        if !Arc::ptr_eq(current, link) {
            return None;
        }
        state
            .mirrored
            .get(workspace_id)
            .filter(|(hash, _)| *hash == registration_hash)
            .map(|(_, record)| record.clone())
    }

    pub(crate) fn note_mirrored(
        &self,
        host_id: &str,
        link: &Arc<HostLink>,
        workspace_id: &str,
        registration_hash: u64,
        record: Value,
    ) {
        let Some(slot) = self.existing_slot(host_id) else {
            return;
        };
        let mut state = slot.lock();
        if state
            .link
            .as_ref()
            .is_some_and(|current| Arc::ptr_eq(current, link))
        {
            state
                .mirrored
                .insert(workspace_id.to_string(), (registration_hash, record));
        }
    }

    pub(crate) fn state(&self, host_id: &str) -> HostLinkState {
        self.existing_slot(host_id)
            .map(|slot| slot.lock().link_state())
            .unwrap_or(HostLinkState::Disconnected)
    }

    pub(crate) fn status(&self, host_id: &str) -> HostLinkStatus {
        let slot = self.existing_slot(host_id).unwrap_or_default();
        let status = slot.lock().status(self.policy.idle_close);
        status
    }

    /// Hosts with a live link right now. Callers that only want to use a link
    /// that already exists (periodic polls) start here instead of `link`, which
    /// would open one.
    pub(crate) fn attached_host_ids(&self) -> Vec<String> {
        self.hosts
            .lock()
            .expect("host link registry poisoned")
            .iter()
            .filter(|(_, slot)| slot.lock().live_link().is_some())
            .map(|(host_id, _)| host_id.clone())
            .collect()
    }

    /// `hostLink.status` payload: every host the registry has seen.
    pub(crate) fn snapshot(&self) -> Value {
        let links: Vec<Value> = self
            .host_ids()
            .into_iter()
            .map(|id| self.status_payload(&id))
            .collect();
        json!({ "links": links })
    }

    /// One host's status with its id, as `hostLinkChanged` carries it.
    pub(crate) fn status_payload(&self, host_id: &str) -> Value {
        let mut value = serde_json::to_value(self.status(host_id)).unwrap_or(Value::Null);
        if let Some(object) = value.as_object_mut() {
            object.insert("hostId".into(), json!(host_id));
        }
        value
    }

    pub(super) fn publish(&self, host_id: &str, newly_attached: bool) {
        let _ = self.inbox.send(ServerCommand::HostLinkStateChanged {
            host_id: host_id.to_string(),
            newly_attached,
        });
    }

    pub(super) fn cancelled(host_id: &str) -> HostError {
        HostError::state(format!(
            "The connection to host {host_id} was cancelled before it attached."
        ))
    }
}

#[cfg(test)]
#[path = "host_link_registry_tests.rs"]
mod tests;
