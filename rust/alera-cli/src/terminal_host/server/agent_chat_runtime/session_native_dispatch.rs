//! Receipt-aware native commands and the freeze on unresolved effects.

use serde_json::Value;

use crate::terminal_host::host_error::HostResult;

use super::commands::{CallerCtx, ChatOp, ReceiptKey};
use super::session::ChatSession;
use super::session_native_history::native_pending_error;
use super::session_native_history_recovery::native_operation_freezes;
use super::session_ops::receipt_conflict;

impl ChatSession {
    pub(super) fn guard_native_operation(
        &self,
        op: &ChatOp,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> HostResult<()> {
        let Some(pending) = self
            .native_operation
            .as_ref()
            .filter(|op| native_operation_freezes(op))
        else {
            return Ok(());
        };
        if let Some(key) = key {
            if pending.caller_scope == ctx.scope
                && pending.verb == key.verb
                && pending.request_id == key.request_id
                && pending.digest != key.digest
            {
                return Err(receipt_conflict());
            }
        }
        if matches!(
            op,
            ChatOp::Snapshot
                | ChatOp::History { .. }
                | ChatOp::ApprovalHistory { .. }
                | ChatOp::TurnDiff { .. }
                | ChatOp::NativeHistoryOperation { .. }
                | ChatOp::NativeHistoryReconcile { .. }
                | ChatOp::Stop
                | ChatOp::Shutdown
        ) {
            return Ok(());
        }
        Err(native_pending_error(pending, pending.state == "uncertain"))
    }

    pub(super) async fn dispatch_native_history(
        &mut self,
        op: &ChatOp,
        ctx: &CallerCtx,
        key: Option<&ReceiptKey>,
    ) -> Option<HostResult<Value>> {
        match op {
            ChatOp::NativeRewind { turn_id } => {
                Some(self.native_rewind(turn_id, false, ctx, key).await)
            }
            ChatOp::NativeRewindFiles { turn_id } => {
                Some(self.native_rewind(turn_id, true, ctx, key).await)
            }
            ChatOp::NativeHistoryReconcile {
                operation_id,
                expected_revision,
                action,
            } => Some(
                self.reconcile_native_history(operation_id, *expected_revision, action, ctx, key)
                    .await,
            ),
            _ => None,
        }
    }
}
