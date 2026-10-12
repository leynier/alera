//! Why a host link failed to attach or dropped, read from the tail of `ssh`'s
//! stderr. The kind decides whether the supervisor retries and lets the app
//! tell an offline machine apart from a rejected key or a broken install.

use serde::{Deserialize, Serialize};

use super::host_error::HostError;

/// A failed attach with its kind. Boxed because [`HostError`] is large and
/// this travels in the `Err` side of every connect.
pub(crate) type AttachError = Box<(HostError, AttachFailureKind)>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum AttachFailureKind {
    /// The machine or its sshd could not be reached.
    Unreachable,
    /// sshd answered but refused the credentials or the host key.
    Authentication,
    /// ssh connected but the Alera runtime on the host did not attach.
    Satellite,
    /// The hub cannot even build the command: unknown or not installed host,
    /// or no `ssh` binary. Retrying cannot fix it.
    Configuration,
    Unknown,
}

impl AttachFailureKind {
    pub(crate) fn retries(self) -> bool {
        self != AttachFailureKind::Configuration
    }
}

const AUTHENTICATION_MARKERS: &[&str] = &[
    "permission denied",
    "host key verification failed",
    "authentication failed",
    "too many authentication failures",
    "no supported authentication methods",
    "remote host identification has changed",
];

const UNREACHABLE_MARKERS: &[&str] = &[
    "could not resolve hostname",
    "name or service not known",
    "nodename nor servname",
    "temporary failure in name resolution",
    "connection refused",
    "connection timed out",
    "operation timed out",
    "no route to host",
    "network is unreachable",
    "host is down",
    "connection reset",
    "connection closed by",
    "kex_exchange_identification",
    "broken pipe",
    "not responding",
    "connection to host lost",
];

const SATELLITE_MARKERS: &[&str] = &[
    "not recognized as an internal or external command",
    "command not found",
    ": not found",
    "no such file or directory",
    "unexpected first frame",
    "runtime-attach",
    "ssh closed before attaching",
];

/// Classifies an attach or close message. Matching is case-insensitive and
/// ordered: an authentication refusal can mention a closed connection, and a
/// network failure never mentions the runtime.
pub(crate) fn classify_attach_failure(message: &str) -> AttachFailureKind {
    let lower = message.to_lowercase();
    let has = |markers: &[&str]| markers.iter().any(|marker| lower.contains(marker));
    if has(AUTHENTICATION_MARKERS) {
        AttachFailureKind::Authentication
    } else if has(UNREACHABLE_MARKERS) {
        AttachFailureKind::Unreachable
    } else if has(SATELLITE_MARKERS) {
        AttachFailureKind::Satellite
    } else {
        AttachFailureKind::Unknown
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn real_ssh_tails_map_to_their_kind() {
        let cases = [
            (
                "Could not attach to host lab: ssh closed before attaching. dev@lab.local: Permission denied (publickey).",
                AttachFailureKind::Authentication,
            ),
            (
                "Host key verification failed.",
                AttachFailureKind::Authentication,
            ),
            (
                "Could not attach to host lab: ssh closed before attaching. ssh: Could not resolve hostname lab.local: Name or service not known",
                AttachFailureKind::Unreachable,
            ),
            (
                "ssh: connect to host 10.0.0.5 port 22: Connection refused",
                AttachFailureKind::Unreachable,
            ),
            (
                "ssh: connect to host mac.local port 22: Operation timed out",
                AttachFailureKind::Unreachable,
            ),
            (
                "ssh: connect to host 192.168.1.9 port 22: No route to host",
                AttachFailureKind::Unreachable,
            ),
            (
                "The link to host lab was closed. Timeout, server lab.local not responding.",
                AttachFailureKind::Unreachable,
            ),
            (
                "client_loop: send disconnect: Broken pipe",
                AttachFailureKind::Unreachable,
            ),
            (
                "kex_exchange_identification: read: Connection reset by peer",
                AttachFailureKind::Unreachable,
            ),
            (
                "sh: 1: /home/dev/.alera/sidecar/bin/alera: not found",
                AttachFailureKind::Satellite,
            ),
            (
                "'\"C:\\Users\\dev\\Alera\\runtime\\bin\\alera.cmd\"' is not recognized as an internal or external command,",
                AttachFailureKind::Satellite,
            ),
            (
                "Could not attach to host lab: unexpected first frame: hello.",
                AttachFailureKind::Satellite,
            ),
            (
                "The link to host lab was closed.",
                AttachFailureKind::Unknown,
            ),
        ];
        for (message, expected) in cases {
            assert_eq!(classify_attach_failure(message), expected, "{message}");
        }
    }

    #[test]
    fn only_configuration_failures_stop_retrying() {
        assert!(!AttachFailureKind::Configuration.retries());
        for kind in [
            AttachFailureKind::Unreachable,
            AttachFailureKind::Authentication,
            AttachFailureKind::Satellite,
            AttachFailureKind::Unknown,
        ] {
            assert!(kind.retries(), "{kind:?}");
        }
    }

    #[test]
    fn kinds_serialize_in_camel_case() {
        assert_eq!(
            serde_json::to_value(AttachFailureKind::Unreachable).unwrap(),
            "unreachable"
        );
        assert_eq!(
            serde_json::to_value(AttachFailureKind::Configuration).unwrap(),
            "configuration"
        );
    }
}
