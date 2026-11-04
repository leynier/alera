//! Existing Rust identity fields use a sentinel; the wire exposes null.

#[cfg(test)]
#[path = "agent_chat_selection_tests.rs"]
mod tests;

use serde::{Deserialize, Deserializer, Serializer};

pub const AGENT_CHAT_UNSELECTED_PROVIDER: &str = "unselected";

pub(super) fn serialize<S: Serializer>(value: &str, serializer: S) -> Result<S::Ok, S::Error> {
    if value == AGENT_CHAT_UNSELECTED_PROVIDER {
        serializer.serialize_none()
    } else {
        serializer.serialize_str(value)
    }
}

pub(super) fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<String, D::Error> {
    Ok(Option::<String>::deserialize(deserializer)?
        .unwrap_or_else(|| AGENT_CHAT_UNSELECTED_PROVIDER.into()))
}
