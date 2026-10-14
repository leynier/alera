use crate::{runtime_response::acp_error, AcpProvider};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{ProviderError, ReasoningEffortCapabilities};
use serde_json::Value;

fn effort_option(options: &[Value]) -> Option<&Value> {
    let mut matches = options.iter().filter(|option| {
        option.get("category").and_then(Value::as_str) == Some("thought_level")
            || matches!(
                option
                    .get("id")
                    .or_else(|| option.get("configId"))
                    .and_then(Value::as_str),
                Some("reasoningEffort" | "reasoning_effort" | "effort")
            )
    });
    let option = matches.next()?;
    if matches.next().is_some() || option.get("type").and_then(Value::as_str) != Some("select") {
        return None;
    }
    option
        .get("id")
        .or_else(|| option.get("configId"))
        .and_then(Value::as_str)
        .filter(|id| !id.trim().is_empty())?;
    Some(option)
}

fn values(option: &Value) -> Vec<String> {
    fn collect(options: &[Value], values: &mut Vec<String>) {
        for option in options {
            if let Some(value) = option
                .get("value")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
            {
                if !values.iter().any(|existing| existing == value) {
                    values.push(value.into());
                }
            }
            if let Some(group) = option.get("options").and_then(Value::as_array) {
                collect(group, values);
            }
        }
    }
    let mut result = Vec::new();
    if let Some(options) = option.get("options").and_then(Value::as_array) {
        collect(options, &mut result);
    }
    result
}

/// Only values in a provider-advertised thought-level configuration option.
pub fn config_reasoning_efforts(options: &[Value]) -> Vec<String> {
    effort_option(options).map(values).unwrap_or_default()
}

pub fn default_config_reasoning_effort(options: &[Value]) -> Option<String> {
    let option = effort_option(options)?;
    option
        .get("currentValue")
        .and_then(Value::as_str)
        .filter(|current| values(option).iter().any(|value| value == current))
        .map(str::to_owned)
}

pub(crate) fn capabilities(options: &[Value]) -> ReasoningEffortCapabilities {
    let values = config_reasoning_efforts(options);
    let supported = !values.is_empty();
    ReasoningEffortCapabilities {
        session: supported,
        turn: supported,
        model_specific: true,
        values,
        session_wire_field: supported.then(|| "session/set_config_option {configId,value}".into()),
        turn_wire_field: supported
            .then(|| "session/set_config_option before session/prompt".into()),
    }
}

impl<T: JsonTransport> AcpProvider<T> {
    pub(crate) async fn apply_reasoning_effort(
        &mut self,
        native_thread_id: &str,
        effort: &str,
    ) -> Result<(), ProviderError> {
        let option = effort_option(&self.session_config_options).ok_or_else(|| {
            ProviderError::Unsupported(
                "ACP agent did not advertise an unambiguous thought-level option".into(),
            )
        })?;
        if !values(option).iter().any(|value| value == effort) {
            return Err(ProviderError::Unsupported(format!(
                "ACP agent did not advertise effort {effort}"
            )));
        }
        let id = option
            .get("id")
            .or_else(|| option.get("configId"))
            .and_then(Value::as_str)
            .expect("validated option id")
            .to_owned();
        let result = self
            .client
            .set_config_option(native_thread_id, &id, Value::String(effort.into()))
            .await
            .map_err(acp_error)?;
        if let Some(options) = result.get("configOptions").and_then(Value::as_array) {
            self.session_config_options = options.clone();
        }
        Ok(())
    }
}
