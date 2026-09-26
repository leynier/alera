//! Reconnect policy for a dropped realtime speech socket.
//!
//! Auth and configuration failures never retry: a bad key or a refused
//! handshake would otherwise keep opening provider sockets until the user
//! stops the session. Transient drops retry with capped exponential backoff
//! and give up after a bounded number of attempts.

use std::time::Duration;

pub(super) const REALTIME_RECONNECT_BASE_DELAY: Duration = Duration::from_secs(2);
pub(super) const REALTIME_RECONNECT_MAX_DELAY: Duration = Duration::from_secs(30);
pub(super) const REALTIME_RECONNECT_MAX_ATTEMPTS: u32 = 6;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum RealtimeReconnectPlan {
    Retry { delay: Duration },
    GiveUp { message: String },
}

/// Decides what to do after the socket closed. `attempts` counts the
/// reconnects already scheduled since the last successful setup.
pub(super) fn plan_realtime_reconnect(
    attempts: u32,
    failure: Option<&str>,
) -> RealtimeReconnectPlan {
    if let Some(message) = failure.filter(|message| is_permanent_realtime_failure(message)) {
        return RealtimeReconnectPlan::GiveUp {
            message: format!("Realtime speech stopped: {message}"),
        };
    }
    if attempts >= REALTIME_RECONNECT_MAX_ATTEMPTS {
        let reason = failure.unwrap_or("the connection kept dropping");
        return RealtimeReconnectPlan::GiveUp {
            message: format!(
                "Realtime speech stopped after {attempts} reconnect attempts: {reason}"
            ),
        };
    }
    RealtimeReconnectPlan::Retry {
        delay: realtime_reconnect_delay(attempts),
    }
}

pub(super) fn realtime_reconnect_delay(attempts: u32) -> Duration {
    REALTIME_RECONNECT_BASE_DELAY
        .saturating_mul(2_u32.saturating_pow(attempts))
        .min(REALTIME_RECONNECT_MAX_DELAY)
}

/// True for failures that another attempt with the same settings cannot fix:
/// rejected or missing credentials, a refused handshake, or an unknown model.
pub(super) fn is_permanent_realtime_failure(message: &str) -> bool {
    let lowered = message.to_ascii_lowercase();
    [
        "http 400",
        "http 401",
        "http 403",
        "http 404",
        "unauthorized",
        "forbidden",
        "api key",
        "api_key",
        "permission denied",
        "permission_denied",
        "authentication",
        "is not found",
    ]
    .iter()
    .any(|needle| lowered.contains(needle))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auth_and_handshake_refusals_do_not_retry() {
        for message in [
            "realtime handshake refused: HTTP 401 Unauthorized",
            "realtime handshake refused: HTTP 403 Forbidden",
            "realtime socket closed (1008): API key not valid. Please pass a valid API key.",
            "Incorrect API key provided: sk-***",
            "A Gemini API key is required for Gemini Live.",
        ] {
            assert!(
                matches!(
                    plan_realtime_reconnect(0, Some(message)),
                    RealtimeReconnectPlan::GiveUp { .. }
                ),
                "{message}"
            );
        }
    }

    #[test]
    fn transient_drops_back_off_and_cap() {
        let failure = Some("realtime socket failed: Connection reset without closing handshake");
        assert_eq!(
            plan_realtime_reconnect(0, failure),
            RealtimeReconnectPlan::Retry {
                delay: Duration::from_secs(2)
            }
        );
        assert_eq!(
            plan_realtime_reconnect(1, None),
            RealtimeReconnectPlan::Retry {
                delay: Duration::from_secs(4)
            }
        );
        assert_eq!(realtime_reconnect_delay(3), Duration::from_secs(16));
        assert_eq!(realtime_reconnect_delay(4), REALTIME_RECONNECT_MAX_DELAY);
        assert_eq!(realtime_reconnect_delay(40), REALTIME_RECONNECT_MAX_DELAY);
    }

    #[test]
    fn transient_drops_give_up_after_the_attempt_cap() {
        let plan = plan_realtime_reconnect(
            REALTIME_RECONNECT_MAX_ATTEMPTS,
            Some("realtime connect failed: IO error: connection refused"),
        );
        let RealtimeReconnectPlan::GiveUp { message } = plan else {
            panic!("expected give up");
        };
        assert!(message.contains("connection refused"), "{message}");
        assert!(message.contains("6 reconnect attempts"), "{message}");
    }
}
