use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn parse_payload<T>(payload: &Value) -> HostResult<T>
where
    T: serde::de::DeserializeOwned,
{
    serde_json::from_value(payload.clone()).map_err(|error| HostError::format(error.to_string()))
}

pub(super) fn json_result<T, E>(result: Result<T, E>) -> HostResult<Value>
where
    T: serde::Serialize,
    E: std::fmt::Display,
{
    result
        .map_err(|error| HostError::state(error.to_string()))
        .and_then(|value| {
            serde_json::to_value(value).map_err(|error| HostError::format(error.to_string()))
        })
}

/// [`json_result`] for `anyhow` errors, which keeps the context chain and
/// types a failed remote command (see [`HostError::from_anyhow`]).
pub(super) fn anyhow_json_result<T>(result: anyhow::Result<T>) -> HostResult<Value>
where
    T: serde::Serialize,
{
    result
        .map_err(|error| HostError::from_anyhow(&error))
        .and_then(|value| {
            serde_json::to_value(value).map_err(|error| HostError::format(error.to_string()))
        })
}
