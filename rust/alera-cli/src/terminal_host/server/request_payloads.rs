use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn parse_payload<T>(payload: &Value) -> HostResult<T>
where
    T: serde::de::DeserializeOwned,
{
    serde_json::from_value(payload.clone()).map_err(|error| HostError::format(error.to_string()))
}

/// An error a request handler can hand back to the client. `anyhow` errors
/// keep their whole context chain, so a failure such as `git worktree add
/// failed` still says why, and a failed remote command becomes the typed
/// `remoteCommandFailed` conflict (see [`HostError::from_anyhow`]).
pub(super) trait IntoHostError {
    fn into_host_error(self) -> HostError;
}

impl IntoHostError for anyhow::Error {
    fn into_host_error(self) -> HostError {
        HostError::from_anyhow(&self)
    }
}

impl IntoHostError for HostError {
    fn into_host_error(self) -> HostError {
        self
    }
}

pub(super) fn json_result<T, E>(result: Result<T, E>) -> HostResult<Value>
where
    T: serde::Serialize,
    E: IntoHostError,
{
    result
        .map_err(IntoHostError::into_host_error)
        .and_then(|value| {
            serde_json::to_value(value).map_err(|error| HostError::format(error.to_string()))
        })
}

#[cfg(test)]
#[path = "request_payloads_tests.rs"]
mod tests;
