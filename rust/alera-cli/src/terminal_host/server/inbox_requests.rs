use std::sync::atomic::{AtomicI64, Ordering};

use alera_core::runtime::{
    InboxQuestionStatus, InboxThreadFilter, NewInboxQuestion, OrchestrationMessageType,
    INBOX_HISTORY_SECONDS, INBOX_MAX_EXPIRY_SECONDS,
};
use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::client_delivery::LocalClientRole;
use super::orchestration_validation::{optional_string, parse_priority, require_string};
use super::{ClientKind, ServerActor};

/// Where questions asked from the desktop and phone UIs live, so both show
/// the same conversations.
pub(super) const UI_INBOX: &str = "ext:user";
const SUBJECT_FROM_BODY_CHARS: usize = 80;
// Leaves room for "..." and a "Re: " prefix under the 256-byte subject limit.
const SUBJECT_FROM_BODY_MAX_BYTES: usize = 200;
const PRUNE_INTERVAL_SECONDS: i64 = 60 * 60;
const EXPIRY_SWEEP_SECONDS: i64 = 30;

// Process-wide so every actor in a test binary shares one cadence; pruning is
// idempotent, so a shared clock can only skip redundant work.
static LAST_PRUNE_UNIX: AtomicI64 = AtomicI64::new(0);
static LAST_EXPIRY_SWEEP_UNIX: AtomicI64 = AtomicI64::new(0);

/// Store errors carry a `code: message` prefix; surface the code so clients
/// can branch on it.
pub(super) fn inbox_error(error: anyhow::Error) -> HostError {
    let text = error.to_string();
    match text.split_once(": ") {
        Some((code, message)) if code.starts_with("inbox_") || code == "message_too_large" => {
            HostError::conflict(code, message, json!({}))
        }
        _ => HostError::state(text),
    }
}

impl ServerActor {
    /// Runs before `handle_request`, so it applies the mobile allowlist itself.
    pub(super) async fn handle_inbox_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        self.require_authenticated_local_request(client_id, request_type)?;
        self.prune_inbox_history_if_due().await;
        match request_type {
            "inbox.summary" => self.inbox_summary().await.map(Some),
            "inbox.threads" => self.inbox_threads(payload).await.map(Some),
            "inbox.thread" => self.inbox_thread(payload).await.map(Some),
            "inbox.targets" => self.inbox_targets(payload).await.map(Some),
            "inbox.ask" => self.inbox_ask(client_id, payload).await.map(Some),
            "inbox.cancel" => self.inbox_cancel(client_id, payload).await.map(Some),
            "inbox.markRead" => self.inbox_mark_read(payload).await.map(Some),
            "inbox.purge" => self.inbox_purge(payload).await.map(Some),
            "inbox.wait" => self.inbox_wait(client_id, request_id, payload).await,
            other => Err(HostError::state(format!("Unknown inbox request: {other}"))),
        }
    }

    /// Announces a new inbox revision to every authenticated client, phones
    /// included, when anything inbox-related changed since the last call.
    pub(super) async fn broadcast_inbox_change(&self) {
        if let Ok(Some(revision)) = self.runtime_store.take_inbox_change().await {
            self.broadcast_authenticated(event("inboxChanged", json!({ "revision": revision })));
        }
    }

    /// Expiry is otherwise lazy: without this, a question that passes its
    /// deadline while nobody asks the host keeps showing as pending.
    pub(super) async fn sweep_inbox_expiry_if_due(&mut self) {
        let now = Utc::now().timestamp();
        if now - LAST_EXPIRY_SWEEP_UNIX.load(Ordering::Relaxed) < EXPIRY_SWEEP_SECONDS {
            return;
        }
        LAST_EXPIRY_SWEEP_UNIX.store(now, Ordering::Relaxed);
        self.expire_inbox_questions().await;
    }

    /// Expires overdue questions, re-checks every parked inbox wait (a read
    /// may have expired its question before this sweep), and announces the
    /// new revision.
    pub(super) async fn expire_inbox_questions(&mut self) {
        if let Err(error) = self.runtime_store.expire_inbox_questions().await {
            tracing::warn!("[inbox] expiring questions failed: {error}");
        }
        for inbox in self.orchestration_waiters.inbox_wait_handles() {
            self.notify_message_arrived(&inbox, OrchestrationMessageType::Status)
                .await;
        }
        self.broadcast_inbox_change().await;
    }

    async fn prune_inbox_history_if_due(&self) {
        let now = Utc::now().timestamp();
        let last = LAST_PRUNE_UNIX.load(Ordering::Relaxed);
        if now - last < PRUNE_INTERVAL_SECONDS.min(INBOX_HISTORY_SECONDS) {
            return;
        }
        LAST_PRUNE_UNIX.store(now, Ordering::Relaxed);
        if let Err(error) = self.runtime_store.prune_inbox_history().await {
            tracing::warn!("[inbox] pruning history failed: {error}");
        }
    }

    pub(super) async fn inbox_revision(&self) -> HostResult<i64> {
        self.runtime_store
            .inbox_revision()
            .await
            .map_err(inbox_error)
    }

    async fn inbox_summary(&self) -> HostResult<Value> {
        let items = self
            .runtime_store
            .inbox_summary()
            .await
            .map_err(inbox_error)?;
        Ok(json!({
            "kind": "inboxes",
            "items": items,
            "revision": self.inbox_revision().await?,
        }))
    }

    async fn inbox_threads(&self, payload: &Value) -> HostResult<Value> {
        let status = match optional_string(payload, "status") {
            None => None,
            Some(raw) => Some(
                InboxQuestionStatus::parse(&raw)
                    .ok_or_else(|| HostError::format(format!("unknown inbox status: {raw}")))?,
            ),
        };
        let filter = InboxThreadFilter {
            inbox: optional_string(payload, "inbox"),
            workspace_id: optional_string(payload, "workspaceId"),
            status,
            before_sequence: payload.get("before").and_then(Value::as_i64),
            limit: payload.get("limit").and_then(Value::as_i64).unwrap_or(50),
        };
        let page = self
            .runtime_store
            .inbox_threads(filter.clone())
            .await
            .map_err(inbox_error)?;
        Ok(json!({
            "kind": "inboxThreads",
            "items": page.items,
            "nextBefore": page.next_before,
            "filters": {
                "inbox": filter.inbox,
                "workspaceId": filter.workspace_id,
                "status": filter.status,
            },
            "revision": self.inbox_revision().await?,
        }))
    }

    /// A thread is named by its root id or by any message in it.
    pub(super) async fn requested_thread_id(&self, payload: &Value) -> HostResult<String> {
        let id = optional_string(payload, "threadId")
            .or_else(|| optional_string(payload, "questionId"))
            .ok_or_else(|| HostError::format("threadId or questionId is required."))?;
        let message = self
            .runtime_store
            .orchestration_message_by_id(&id)
            .await
            .map_err(inbox_error)?
            .ok_or_else(|| {
                HostError::conflict(
                    "inbox_thread_not_found",
                    format!("No inbox thread or question {id}"),
                    json!({}),
                )
            })?;
        Ok(message.thread_id.unwrap_or(message.id))
    }

    async fn inbox_thread(&self, payload: &Value) -> HostResult<Value> {
        let thread_id = self.requested_thread_id(payload).await?;
        if payload.get("markRead").and_then(Value::as_bool) == Some(true) {
            self.mark_thread_read(&thread_id).await?;
        }
        let detail = self
            .runtime_store
            .inbox_thread(&thread_id)
            .await
            .map_err(inbox_error)?
            .ok_or_else(|| {
                HostError::conflict(
                    "inbox_thread_not_found",
                    format!("No inbox thread {thread_id}"),
                    json!({}),
                )
            })?;
        let recipient = self.inbox_recipient(&detail.thread.recipient);
        Ok(json!({
            "thread": detail.thread,
            "messages": detail.messages,
            "recipient": recipient,
            "revision": self.inbox_revision().await?,
        }))
    }

    pub(super) async fn mark_thread_read(&self, thread_id: &str) -> HostResult<u64> {
        let Some(detail) = self
            .runtime_store
            .inbox_thread(thread_id)
            .await
            .map_err(inbox_error)?
        else {
            return Ok(0);
        };
        let ids: Vec<String> = detail
            .messages
            .iter()
            .filter(|entry| entry.message.to_handle == detail.thread.inbox && !entry.message.read)
            .map(|entry| entry.message.id.clone())
            .collect();
        self.runtime_store
            .mark_inbox_messages_read(&ids)
            .await
            .map_err(inbox_error)
    }

    /// How a question to `handle` would reach the agent right now.
    pub(super) fn inbox_recipient(&self, handle: &str) -> Value {
        let session = self.sessions.get(handle);
        let session_live = session.is_some_and(|session| session.running());
        let presence = self.agent_presence.get(handle);
        let delivery_mode = if self.is_active_coordinator_handle(handle) {
            "check"
        } else if session_live && presence.is_some() {
            "paste"
        } else {
            "unavailable"
        };
        json!({
            "handle": handle,
            "sessionLive": session_live,
            "workspaceId": session.map(|session| session.workspace_id.clone()),
            "tabId": session.map(|session| session.tab_id.clone()),
            "agent": presence.map(|entry| entry.agent_type.clone()),
            "presence": presence.map(|entry| entry.state.as_str()),
            "deliveryMode": delivery_mode,
        })
    }

    async fn inbox_targets(&self, payload: &Value) -> HostResult<Value> {
        let workspace = optional_string(payload, "workspaceId");
        let mut handles: Vec<&String> = self
            .sessions
            .iter()
            .filter(|(handle, session)| {
                session.running()
                    && self.agent_presence.get(handle).is_some()
                    && workspace
                        .as_ref()
                        .is_none_or(|workspace| &session.workspace_id == workspace)
            })
            .map(|(handle, _)| handle)
            .collect();
        handles.sort();
        let mut items = Vec::with_capacity(handles.len());
        for handle in handles {
            let mut target = self.inbox_recipient(handle);
            target["tabTitle"] = json!(self.inbox_tab_title(handle).await);
            items.push(target);
        }
        Ok(json!({
            "kind": "inboxTargets",
            "items": items,
            "filters": { "workspaceId": workspace },
        }))
    }

    async fn inbox_tab_title(&self, handle: &str) -> Option<String> {
        let tab_id = self.sessions.get(handle)?.tab_id.clone();
        self.runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .ok()
            .flatten()
            .map(|tab| tab.title)
    }

    /// Picks the recipient: an explicit terminal, or the single running agent
    /// of a workspace, optionally narrowed by agent type.
    fn resolve_inbox_recipient(&self, payload: &Value) -> HostResult<String> {
        if let Some(to) = optional_string(payload, "to") {
            if !self.sessions.contains_key(&to) {
                return Err(HostError::conflict(
                    "inbox_unknown_recipient",
                    format!("No terminal {to} is known to this runtime."),
                    json!({}),
                ));
            }
            return Ok(to);
        }
        let workspace = optional_string(payload, "workspaceId").ok_or_else(|| {
            HostError::format("to or workspaceId is required to choose who to ask.")
        })?;
        let agent = optional_string(payload, "agent");
        let mut candidates: Vec<(String, String)> = self
            .sessions
            .iter()
            .filter(|(_, session)| session.running() && session.workspace_id == workspace)
            .filter_map(|(handle, _)| {
                let presence = self.agent_presence.get(handle)?;
                agent
                    .as_ref()
                    .is_none_or(|agent| presence.agent_type.eq_ignore_ascii_case(agent))
                    .then(|| (handle.clone(), presence.agent_type.clone()))
            })
            .collect();
        candidates.sort();
        match candidates.as_slice() {
            [(handle, _)] => Ok(handle.clone()),
            [] => Err(HostError::conflict(
                "inbox_no_recipient",
                format!("No running agent in workspace {workspace} matches."),
                json!({}),
            )),
            many => Err(HostError::conflict(
                "inbox_ambiguous_recipient",
                "More than one running agent matches; pass to or agent.",
                json!({
                    "candidates": many
                        .iter()
                        .map(|(handle, agent)| json!({ "handle": handle, "agent": agent }))
                        .collect::<Vec<_>>(),
                }),
            )),
        }
    }

    /// The surface a request came from, decided by the connection.
    pub(super) fn inbox_origin(&self, client_id: u64) -> Value {
        let Some(client) = self.clients.get(&client_id) else {
            return json!({ "surface": "cli" });
        };
        match client.kind {
            ClientKind::Mobile => json!({
                "surface": "mobile",
                "deviceId": client.mobile_device_id,
                "deviceName": client.mobile_device_name,
            }),
            ClientKind::Local if client.local_role == LocalClientRole::App => {
                json!({ "surface": "desktop" })
            }
            ClientKind::Local => json!({ "surface": "cli" }),
        }
    }

    async fn inbox_ask(&mut self, client_id: u64, payload: &Value) -> HostResult<Value> {
        let body = require_string(payload, "body")?;
        // A follow-up names any question of its thread and inherits the
        // thread's inbox and recipient unless they are given explicitly; a
        // workspace only narrows the recipient of a new thread.
        let thread_root = match optional_string(payload, "threadId") {
            Some(_) => {
                let root_id = self.requested_thread_id(payload).await?;
                self.runtime_store
                    .orchestration_message_by_id(&root_id)
                    .await
                    .map_err(inbox_error)?
            }
            None => None,
        };
        let inbox = optional_string(payload, "inbox")
            .or_else(|| thread_root.as_ref().map(|root| root.from_handle.clone()))
            .unwrap_or_else(|| UI_INBOX.to_string());
        let recipient = match &thread_root {
            Some(root) if optional_string(payload, "to").is_none() => {
                if !self.sessions.contains_key(&root.to_handle) {
                    return Err(HostError::conflict(
                        "inbox_unknown_recipient",
                        format!(
                            "The terminal {} that this thread asked is gone; ask in a new thread.",
                            root.to_handle
                        ),
                        json!({}),
                    ));
                }
                root.to_handle.clone()
            }
            _ => self.resolve_inbox_recipient(payload)?,
        };
        let thread_id = thread_root.as_ref().map(|root| root.id.clone());
        let subject = optional_string(payload, "subject").unwrap_or_else(|| subject_from(&body));
        let expires_in_seconds = match payload.get("expiresInMs") {
            None | Some(Value::Null) => None,
            Some(value) => Some(
                value
                    .as_u64()
                    .filter(|ms| *ms <= INBOX_MAX_EXPIRY_SECONDS as u64 * 1000)
                    .map(|ms| ms.div_ceil(1000) as i64)
                    .ok_or_else(|| {
                        HostError::conflict(
                            "inbox_invalid_expiry",
                            "expiresInMs must be a whole number of milliseconds up to 7 days.",
                            json!({}),
                        )
                    })?,
            ),
        };
        let workspace_id = self
            .sessions
            .get(&recipient)
            .map(|session| session.workspace_id.clone());
        let workspace_name = match workspace_id.as_deref() {
            Some(id) => self
                .runtime_store
                .find_workspace(id)
                .await
                .ok()
                .flatten()
                .map(|workspace| workspace.name),
            None => None,
        };
        let external_meta = json!({
            "version": 1,
            "origin": self.inbox_origin(client_id),
            "target": {
                "agent": self.agent_presence.get(&recipient).map(|entry| entry.agent_type.clone()),
                "tabTitle": self.inbox_tab_title(&recipient).await,
                "workspaceName": workspace_name,
            },
        });
        let message = self
            .runtime_store
            .insert_inbox_question(NewInboxQuestion {
                inbox,
                recipient: recipient.clone(),
                subject,
                body,
                priority: match payload.get("priority") {
                    None => alera_core::runtime::OrchestrationMessagePriority::High,
                    Some(_) => parse_priority(payload)?,
                },
                thread_id,
                workspace_id,
                payload: optional_string(payload, "payload"),
                expires_in_seconds,
                external_meta,
            })
            .await
            .map_err(inbox_error)?;
        self.deliver_pending_messages_if_idle(&recipient).await;
        // Wakes a coordinator parked on `check --wait`.
        self.notify_message_arrived(&recipient, OrchestrationMessageType::DecisionGate)
            .await;
        Ok(json!({
            "questionId": message.id,
            "threadId": message.thread_id.clone().unwrap_or_else(|| message.id.clone()),
            "message": message,
            "recipient": self.inbox_recipient(&recipient),
            "revision": self.inbox_revision().await?,
        }))
    }
}

fn subject_from(body: &str) -> String {
    let line = body
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("Question");
    let mut subject = String::new();
    for character in line.chars().take(SUBJECT_FROM_BODY_CHARS) {
        if subject.len() + character.len_utf8() > SUBJECT_FROM_BODY_MAX_BYTES {
            break;
        }
        subject.push(character);
    }
    if subject.len() < line.len() {
        subject.push_str("...");
    }
    subject
}
