//! One async actor per chat. It owns the provider adapter, the header the
//! store last committed plus the one being built, and the pending item
//! changes. Commands and provider events are selected in one loop; provider
//! I/O never runs on the host actor.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use alera_core::runtime::{AgentChatCommitOutcome, AgentChatReceipt, RuntimeStore};
use alera_provider_protocol::{
    ProviderCapabilities, ProviderError, ProviderEvent, ProviderSession, ProviderSkill, RequestId,
};
use serde_json::Value;
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;
use tokio::time::Instant;

use super::commands::ChatEnvelope;
use super::events::{ChatEventSink, ChatRuntimeEvent};
use super::header::{header_delta, Header};
use super::provider_factory::{BoxedProvider, ProviderFactory, ProviderLaunchHook};
use super::session_pending::PendingItems;
use super::tab_directory::TabDirectory;
use super::wire::ChatItem;
use super::{ChatActivity, InstanceDirectory};

#[cfg(test)]
#[path = "startup_cancellation_tests.rs"]
mod startup_cancellation_tests;

/// Streamed text waits at most this long before it is committed.
pub(crate) const DEFAULT_FLUSH_DELAY: Duration = Duration::from_millis(75);
/// Streamed text above this size is committed without waiting.
pub(crate) const FLUSH_TEXT_BYTES: usize = 8 * 1024;
pub(super) const STARTUP_TIMEOUT: Duration = Duration::from_secs(90);
pub(super) const CLOSE_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone)]
pub(crate) struct SessionDeps {
    pub store: RuntimeStore,
    pub factory: Arc<dyn ProviderFactory>,
    pub hooks: Arc<std::sync::RwLock<Vec<Arc<dyn ProviderLaunchHook>>>>,
    pub sink: Arc<dyn ChatEventSink>,
    pub tabs: Arc<dyn TabDirectory>,
    pub activity: Arc<ChatActivity>,
    pub instances: Arc<InstanceDirectory>,
    pub flush_delay: Duration,
}

pub(super) type StartupResult = Result<(BoxedProvider, ProviderSession), String>;

/// A turn accepted while the provider is still starting.
pub(super) struct DeferredTurn {
    pub input: alera_provider_protocol::TurnInput,
}

/// A request the provider is waiting on, with its native id.
#[derive(Clone)]
pub(super) struct OpenRequest {
    pub request_id: String,
    pub native: RequestId,
}

pub(crate) struct ChatSession {
    pub(super) deps: SessionDeps,
    pub(super) generation: i64,
    pub(super) native_thread: Option<String>,
    pub(super) native_fork: Option<super::session_native_fork::NativeForkPlan>,
    pub(super) fork_source_turn_id: Option<String>,
    pub(super) startup_forking: bool,
    pub(super) native_operation: Option<alera_core::runtime::AgentChatNativeOperation>,
    /// What the store holds at `committed.cursor`.
    pub(super) committed: Header,
    /// What the next commit writes.
    pub(super) header: Header,
    pub(super) pending: PendingItems,
    pub(super) receipt: Option<AgentChatReceipt>,
    /// Client message ids, recorded after the commit that holds the message.
    pub(super) message_receipts: Vec<AgentChatReceipt>,
    pub(super) has_items: bool,
    pub(super) provider: Option<BoxedProvider>,
    pub(super) live_caps: Option<ProviderCapabilities>,
    /// The skills the live provider last reported (`session.skills.updated`).
    /// Kept out of the header: lists can be large and clients fetch them
    /// through `agentChat.skills` only when the composer asks.
    pub(super) provider_skills: Option<Vec<ProviderSkill>>,
    /// Native ids of this provider process are mapped under kinds suffixed
    /// with it, because JSON-RPC and local ids restart with every process.
    pub(super) process_epoch: String,
    /// Polled for events only while armed; an adapter with nothing to report
    /// answers `None`, and is re-armed by the next send, answer or interrupt.
    pub(super) events_armed: bool,
    pub(super) startup: Option<oneshot::Receiver<StartupResult>>,
    /// The task owns hook preparation and the provider while it starts. It is
    /// cancelled and joined before launch credentials are revoked, so a late
    /// startup cannot mint a new credential or adopt a provider after stop.
    pub(super) startup_task: Option<JoinHandle<()>>,
    pub(super) startup_resume: bool,
    pub(super) deferred_turn: Option<DeferredTurn>,
    /// The next user turn carries the transcript of earlier sessions.
    pub(super) handoff_pending: bool,
    /// Where the pending handoff's context came from, kept after a failed
    /// handoff so the retry names the original source, not the failed turn.
    pub(super) handoff_from: Option<Value>,
    pub(super) provider_turn_id: Option<String>,
    pub(super) native_ids: HashMap<(String, String), String>,
    pub(super) open_requests: Vec<OpenRequest>,
    /// Native background work the agent resumes from (`task.*.awaited`, or
    /// a background command it said it waits on), by task id. It keeps the
    /// chat working after the turn that started it ends; other background
    /// work does not.
    pub(super) awaited_tasks: HashMap<String, super::session_background_work::AwaitedTask>,
    pub(super) items: HashMap<String, ChatItem>,
    /// List and tab notices, sent after the commit they describe.
    pub(super) notices: Vec<ChatRuntimeEvent>,
    pub(super) busy_flag: bool,
    pub(super) live_flag: bool,
    pub(super) closed: bool,
}

enum Next {
    Command(Option<Box<ChatEnvelope>>),
    Started(Result<StartupResult, oneshot::error::RecvError>),
    Event(Box<Result<Option<ProviderEvent>, ProviderError>>),
    Flush,
}

impl ChatSession {
    pub(super) async fn load(chat_id: &str, deps: SessionDeps) -> Result<Self, String> {
        let record = deps
            .store
            .agent_chat(chat_id)
            .await
            .map_err(|error| error.to_string())?
            .ok_or_else(|| format!("Unknown chat {chat_id}"))?;
        let page_items: Vec<ChatItem> = record
            .snapshot
            .get("items")
            .cloned()
            .and_then(|items| serde_json::from_value(items).ok())
            .unwrap_or_default();
        let stored_header = Header::from_snapshot(record.snapshot.clone())?;
        let mut header = stored_header.clone();
        if header.title_source == "legacy" {
            let default_title = deps
                .instances
                .find(&header.provider_instance_id)
                .and_then(|instance| instance.label)
                .or_else(|| {
                    super::provider_traits::provider_traits(&header.provider)
                        .map(|traits| traits.label.into())
                });
            header.title_source = if default_title.as_deref() == Some(&header.title) {
                "default"
            } else {
                "user"
            }
            .into();
        }
        header.cursor = record.cursor;
        header.tab_id = record.tab_id.clone();
        header.archived = header.archived || record.archived;
        if header.session.cwd.is_none() {
            if let Some(workspace) = deps
                .tabs
                .workspace(&record.workspace_id)
                .await
                .map_err(|error| error.to_string())?
            {
                header.session.cwd = Some(workspace.path.to_string_lossy().into_owned());
            }
        }
        if header.lineage.is_none() {
            header.lineage = super::header::lineage_from_metadata(record.metadata.as_ref());
        }
        let items = page_items
            .iter()
            .filter(|item| item.status == "inProgress" || item.streaming)
            .map(|item| (item.item_id.clone(), item.clone()))
            .collect();
        let mut committed = stored_header;
        committed.cursor = record.cursor;
        committed.tab_id = record.tab_id.clone();
        committed.archived = committed.archived || record.archived;
        let mut session = Self {
            deps,
            generation: record.generation,
            native_thread: record.native_thread_id,
            native_fork: record
                .metadata
                .as_ref()
                .and_then(|metadata| metadata.get("nativeFork"))
                .and_then(|fork| serde_json::from_value(fork.clone()).ok()),
            fork_source_turn_id: record
                .metadata
                .as_ref()
                .and_then(|metadata| metadata.get("forkedFromTurnId"))
                .and_then(Value::as_str)
                .map(str::to_string),
            startup_forking: false,
            native_operation: None,
            committed,
            header,
            pending: PendingItems::default(),
            receipt: None,
            message_receipts: Vec::new(),
            has_items: !page_items.is_empty(),
            provider: None,
            live_caps: None,
            provider_skills: None,
            process_epoch: super::ids::process_epoch(),
            events_armed: false,
            startup: None,
            startup_task: None,
            startup_resume: false,
            deferred_turn: None,
            handoff_pending: false,
            handoff_from: None,
            provider_turn_id: None,
            native_ids: HashMap::new(),
            open_requests: Vec::new(),
            awaited_tasks: HashMap::new(),
            items,
            notices: Vec::new(),
            busy_flag: false,
            live_flag: false,
            closed: false,
        };
        session.load_native_history_recovery().await?;
        Ok(session)
    }

    pub(super) async fn run(mut self, mut rx: mpsc::Receiver<ChatEnvelope>) {
        loop {
            self.sync_activity();
            if self.closed {
                break;
            }
            let poll_events = self.events_armed && self.provider.is_some();
            let has_startup = self.startup.is_some();
            let deadline = self.pending.deadline;
            let next = {
                let provider = self.provider.as_mut();
                let startup = self.startup.as_mut();
                tokio::select! {
                    biased;
                    envelope = rx.recv() => Next::Command(envelope.map(Box::new)),
                    result = async { startup.expect("startup is pending").await }, if has_startup => {
                        Next::Started(result)
                    }
                    event = async { provider.expect("provider is running").next_event().await }, if poll_events => {
                        Next::Event(Box::new(event))
                    }
                    _ = tokio::time::sleep_until(deadline.unwrap_or_else(Instant::now)), if deadline.is_some() => {
                        Next::Flush
                    }
                }
            };
            match next {
                Next::Command(None) => {
                    self.shutdown().await;
                    break;
                }
                Next::Command(Some(envelope)) => self.handle_envelope(*envelope).await,
                Next::Started(result) => {
                    self.startup = None;
                    self.join_startup_task().await;
                    let result =
                        result.unwrap_or_else(|_| Err("provider startup was dropped".into()));
                    self.finish_startup(result).await;
                }
                Next::Event(event) => match *event {
                    Ok(Some(event)) => self.apply_provider_event(event).await,
                    Ok(None) => self.provider_went_quiet().await,
                    Err(error) => self.provider_failed(error.to_string()).await,
                },
                Next::Flush => {
                    let _ = self.flush().await;
                }
            }
        }
        self.live_flag_set(false);
        self.busy_flag_set(false);
    }

    pub(super) fn is_busy(&self) -> bool {
        self.native_operation
            .as_ref()
            .is_some_and(super::session_native_history_recovery::native_operation_freezes)
            || self.header.session.active_turn_id.is_some()
            || !self.header.pending_requests.is_empty()
            || !self.header.queue.is_empty()
            || self.startup.is_some()
            || self.deferred_turn.is_some()
    }

    pub(super) fn never_sent(&self) -> bool {
        !self.has_items
            && self.header.turns.is_empty()
            && self.native_thread.is_none()
            && self.header.queue.is_empty()
            && self.deferred_turn.is_none()
            && self.startup.is_none()
            && self.header.session.active_turn_id.is_none()
            && self.header.pending_requests.is_empty()
    }

    fn sync_activity(&mut self) {
        let busy = !self.closed && self.is_busy();
        let live = !self.closed && (self.provider.is_some() || self.startup.is_some());
        self.busy_flag_set(busy);
        self.live_flag_set(live);
    }

    fn busy_flag_set(&mut self, busy: bool) {
        if busy != self.busy_flag {
            self.busy_flag = busy;
            self.deps.activity.adjust_busy(busy);
            self.deps.sink.activity_changed();
        }
    }

    fn live_flag_set(&mut self, live: bool) {
        if live != self.live_flag {
            self.live_flag = live;
            self.deps.activity.adjust_live(live);
            self.deps.sink.activity_changed();
        }
    }

    pub(super) fn refresh_capabilities(&mut self) {
        self.header.session.capabilities = super::provider_traits::capabilities_json(
            &self.header.provider,
            self.live_caps.as_ref(),
        );
        self.header.session.capabilities["rollback"] = Value::Bool(false);
        self.header.session.capabilities["transcriptFork"] = Value::Bool(true);
        self.header.session.capabilities["transcriptRewind"] = Value::Bool(true);
        self.header.session.capabilities["approvalHistory"] = Value::Bool(true);
        self.header.session.capabilities["turnDiff"] = Value::Bool(true);
        let native = self
            .provider
            .as_ref()
            .map(|provider| provider.native_history_capabilities())
            .unwrap_or_default();
        self.header.session.capabilities["nativeHistory"] = serde_json::json!({
            "forkAtTurn":native.fork_at_turn,"forkAtMessage":false,
            "rollbackRemoveTurns":false,"rollbackBeforeTurn":native.rollback_before_turn,
            "rewindFiles":native.rewind_files,
            "fileCheckpointing":native.file_checkpointing || self.header.provider == "claudeAgent",
        });
        self.header.session.capabilities["rollback"] = Value::Bool(native.rollback_before_turn);
        if let Some(provider) = self.provider.as_ref() {
            self.header.session.capabilities["reasoningEffort"] =
                super::wire::json(&provider.reasoning_effort_capabilities());
        }
    }

    /// Commits everything pending as one cursor step and broadcasts it.
    pub(super) async fn flush(&mut self) -> Result<(), String> {
        self.refresh_capabilities();
        let header_changed = !header_delta(&self.committed, &self.header).is_empty();
        if self.pending.is_empty() && self.receipt.is_none() && !header_changed {
            self.pending.deadline = None;
            self.emit_notices().await;
            return Ok(());
        }
        let mut next = self.header.clone();
        next.cursor = self.committed.cursor + 1;
        if next.provider_instance_id != self.committed.provider_instance_id
            || next.provider != self.committed.provider
        {
            if self.generation <= self.committed.session.generation {
                self.generation = self.committed.session.generation + 1;
            }
            next.session.generation = self.generation;
        }
        let mut delta = header_delta(&self.committed, &next);
        self.pending.write_into(&self.items, &mut delta);
        let outcome = self
            .deps
            .store
            .commit_agent_chat(
                &next.chat_id,
                self.committed.cursor,
                &next.to_snapshot(),
                &Value::Object(delta),
                self.receipt.as_ref(),
            )
            .await;
        match outcome {
            Ok(AgentChatCommitOutcome::Committed(event)) => {
                if next.provider_instance_id != self.committed.provider_instance_id
                    || next.provider != self.committed.provider
                {
                    self.native_thread = None;
                }
                self.header = next.clone();
                self.committed = next;
                self.pending = PendingItems::default();
                self.receipt = None;
                for receipt in std::mem::take(&mut self.message_receipts) {
                    let _ = self
                        .deps
                        .store
                        .record_agent_chat_receipt(Some(&self.header.chat_id), &receipt)
                        .await;
                }
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::Changed {
                        chat_id: self.header.chat_id.clone(),
                        workspace_id: self.header.workspace_id.clone(),
                        cursor: event.cursor,
                        delta: event.delta,
                    })
                    .await;
                self.emit_notices().await;
                Ok(())
            }
            Ok(AgentChatCommitOutcome::CursorConflict { current }) => {
                tracing::error!(chat_id = %next.chat_id, current, "agent chat cursor moved under its session");
                self.pending.deadline = Some(Instant::now() + Duration::from_millis(500));
                Err("The chat changed outside its session.".into())
            }
            Ok(_) => {
                // The receipt was recorded by an earlier attempt; the change
                // itself still has to land.
                self.receipt = None;
                Box::pin(self.flush()).await
            }
            Err(error) => {
                let message = format!("{error:#}");
                tracing::error!(chat_id = %next.chat_id, error = %message, "agent chat commit failed");
                self.pending.deadline = Some(Instant::now() + Duration::from_millis(500));
                Err(message)
            }
        }
    }

    /// Schedules a coalesced flush, or flushes now once enough text waits.
    pub(super) async fn schedule_flush(&mut self) {
        if self.pending.text_bytes() >= FLUSH_TEXT_BYTES {
            let _ = self.flush().await;
        } else if self.pending.deadline.is_none() {
            self.pending.deadline = Some(Instant::now() + self.deps.flush_delay);
        }
    }

    async fn emit_notices(&mut self) {
        for notice in std::mem::take(&mut self.notices) {
            self.deps.sink.emit(notice).await;
        }
    }
}
