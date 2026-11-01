//! Muse does not give workflow children a full-access session's `allowAll`
//! mode, so the adapter approves their requests instead of showing them.

use crate::events::PendingRequest;
use crate::provider::MuseProvider;
use alera_provider_protocol::{ApprovalDecision, RequestKind};
use serde_json::Value;

/// The subject kinds MSP defines; clients never auto-approve another kind.
const KNOWN_SUBJECTS: [&str; 6] = [
    "shell",
    "fileAccess",
    "network",
    "unixSocket",
    "process",
    "tool",
];

impl MuseProvider {
    /// Approves a child's request once in a full-access session. False
    /// leaves it for the person, including when Muse refuses the decision.
    pub(crate) async fn auto_approve_child(&mut self, request: &PendingRequest) -> bool {
        if self.approval_mode != Some("allowAll") || !is_child_approval(request) {
            return false;
        }
        let requirement = request
            .params
            .get("currentRequirementId")
            .cloned()
            .unwrap_or(Value::Null);
        // `approval/request` and `approval/requested` announce the same stage.
        if self.auto_approved.get(&request.logical_id) == Some(&requirement) {
            return true;
        }
        match self
            .decide_approval(request, ApprovalDecision::Accept)
            .await
        {
            Ok(()) => {
                self.auto_approved
                    .insert(request.logical_id.clone(), requirement);
                true
            }
            Err(_) => {
                self.auto_approved.remove(&request.logical_id);
                false
            }
        }
    }
}

fn is_child_approval(request: &PendingRequest) -> bool {
    !matches!(request.kind, RequestKind::ToolUserInput)
        && request
            .params
            .get("subagentOrigin")
            .is_some_and(Value::is_object)
        && request
            .params
            .get("subject")
            .and_then(|subject| subject.get("kind"))
            .and_then(Value::as_str)
            .is_some_and(|kind| KNOWN_SUBJECTS.contains(&kind))
}
