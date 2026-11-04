use super::*;
use alera_provider_protocol::ReasoningEffortCapabilities;
use cursor_agent_sdk::{ModelParameterDefinition, ModelParameterValue, SdkModel};

/// Parameter identifiers and values are provider-advertised, not inferred from model names.
pub fn model_reasoning_efforts(model: &SdkModel) -> Vec<String> {
    effort_parameter(model)
        .map(|parameter| {
            parameter
                .values
                .iter()
                .map(|value| value.value.clone())
                .collect()
        })
        .unwrap_or_default()
}

pub fn default_model_reasoning_effort(model: &SdkModel) -> Option<String> {
    let parameter = effort_parameter(model)?;
    let variant = model.variants.iter().find(|variant| variant.is_default)?;
    variant
        .params
        .iter()
        .find(|value| value.id == parameter.id)
        .map(|value| value.value.clone())
        .filter(|value| parameter.values.iter().any(|choice| &choice.value == value))
}

fn effort_parameter(model: &SdkModel) -> Option<&ModelParameterDefinition> {
    let mut parameters = model.parameters.iter().filter(|parameter| {
        matches!(
            parameter.id.as_str(),
            "reasoningEffort" | "reasoning_effort" | "effort"
        )
    });
    let first = parameters.next()?;
    parameters.next().is_none().then_some(first)
}

pub(super) fn capabilities(provider: &CursorProvider) -> ReasoningEffortCapabilities {
    let values = provider
        .session
        .as_ref()
        .and_then(|session| session.model.as_deref())
        .and_then(|id| provider.effort_models.iter().find(|model| model.id == id))
        .map(model_reasoning_efforts)
        .unwrap_or_default();
    ReasoningEffortCapabilities {
        session: true,
        turn: true,
        model_specific: true,
        values,
        session_wire_field: Some("model.params[].{id,value}".into()),
        turn_wire_field: Some("model.params[].{id,value}".into()),
    }
}

impl CursorProvider {
    pub(super) async fn discover_effort_models(&mut self) -> Result<(), ProviderError> {
        if !self.effort_models.is_empty() {
            return Ok(());
        }
        let key = self.config.api_key.as_deref().ok_or_else(|| {
            ProviderError::Unsupported(
                "Cursor effort requires authenticated model parameter discovery".into(),
            )
        })?;
        let result = self
            .client
            .list_models(key)
            .await
            .map_err(|error| ProviderError::Protocol(error.to_string()))?;
        let models = result
            .get("models")
            .cloned()
            .ok_or_else(|| ProviderError::Protocol("Cursor model response has no models".into()))?;
        self.effort_models = serde_json::from_value(models).map_err(|error| {
            ProviderError::Protocol(format!("invalid Cursor model parameters: {error}"))
        })?;
        Ok(())
    }

    pub(super) fn model_selection(
        &self,
        model: Option<String>,
        effort: Option<&str>,
    ) -> Result<Option<ModelSelection>, ProviderError> {
        let Some(id) = model else {
            return if effort.is_some() {
                Err(ProviderError::Unsupported(
                    "Cursor effort requires an explicitly selected model".into(),
                ))
            } else {
                Ok(None)
            };
        };
        let params = if let Some(effort) = effort {
            let parameter = self
                .effort_models
                .iter()
                .find(|model| model.id == id)
                .and_then(effort_parameter)
                .ok_or_else(|| {
                    ProviderError::Unsupported(
                        "Cursor model did not advertise an unambiguous effort parameter".into(),
                    )
                })?;
            if !parameter.values.iter().any(|choice| choice.value == effort) {
                return Err(ProviderError::Unsupported(format!(
                    "Cursor model {id} did not advertise effort {effort}"
                )));
            }
            vec![ModelParameterValue {
                id: parameter.id.clone(),
                value: effort.into(),
            }]
        } else {
            Vec::new()
        };
        Ok(Some(ModelSelection { id, params }))
    }
}
