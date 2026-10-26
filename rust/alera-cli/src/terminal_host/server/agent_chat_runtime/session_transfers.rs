//! Context transfers (`agentChatTransfersV1`): durable records of context
//! moved into a chat, T3 Code's `contextTransfers`. A fork's copied history,
//! a merge-back, a provider handoff, a delegated brief and a delegated
//! result each leave one record in the chat that received the context, so
//! the timeline and the lineage control can show where it came from. The
//! records live in the chat header (`contextTransfers`), so a restart keeps
//! them with the rest of the snapshot.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::conflict;
use super::header::Header;
use super::ids::{new_id, now};
use super::session::ChatSession;

/// The header key holding the chat's transfer records, oldest first.
pub(crate) const TRANSFERS_KEY: &str = "contextTransfers";
/// Records kept per chat; the oldest settled ones go first.
const MAX_TRANSFERS: usize = 200;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum TransferKind {
    /// History copied into a fork up to `sourceTurnId`.
    Fork,
    /// The transcript carried into a fresh provider session of the same chat.
    ProviderHandoff,
    /// A fork's work handed back to the chat it was forked from.
    MergeBack,
    /// A delegated brief sent to a child chat.
    SubagentSpawn,
    /// A delegated chat's result delivered to its parent.
    SubagentResult,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum TransferStatus {
    /// Recorded; the context has not reached a turn yet.
    Pending,
    /// The context reached the receiving chat's agent.
    Consumed,
    /// The turn that carried it failed.
    Failed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ContextTransfer {
    pub transfer_id: String,
    pub kind: TransferKind,
    pub source_chat_id: String,
    pub target_chat_id: String,
    /// The source chat's title when the transfer was made, for a source that
    /// is gone or on another host.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_title: Option<String>,
    /// The source chat's turn the context was taken through.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_turn_id: Option<String>,
    /// The receiving chat's turn that carried the context.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_turn_id: Option<String>,
    /// The receiving chat's timeline item showing the transfer, when it has
    /// one (a merge-back notice, a handoff marker).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub item_id: Option<String>,
    /// The chat orchestration task of a delegated brief or result.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
    /// `{provider, providerInstanceId, model}` of the agent the context left.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from: Option<Value>,
    /// `{provider, providerInstanceId, model}` of the agent it reached.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub to: Option<Value>,
    pub status: TransferStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub consumed_at: Option<String>,
}

impl ContextTransfer {
    pub(crate) fn new(
        kind: TransferKind,
        source_chat_id: &str,
        target_chat_id: &str,
        status: TransferStatus,
    ) -> Self {
        let stamp = now();
        Self {
            transfer_id: new_id("transfer"),
            kind,
            source_chat_id: source_chat_id.into(),
            target_chat_id: target_chat_id.into(),
            source_title: None,
            source_turn_id: None,
            target_turn_id: None,
            item_id: None,
            task_id: None,
            from: None,
            to: None,
            consumed_at: (status == TransferStatus::Consumed).then(|| stamp.clone()),
            status,
            error: None,
            created_at: stamp.clone(),
            updated_at: stamp,
        }
    }

    fn settle(&mut self, status: TransferStatus, turn_id: Option<&str>) {
        let stamp = now();
        self.status = status;
        if let Some(turn_id) = turn_id {
            self.target_turn_id = Some(turn_id.into());
        }
        if status == TransferStatus::Consumed {
            self.consumed_at = Some(stamp.clone());
        }
        self.updated_at = stamp;
    }
}

/// `{provider, providerInstanceId, model}` of a chat's current agent.
pub(crate) fn agent_endpoint(header: &Header) -> Value {
    json!({
        "provider": header.provider,
        "providerInstanceId": header.provider_instance_id,
        "model": header.session.model,
    })
}

/// The record a new fork starts with: the source's history through
/// `turn_id` is already in it.
pub(crate) fn fork_transfer(source: &Header, turn_id: &str, fork_chat_id: &str) -> Value {
    let mut transfer = ContextTransfer::new(
        TransferKind::Fork,
        &source.chat_id,
        fork_chat_id,
        TransferStatus::Consumed,
    );
    transfer.source_title = Some(source.title.clone()).filter(|title| !title.is_empty());
    transfer.source_turn_id = Some(turn_id.into());
    transfer.from = Some(agent_endpoint(source));
    transfer.to = transfer.from.clone();
    json!([transfer])
}

/// The records stored in `header`, skipping any a newer host wrote in a
/// shape this one does not read.
pub(crate) fn header_transfers(header: &Header) -> Vec<ContextTransfer> {
    header
        .extra
        .get(TRANSFERS_KEY)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|value| serde_json::from_value(value.clone()).ok())
        .collect()
}

fn store_transfers(header: &mut Header, mut transfers: Vec<ContextTransfer>) {
    while transfers.len() > MAX_TRANSFERS {
        let index = transfers
            .iter()
            .position(|transfer| transfer.status != TransferStatus::Pending)
            .unwrap_or(0);
        transfers.remove(index);
    }
    header.extra.insert(TRANSFERS_KEY.into(), json!(transfers));
}

impl ChatSession {
    /// Adds `transfer`, or replaces the record with its id.
    pub(super) fn record_transfer(&mut self, transfer: ContextTransfer) {
        let mut transfers = header_transfers(&self.header);
        match transfers
            .iter_mut()
            .find(|existing| existing.transfer_id == transfer.transfer_id)
        {
            Some(existing) => *existing = transfer,
            None => transfers.push(transfer),
        }
        store_transfers(&mut self.header, transfers);
        self.pending.session();
    }

    /// Settles the records shown by the timeline item `item_id`.
    pub(super) fn settle_item_transfers(
        &mut self,
        item_id: &str,
        status: TransferStatus,
        turn_id: Option<&str>,
    ) {
        let mut transfers = header_transfers(&self.header);
        let mut changed = false;
        for transfer in transfers
            .iter_mut()
            .filter(|transfer| transfer.item_id.as_deref() == Some(item_id))
            .filter(|transfer| transfer.status != status)
        {
            transfer.settle(status, turn_id);
            changed = true;
        }
        if changed {
            store_transfers(&mut self.header, transfers);
            self.pending.session();
        }
    }

    /// `ChatOp::RecordTransfer`: a record another chat's work produced for
    /// this one (a delegated brief or result). A task's record is kept once
    /// per kind, so a replayed delivery does not add another.
    pub(super) async fn receive_transfer(
        &mut self,
        mut transfer: ContextTransfer,
    ) -> HostResult<Value> {
        if transfer.target_chat_id != self.header.chat_id {
            return Err(conflict(
                "transferTarget",
                "The transfer belongs to another chat.",
            ));
        }
        if let Some(existing) = header_transfers(&self.header).into_iter().find(|existing| {
            existing.kind == transfer.kind
                && transfer.task_id.is_some()
                && existing.task_id == transfer.task_id
        }) {
            transfer.transfer_id = existing.transfer_id;
            transfer.created_at = existing.created_at;
        }
        let transfer_id = transfer.transfer_id.clone();
        self.record_transfer(transfer);
        self.flush().await.map_err(|error| {
            HostError::state(format!("The transfer could not be saved: {error}"))
        })?;
        Ok(json!({"chatId": self.header.chat_id, "transferId": transfer_id}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn header() -> Header {
        Header::from_snapshot(json!({
            "chatId": "c", "workspaceId": "w", "tabId": "t", "title": "Source",
            "providerInstanceId": "codex", "provider": "codex", "cursor": 0,
            "session": {"status": "stopped", "runtimeMode": "approval-required", "interactionMode": "default", "model": "gpt"},
        }))
        .unwrap()
    }

    #[test]
    fn a_fork_record_names_its_source_turn_and_agent() {
        let value = fork_transfer(&header(), "turn-1", "fork");
        let record = &value[0];
        assert_eq!(record["kind"], "fork");
        assert_eq!(record["sourceChatId"], "c");
        assert_eq!(record["targetChatId"], "fork");
        assert_eq!(record["sourceTitle"], "Source");
        assert_eq!(record["sourceTurnId"], "turn-1");
        assert_eq!(record["status"], "consumed");
        assert_eq!(record["from"]["model"], "gpt");
        assert!(record["consumedAt"].is_string());
    }

    #[test]
    fn the_store_drops_settled_records_before_pending_ones() {
        let mut header = header();
        let mut transfers = Vec::new();
        let mut pending = ContextTransfer::new(
            TransferKind::MergeBack,
            "fork",
            "c",
            TransferStatus::Pending,
        );
        pending.transfer_id = "pending".into();
        transfers.push(pending);
        for _ in 0..MAX_TRANSFERS {
            transfers.push(ContextTransfer::new(
                TransferKind::ProviderHandoff,
                "c",
                "c",
                TransferStatus::Consumed,
            ));
        }
        store_transfers(&mut header, transfers);
        let kept = header_transfers(&header);
        assert_eq!(kept.len(), MAX_TRANSFERS);
        assert_eq!(kept[0].transfer_id, "pending");
    }

    #[test]
    fn unreadable_records_are_skipped() {
        let mut header = header();
        header.extra.insert(
            TRANSFERS_KEY.into(),
            json!([{"kind": "teleport"}, fork_transfer(&header, "t", "f")[0].clone()]),
        );
        assert_eq!(header_transfers(&header).len(), 1);
    }
}
