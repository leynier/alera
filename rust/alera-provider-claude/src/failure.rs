//! Claude failure classes, from the turn's typed signals: rate limit events,
//! assistant `error` codes, and the result's HTTP status and terminal reason.

use alera_provider_protocol::FailureClass;
use claude_agent_sdk::ResultMessage;
use std::collections::HashSet;

/// What the running turn reported before its result.
#[derive(Debug, Default)]
pub(super) struct TurnFailureEvidence {
    /// Limit types the CLI rejected and has not allowed again.
    rejected_rate_limits: HashSet<String>,
    assistant_rate_limited: bool,
    auth_failed: bool,
}

impl TurnFailureEvidence {
    pub(super) fn rate_limit(&mut self, status: &str, limit_type: Option<&str>) {
        let limit_type = limit_type.unwrap_or("unknown").to_owned();
        match status {
            "rejected" => {
                self.rejected_rate_limits.insert(limit_type);
            }
            "allowed" => {
                self.rejected_rate_limits.remove(&limit_type);
            }
            _ => {}
        }
    }

    pub(super) fn assistant_error(&mut self, error: &str) {
        match error {
            "rate_limit" => self.assistant_rate_limited = true,
            "authentication_failed" => self.auth_failed = true,
            _ => {}
        }
    }

    pub(super) fn class(&self, result: &ResultMessage) -> FailureClass {
        let status = result.api_error_status;
        let reason = result.terminal_reason.as_deref();
        // The CLI also labels a 403 authentication_failed, but signing in
        // again cannot grant that access.
        if status == Some(401) || (self.auth_failed && status != Some(403)) {
            return FailureClass::Auth;
        }
        let limited = (!self.rejected_rate_limits.is_empty() || self.assistant_rate_limited)
            && status.is_none_or(|status| status == 429)
            && reason.is_none_or(|reason| matches!(reason, "api_error" | "blocking_limit"));
        if status == Some(429) || limited {
            return FailureClass::UsageLimit;
        }
        // The CLI also ends a turn with blocking_limit once the context
        // window is full, so only rate limit evidence makes it a usage limit.
        match reason {
            Some("prompt_too_long" | "blocking_limit") => FailureClass::ContextWindowFull,
            _ => FailureClass::Unknown,
        }
    }
}

/// Results the SDK reports without `is_error` that still end the turn
/// unfinished.
pub(super) fn result_failed_without_error(result: &ResultMessage) -> bool {
    result.api_error_status == Some(429)
        || matches!(
            result.terminal_reason.as_deref(),
            Some("prompt_too_long" | "blocking_limit")
        )
}
