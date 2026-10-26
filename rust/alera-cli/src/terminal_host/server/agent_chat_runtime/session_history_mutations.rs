//! Actor-serialized transcript mutations. Workspace files are never reverted.

use alera_core::runtime::{
    AgentChatArchivedDeleteOutcome, AgentChatCreateOutcome, AgentChatReceipt, AgentChatRecord,
    AgentChatRewindOutcome,
};
use alera_provider_protocol::NativeForkBoundary;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, CallerCtx, ReceiptKey};
use super::events::ChatRuntimeEvent;
use super::header::Header;
use super::ids::{process_epoch, receipt_scope};
use super::session::{ChatSession, CLOSE_TIMEOUT};
use super::session_ops::receipt_conflict;
use super::tab_directory::{chat_tab_payload, chat_tab_record};

fn fork_record(
    source: &Header,
    turn_id: &str,
    chat_id: &str,
    tab_id: &str,
    title: Option<&str>,
) -> HostResult<AgentChatRecord> {
    let title = title
        .map(str::trim)
        .filter(|title| !title.is_empty())
        .map(|title| title.chars().take(200).collect::<String>())
        .unwrap_or_else(|| {
            let original = source.title.trim().chars().take(190).collect::<String>();
            if original.is_empty() {
                "Agent Chat Fork".into()
            } else {
                format!("{original} Fork")
            }
        });
    let header = Header::from_snapshot(json!({
        "chatId": chat_id, "workspaceId": source.workspace_id, "tabId": tab_id,
        "providerInstanceId": source.provider_instance_id, "provider": source.provider,
        "title": title, "titleSource": "user", "cursor": 0,
        "session": {
            "status": "stopped", "model": source.session.model,
            "reasoningEffort": source.session.reasoning_effort,
            "runtimeMode": source.session.runtime_mode,
            "interactionMode": source.session.interaction_mode, "cwd": source.session.cwd,
            "generation": 1,
            "capabilities": super::provider_traits::capabilities_json(&source.provider, None),
        },
        "turns": [], "items": [], "pendingRequests": [], "queue": [],
    }))
    .map_err(HostError::state)?;
    let stamp = chrono::Utc::now();
    Ok(AgentChatRecord {
        chat_id: chat_id.into(),
        tab_id: tab_id.into(),
        workspace_id: source.workspace_id.clone(),
        provider_instance_id: source.provider_instance_id.clone(),
        provider: source.provider.clone(),
        native_thread_id: None,
        generation: 1,
        archived: false,
        archived_at: None,
        cursor: 0,
        created_at: stamp,
        updated_at: stamp,
        metadata: Some(json!({
            "originKind": "transcriptFork", "forkedFromChatId": source.chat_id,
            "forkedFromTurnId": turn_id,
        })),
        snapshot: header.to_snapshot(),
    })
}

fn history_receipt(ctx: &CallerCtx, key: Option<&ReceiptKey>) -> Option<AgentChatReceipt> {
    key.map(|key| AgentChatReceipt {
        caller_scope: receipt_scope(&ctx.scope, &key.verb),
        request_id: key.request_id.clone(),
        digest: key.digest.clone(),
        receipt: Value::Null,
    })
}

impl ChatSession {
    async fn native_fork_metadata(&mut self, turn_id: &str) -> HostResult<Option<Value>> {
        if !self
            .provider
            .as_ref()
            .is_some_and(|provider| provider.native_history_capabilities().fork_at_turn)
        {
            return Ok(None);
        }
        let Some(source_thread) = self.native_thread.clone() else {
            return Ok(None);
        };
        let turn = self
            .deps
            .store
            .agent_chat_turn(&self.header.chat_id, turn_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if turn
            .as_ref()
            .and_then(|turn| turn.get("generation"))
            .and_then(Value::as_i64)
            != Some(self.generation)
        {
            return Ok(None);
        }
        let mapping = self
            .deps
            .store
            .agent_chat_native_id_for_app(&self.header.chat_id, self.generation, "turn", turn_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let Some(mapping) = mapping.filter(|mapping| mapping.generation == self.generation) else {
            return Ok(None);
        };
        let Some(native_turn) = mapping.native_id.as_str() else {
            return Ok(None);
        };
        Ok(Some(json!({
            "sourceNativeThreadId": source_thread,
            "boundary": NativeForkBoundary::Turn(native_turn.into()),
            "provider": self.header.provider,
            "providerInstanceId": self.header.provider_instance_id,
        })))
    }

    pub(super) async fn fork_history(
        &mut self,
        turn_id: &str,
        new_chat_id: &str,
        new_tab_id: &str,
        title: Option<&str>,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> HostResult<Value> {
        self.require_idle("forking this chat")?;
        self.flush().await.map_err(HostError::state)?;
        let workspace = self
            .deps
            .tabs
            .workspace(&self.header.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| conflict("workspaceNotFound", "The workspace no longer exists."))?;
        if workspace.archived || workspace.host_id != "local" {
            return Err(conflict(
                "workspaceUnavailable",
                "Open the local workspace before forking this chat.",
            ));
        }
        let mut record = fork_record(&self.header, turn_id, new_chat_id, new_tab_id, title)?;
        let native = self.native_fork_metadata(turn_id).await?;
        let operation_kind = if native.is_some() {
            "nativeForkDeferred"
        } else {
            "transcriptFork"
        };
        if let Some(native) = native {
            record.metadata.as_mut().expect("fork metadata exists")["nativeFork"] = native;
        }
        record.snapshot["session"]["historyOperation"] = json!({"kind": operation_kind});
        record.snapshot[super::session_transfers::TRANSFERS_KEY] =
            super::session_transfers::fork_transfer(&self.header, turn_id, new_chat_id);
        let tab = chat_tab_record(
            new_tab_id,
            &record.workspace_id,
            record.snapshot["title"]
                .as_str()
                .unwrap_or("Agent Chat Fork"),
            chat_tab_payload(
                new_chat_id,
                &record.provider,
                &record.provider_instance_id,
                self.header.session.model.as_deref(),
            ),
        );
        let receipt = history_receipt(ctx, key);
        match self
            .deps
            .store
            .fork_agent_chat_through_turn(
                &self.header.chat_id,
                self.committed.cursor,
                turn_id,
                &record,
                &tab,
                receipt.as_ref(),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            AgentChatCreateOutcome::Created(record) => {
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::ChatsChanged {
                        workspace_id: Some(record.workspace_id.clone()),
                    })
                    .await;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::TabsChanged {
                        workspace_id: record.workspace_id.clone(),
                    })
                    .await;
                Ok(json!({
                    "chatId": record.chat_id, "tabId": record.tab_id, "snapshot": record.snapshot,
                    "operationKind": operation_kind, "filesystemChangesReverted": false,
                }))
            }
            AgentChatCreateOutcome::Replay(response) => Ok(response),
            AgentChatCreateOutcome::ReceiptConflict => Err(receipt_conflict()),
        }
    }

    pub(super) async fn rewind_history(
        &mut self,
        turn_id: &str,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> HostResult<Value> {
        self.require_idle("rewinding this chat")?;
        if self.header.archived {
            return Err(conflict(
                "chatArchived",
                "Reopen this chat before rewinding it.",
            ));
        }
        self.flush().await.map_err(HostError::state)?;
        let mut next = self.header.clone();
        next.cursor = self
            .committed
            .cursor
            .checked_add(1)
            .ok_or_else(|| HostError::state("The chat cursor is exhausted."))?;
        next.session.generation = self
            .generation
            .checked_add(1)
            .ok_or_else(|| HostError::state("The chat generation is exhausted."))?;
        next.session.status = "stopped".into();
        next.session.active_turn_id = None;
        next.session.error_message = None;
        next.session.extra.remove("historyOperation");
        next.turns.clear();
        next.pending_requests.clear();
        next.queue.clear();
        next.usage = None;
        next.recovery = None;
        self.revoke_launch_credentials("historyRewind").await;
        if let Some(mut provider) = self.provider.take() {
            let _ = tokio::time::timeout(CLOSE_TIMEOUT, provider.close()).await;
        }
        self.live_caps = None;
        self.events_armed = false;
        let receipt = history_receipt(ctx, key);
        let outcome = self
            .deps
            .store
            .rewind_agent_chat_before_turn(
                &self.header.chat_id,
                self.committed.cursor,
                turn_id,
                &next.to_snapshot(),
                receipt.as_ref(),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        match outcome {
            AgentChatRewindOutcome::Rewound {
                record,
                event,
                prompt,
            } => {
                self.header =
                    Header::from_snapshot(record.snapshot.clone()).map_err(HostError::state)?;
                self.committed = self.header.clone();
                self.generation = record.generation;
                self.native_thread = None;
                self.process_epoch = process_epoch();
                self.native_ids.clear();
                self.open_requests.clear();
                self.items.clear();
                self.pending = Default::default();
                self.receipt = None;
                self.message_receipts.clear();
                self.provider_turn_id = None;
                self.deferred_turn = None;
                self.native_fork = None;
                self.fork_source_turn_id = None;
                self.startup_forking = false;
                self.has_items = record.snapshot["items"]
                    .as_array()
                    .is_some_and(|items| !items.is_empty());
                self.handoff_pending = self.has_items;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::Changed {
                        chat_id: record.chat_id.clone(),
                        workspace_id: record.workspace_id.clone(),
                        cursor: event.cursor,
                        delta: event.delta.clone(),
                    })
                    .await;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::ChatsChanged {
                        workspace_id: Some(record.workspace_id.clone()),
                    })
                    .await;
                Ok(json!({
                    "chatId": record.chat_id, "snapshot": record.snapshot, "event": event,
                    "prompt": prompt.get("text").and_then(Value::as_str).unwrap_or(""),
                    "attachments": prompt.get("attachments").cloned().unwrap_or_else(|| json!([])),
                    "promptItem": prompt,
                    "operationKind": "transcriptRewind", "filesystemChangesReverted": false,
                    "nativeRollback": false,
                    "nativeRollbackUnavailableReason": "Use native mode to request a verified native conversation rewind.",
                }))
            }
            AgentChatRewindOutcome::Replay(response) => Ok(response),
            AgentChatRewindOutcome::ReceiptConflict => Err(receipt_conflict()),
            AgentChatRewindOutcome::CursorConflict { current } => Err(HostError::conflict(
                "cursorConflict",
                "The chat changed before it could be rewound.",
                json!({"cursor": current}),
            )),
        }
    }

    pub(super) async fn delete_history(
        &mut self,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> HostResult<Value> {
        self.require_idle("deleting this chat")?;
        self.flush().await.map_err(HostError::state)?;
        let receipt = history_receipt(ctx, key);
        match self
            .deps
            .store
            .delete_archived_agent_chat(
                &self.header.chat_id,
                self.committed.cursor,
                receipt.as_ref(),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            AgentChatArchivedDeleteOutcome::Deleted => {
                self.closed = true;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::Deleted {
                        chat_id: self.header.chat_id.clone(),
                        workspace_id: self.header.workspace_id.clone(),
                        discarded: false,
                    })
                    .await;
                self.deps
                    .sink
                    .emit(ChatRuntimeEvent::ChatsChanged {
                        workspace_id: Some(self.header.workspace_id.clone()),
                    })
                    .await;
                Ok(json!({"chatId": self.header.chat_id, "deleted": true}))
            }
            AgentChatArchivedDeleteOutcome::NotArchived => Err(conflict(
                "chatNotArchived",
                "Close this chat before deleting it.",
            )),
            AgentChatArchivedDeleteOutcome::ReferencedByTasks => Err(conflict(
                "chatHasActiveTasks",
                "Wait for this chat's active tasks before deleting it.",
            )),
            AgentChatArchivedDeleteOutcome::CursorConflict { current } => Err(HostError::conflict(
                "cursorConflict",
                "The chat changed before it could be deleted.",
                json!({"cursor": current}),
            )),
            AgentChatArchivedDeleteOutcome::Replay(response) => Ok(response),
            AgentChatArchivedDeleteOutcome::ReceiptConflict => Err(receipt_conflict()),
        }
    }
}

#[cfg(test)]
#[path = "session_history_mutation_tests.rs"]
mod tests;
