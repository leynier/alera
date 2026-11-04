use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

/// Only effort has a verified runtime validation and adapter mapping. Other
/// provider options cannot bypass the host's launch or permission policy.
pub(super) fn delegation_effort(options: Option<&Value>) -> HostResult<Option<String>> {
    let Some(options) = options.filter(|value| !value.is_null()) else {
        return Ok(None);
    };
    let object = options.as_object().ok_or_else(unsupported_options)?;
    if object.keys().any(|key| key != "reasoningEffort") {
        return Err(unsupported_options());
    }
    alera_provider_protocol::reasoning_effort(object)
        .map(|effort| effort.map(ToOwned::to_owned))
        .map_err(|_| {
            HostError::format("reasoningEffort must be a nonempty string of at most 128 bytes")
        })
}

fn unsupported_options() -> HostError {
    HostError::conflict(
        "unsupported",
        "Only verified reasoning effort is supported in agent options.",
        json!({}),
    )
}
