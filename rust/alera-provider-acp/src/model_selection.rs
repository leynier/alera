//! Writes the session's model the way the session keeps it, after T3 Code's
//! `configureSession`: a model config option through
//! `session/set_config_option`, the legacy `models` state through
//! `session/set_model`.

use crate::config::AcpFlavor;
use crate::model_inventory::{self, ModelInventory};
use crate::runtime_response::acp_error;
use crate::AcpProvider;
use agent_client_protocol::{AcpError, AcpProtocolGeneration};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{FailureClass, ProviderError};
use serde_json::Value;

/// The error of a refused model write. Invalid params is the agent refusing
/// the value; other failures, such as sign-in or a lost connection, keep
/// their own error.
pub(crate) fn model_write_error(model: &str, error: AcpError) -> ProviderError {
    match error {
        AcpError::Rpc { code: -32602, .. } => rejected_model(model),
        error => acp_error(error),
    }
}

/// The readable refusal of a model the session does not take.
pub(crate) fn rejected_model(model: &str) -> ProviderError {
    ProviderError::Rejected {
        class: FailureClass::Unknown,
        detail: format!(
            "The agent did not accept the model \"{model}\". Choose another model for this provider, then retry."
        ),
    }
}

impl<T: JsonTransport> AcpProvider<T> {
    /// How the live session selects its model.
    pub(crate) fn model_inventory(&self) -> ModelInventory {
        let v1 = self.protocol_generation() == AcpProtocolGeneration::V1;
        let set_model_capability = v1
            && self.client.initialized().is_some_and(|initialized| {
                initialized
                    .capabilities
                    .supports(&["sessionCapabilities", "setModel"])
                    || initialized.capabilities.supports(&["setModel"])
            });
        model_inventory::inventory(
            &self.session_config_options,
            self.session_models.as_ref(),
            v1 && self.config.flavor == AcpFlavor::Grok,
            set_model_capability,
        )
    }

    /// Adopts the `configOptions` a config write returns.
    pub(crate) fn adopt_config_options(&mut self, result: &Value) {
        if let Some(options) = result.get("configOptions").and_then(Value::as_array) {
            self.session_config_options = options.clone();
        }
    }

    /// Writes `model` to the session. When nothing says the agent can change
    /// its model, a resumed session keeps its own and a new one is refused.
    pub(crate) async fn apply_model(
        &mut self,
        native_thread_id: &str,
        model: &str,
        resuming: bool,
    ) -> Result<(), ProviderError> {
        match self.model_inventory() {
            ModelInventory::Option { id, .. } => {
                let result = self
                    .client
                    .set_config_option(native_thread_id, &id, Value::String(model.into()))
                    .await
                    .map_err(|error| model_write_error(model, error))?;
                self.adopt_config_options(&result);
            }
            ModelInventory::Legacy(state) => {
                if state.current.as_deref() != Some(model) {
                    let result = self
                        .client
                        .set_model(native_thread_id, model)
                        .await
                        .map_err(|error| model_write_error(model, error))?;
                    self.adopt_config_options(&result);
                }
                if let Some(state) = self.session_models.as_mut() {
                    state.current = Some(model.into());
                }
            }
            ModelInventory::Capability => {
                let result = self
                    .client
                    .set_model(native_thread_id, model)
                    .await
                    .map_err(|error| model_write_error(model, error))?;
                self.adopt_config_options(&result);
            }
            ModelInventory::Unknown if resuming => {}
            ModelInventory::Unknown => {
                return Err(ProviderError::Unsupported(
                    "This agent does not let Alera choose its model. Clear the model for this provider, then retry.".into(),
                ))
            }
        }
        Ok(())
    }

    /// Applies a turn's model before its prompt: a changed model is written,
    /// an unchanged one is only checked.
    pub(crate) async fn apply_turn_model(
        &mut self,
        native_thread_id: &str,
        model: Option<&str>,
    ) -> Result<(), ProviderError> {
        let Some(model) = model else {
            return Ok(());
        };
        let current = self
            .session
            .as_ref()
            .and_then(|session| session.model.clone());
        if current.as_deref() == Some(model) {
            return self.validate_model(model);
        }
        self.validate_model(model)?;
        self.apply_model(native_thread_id, model, false).await?;
        if let Some(session) = self.session.as_mut() {
            session.model = Some(model.into());
        }
        Ok(())
    }

    /// Checks `model` against what the session offers before any write.
    pub(crate) fn validate_model(&self, _model: &str) -> Result<(), ProviderError> {
        Ok(())
    }

    /// Selects `model` on the live session, for probes that walk the models
    /// a session offers.
    pub async fn select_model(&mut self, model: &str) -> Result<(), ProviderError> {
        let native = self
            .session
            .as_ref()
            .map(|session| session.native_thread_id.clone())
            .ok_or_else(|| ProviderError::InvalidState("start an ACP session first".into()))?;
        self.validate_model(model)?;
        self.apply_model(&native, model, false).await?;
        if let Some(session) = self.session.as_mut() {
            session.model = Some(model.into());
        }
        Ok(())
    }

    /// The live session's config options.
    pub fn session_config_options(&self) -> &[Value] {
        &self.session_config_options
    }

    /// The `(id, label)` models the live session offers.
    pub fn session_model_choices(&self) -> Vec<(String, String)> {
        model_inventory::session_model_choices(
            &self.session_config_options,
            self.session_models.as_ref(),
        )
    }

    /// The live session's current model, as the agent reports it.
    pub fn session_current_model(&self) -> Option<String> {
        model_inventory::current_model(&self.session_config_options, self.session_models.as_ref())
    }
}
