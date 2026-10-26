//! "Always allow this session" for Codex approvals.
//!
//! Codex's own `acceptForSession` only skips the exact command or patch it
//! answered, so every new command would ask again. After the user allows a
//! kind for the session, later approvals of that kind on the same native
//! thread are answered here. A connection holds one session, so a new
//! runtime mode means a new provider and the allowance ends with the old one.

use crate::provider::CodexProvider;
use crate::wire;
use alera_provider_protocol::ApprovalDecision;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) enum AllowanceKind {
    Command,
    FileChange,
}

/// What an approval request may add to the session allowance when answered.
#[derive(Clone, Debug)]
pub(crate) struct AllowanceGrant {
    pub native_thread_id: String,
    pub kind: AllowanceKind,
}

#[derive(Default)]
pub(crate) struct SessionApprovals {
    allowed: HashMap<String, HashSet<AllowanceKind>>,
}

impl SessionApprovals {
    pub(crate) fn allows(&self, native_thread_id: &str, kind: AllowanceKind) -> bool {
        self.allowed
            .get(native_thread_id)
            .is_some_and(|kinds| kinds.contains(&kind))
    }

    pub(crate) fn record(&mut self, grant: &AllowanceGrant, decision: ApprovalDecision) {
        if !matches!(
            decision,
            ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways
        ) {
            return;
        }
        self.allowed
            .entry(grant.native_thread_id.clone())
            .or_default()
            .insert(grant.kind);
    }

    pub(crate) fn clear(&mut self) {
        self.allowed.clear();
    }
}

pub(crate) fn allowance_kind(method: &str) -> Option<AllowanceKind> {
    match method {
        "item/commandExecution/requestApproval" | "execCommandApproval" => {
            Some(AllowanceKind::Command)
        }
        "item/fileChange/requestApproval" | "applyPatchApproval" => Some(AllowanceKind::FileChange),
        _ => None,
    }
}

/// The legacy v1 approvals name their thread `conversationId`.
pub(crate) fn request_native_thread_id(params: &Value) -> Option<String> {
    wire::string(params, "threadId")
        .or_else(|| wire::nested_string(params, "thread", "id"))
        .or_else(|| wire::string(params, "conversationId"))
}

/// The answer for a request already covered by the session allowance.
pub(crate) fn allowed_result(method: &str) -> Value {
    if is_legacy(method) {
        json!({ "decision": "approved_for_session" })
    } else {
        json!({ "decision": "acceptForSession" })
    }
}

pub(crate) fn is_legacy(method: &str) -> bool {
    matches!(method, "execCommandApproval" | "applyPatchApproval")
}

impl<T> CodexProvider<T> {
    pub(crate) fn allowance_grant(&self, method: &str, params: &Value) -> Option<AllowanceGrant> {
        let kind = allowance_kind(method)?;
        let native_thread_id = request_native_thread_id(params).or_else(|| {
            self.session
                .as_ref()
                .map(|session| session.native_thread_id.clone())
        })?;
        Some(AllowanceGrant {
            native_thread_id,
            kind,
        })
    }
}
