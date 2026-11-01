//! Claude failures: SDK errors as provider errors, and failure classes from
//! the turn's typed signals: rate limit events, assistant `error` codes, and
//! the result's HTTP status and terminal reason.

use alera_provider_protocol::{FailureClass, ProviderError};
use claude_agent_sdk::{ClaudeSdkError, ResultMessage};
use std::collections::HashSet;

/// The provider error an SDK failure surfaces as.
pub(super) fn sdk_error(error: ClaudeSdkError) -> ProviderError {
    match error {
        ClaudeSdkError::Transport(message) => ProviderError::Protocol(message),
        ClaudeSdkError::Closed => ProviderError::Closed,
        ClaudeSdkError::Timeout { operation, .. } => ProviderError::Timeout { operation },
        other => ProviderError::Protocol(other.to_string()),
    }
}

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

/// CLI telemetry the result lists among its errors; never shown or failing.
const DIAGNOSTIC_ERROR_PREFIX: &str = "[ede_diagnostic]";
const API_ERROR_PREFIX: &str = "API Error:";
const MAX_API_ERROR_CHARS: usize = 500;
const OVERLOADED_MESSAGE: &str = "Claude API is overloaded (529). Try again shortly.";
const RATE_LIMITED_MESSAGE: &str = "Claude API rate limit reached. Try again later.";
const CONTEXT_WINDOW_FULL_MESSAGE: &str =
    "Claude stopped: the prompt exceeds the model's context window. Run /compact or start a new thread.";

/// Terminal reasons that end a turn unfinished even on a success-shaped,
/// unflagged result (Claude Code 2.1.316).
const FAILED_TERMINAL_REASONS: [&str; 11] = [
    "api_error",
    "malformed_tool_use_exhausted",
    "budget_exhausted",
    "structured_output_retry_exhausted",
    "tool_deferred_unavailable",
    "turn_setup_failed",
    "blocking_limit",
    "rapid_refill_breaker",
    "prompt_too_long",
    "image_error",
    "model_error",
];

/// The result's listed errors without blanks and CLI diagnostics.
pub(super) fn user_facing_errors(result: &ResultMessage) -> Vec<&str> {
    result
        .errors
        .iter()
        .flatten()
        .map(|error| error.trim())
        .filter(|error| !error.is_empty() && !error.starts_with(DIAGNOSTIC_ERROR_PREFIX))
        .collect()
}

/// Whether the result ends its turn unfinished. The CLI reports API errors
/// as `success` results, often without `is_error`.
pub(super) fn result_failed(result: &ResultMessage) -> bool {
    result.is_error
        || result.subtype.starts_with("error")
        || !user_facing_errors(result).is_empty()
        || matches!(result.api_error_status, Some(429 | 529))
        || result
            .terminal_reason
            .as_deref()
            .is_some_and(|reason| FAILED_TERMINAL_REASONS.contains(&reason))
}

/// The failed turn's message: Claude's own text first, then a fixed
/// sentence for the status or terminal reason.
pub(super) fn result_error_message(result: &ResultMessage, class: FailureClass) -> Option<String> {
    let errors = user_facing_errors(result);
    if !errors.is_empty() {
        return Some(errors.join("; "));
    }
    let text = result
        .result
        .as_deref()
        .map(str::trim)
        .filter(|text| !text.is_empty());
    if let Some(text) = text.filter(|text| text.starts_with(API_ERROR_PREFIX)) {
        return Some(text.chars().take(MAX_API_ERROR_CHARS).collect());
    }
    let reason = result.terminal_reason.as_deref();
    // Here the result text is the last assistant reply, not the error.
    if result.api_error_status == Some(529) {
        return Some(OVERLOADED_MESSAGE.into());
    }
    if reason == Some("api_error") && class == FailureClass::Unknown {
        return terminal_reason_message("api_error").map(str::to_owned);
    }
    if let Some(text) = text {
        return Some(text.to_owned());
    }
    reason
        .and_then(terminal_reason_message)
        .or_else(|| (result.api_error_status == Some(429)).then_some(RATE_LIMITED_MESSAGE))
        .map(str::to_owned)
}

fn terminal_reason_message(reason: &str) -> Option<&'static str> {
    Some(match reason {
        "api_error" => "Claude gave up after repeated API errors.",
        "malformed_tool_use_exhausted" => "Claude gave up after repeated malformed tool calls.",
        "budget_exhausted" => "Claude stopped: the turn's token budget was exhausted.",
        "structured_output_retry_exhausted" => {
            "Claude could not produce the requested structured output."
        }
        "tool_deferred_unavailable" => {
            "Claude could not resume a deferred tool call: the tool is no longer available."
        }
        "turn_setup_failed" => "Claude could not start the turn.",
        "blocking_limit" | "prompt_too_long" => CONTEXT_WINDOW_FULL_MESSAGE,
        "rapid_refill_breaker" => {
            "Claude stopped: the context refilled too quickly after compaction."
        }
        "image_error" => "Claude stopped: an image in the conversation could not be processed.",
        "model_error" => "Claude stopped: the model returned an error.",
        _ => return None,
    })
}
