use crate::{error::nonempty, ProviderError};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

pub const REASONING_EFFORT_OPTION: &str = "reasoningEffort";

/// Wire support, not a promise that every model accepts every effort.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReasoningEffortCapabilities {
    pub session: bool,
    pub turn: bool,
    pub model_specific: bool,
    pub values: Vec<String>,
    pub session_wire_field: Option<String>,
    pub turn_wire_field: Option<String>,
}

pub fn reasoning_effort(options: &Map<String, Value>) -> Result<Option<&str>, ProviderError> {
    options
        .get(REASONING_EFFORT_OPTION)
        .map(|value| {
            let effort = value.as_str().ok_or_else(|| {
                ProviderError::Validation("reasoningEffort must be a string".into())
            })?;
            nonempty(effort, REASONING_EFFORT_OPTION)?;
            if effort.len() > 128 {
                return Err(ProviderError::Validation(
                    "reasoningEffort exceeds 128 bytes".into(),
                ));
            }
            Ok(effort)
        })
        .transpose()
}
