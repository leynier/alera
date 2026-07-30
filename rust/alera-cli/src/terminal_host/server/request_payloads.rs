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
