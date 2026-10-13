use crate::config::AcpFlavor;
use crate::provider::AcpProvider;
use agent_client_protocol::AcpError;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{ProviderError, RuntimeMode};
use serde_json::Value;

impl<T: JsonTransport> AcpProvider<T> {
    pub(crate) fn validate_runtime_policy(&self, mode: RuntimeMode) -> Result<(), ProviderError> {
        if let Some(custom_mode) = self.config.session_mode.as_deref() {
            if self.config.flavor == AcpFlavor::Grok {
                return Err(ProviderError::Unsupported(format!(
                    "Grok launch mode cannot use session mode `{custom_mode}`"
                )));
            }
        }
        if self.config.flavor != AcpFlavor::Grok {
            return Ok(());
        }
        let launch_mode = grok_launch_mode(&self.config.process.args);
        if launch_mode != mode {
            return Err(ProviderError::InvalidState(format!(
                "Grok process mode {:?} does not match requested runtime mode {:?}",
                launch_mode, mode
            )));
        }
        Ok(())
    }

    pub(crate) async fn apply_runtime_policy(
        &mut self,
        session_id: &str,
        mode: RuntimeMode,
    ) -> Result<(), ProviderError> {
        if self.config.flavor == AcpFlavor::Grok {
            return Ok(());
        }
        if let Some(custom_mode) = self.config.session_mode.clone() {
            if !self.supports_config_option("mode") {
                return Err(ProviderError::Unsupported(
                    "ACP agent did not advertise a mode configuration option".into(),
                ));
            }
            self.client
                .set_config_option(session_id, "mode", Value::String(custom_mode))
                .await
                .map_err(crate::runtime_response::acp_error)?;
            return Ok(());
        }
        let native_mode = match (self.config.flavor, mode) {
            (_, RuntimeMode::ApprovalRequired) => return Ok(()),
            (AcpFlavor::Antigravity, RuntimeMode::AutoAcceptEdits) => "auto_edit",
            (AcpFlavor::Antigravity, RuntimeMode::Auto) => "default",
            (AcpFlavor::Antigravity, RuntimeMode::FullAccess) => "yolo",
            (AcpFlavor::Generic | AcpFlavor::Registry, RuntimeMode::Auto) => "auto",
            (AcpFlavor::Generic | AcpFlavor::Registry, RuntimeMode::FullAccess) => "always-approve",
            requested => {
                return Err(ProviderError::Unsupported(format!(
                    "ACP flavor {:?} cannot represent runtime mode {:?}",
                    requested.0, requested.1
                )))
            }
        };
        if !self.supports_config_option("mode") {
            return Err(ProviderError::Unsupported(
                "ACP agent did not advertise a mode configuration option".into(),
            ));
        }
        self.client
            .set_config_option(session_id, "mode", Value::String(native_mode.into()))
            .await
            .map_err(crate::runtime_response::acp_error)?;
        Ok(())
    }

    pub(crate) async fn authenticate_after_required(&mut self) -> Result<(), ProviderError> {
        let method = self.config.auth_method.clone().ok_or_else(|| {
            ProviderError::Unsupported(
                "ACP agent requires authentication but no auth method was configured".into(),
            )
        })?;
        if let Some(initialized) = self.client.initialized() {
            if !initialized
                .auth_methods
                .iter()
                .any(|auth| auth.id == method)
            {
                return Err(ProviderError::Unsupported(format!(
                    "ACP auth method `{method}` was not advertised"
                )));
            }
        }
        self.client
            .authenticate(&method)
            .await
            .map_err(crate::runtime_response::acp_error)?;
        Ok(())
    }
}

pub(crate) fn is_auth_required(error: &AcpError) -> bool {
    match error {
        AcpError::Rpc { code, message, .. } => {
            *code == -32000
                || message.to_ascii_lowercase().contains("auth_required")
                || message
                    .to_ascii_lowercase()
                    .contains("authentication required")
        }
        AcpError::Protocol(message) => {
            let message = message.to_ascii_lowercase();
            message.contains("auth_required") || message.contains("authentication required")
        }
        _ => false,
    }
}

fn grok_launch_mode(args: &[std::ffi::OsString]) -> RuntimeMode {
    let mut permission_mode = None;
    let mut always_approve = false;
    let mut index = 0;
    while index < args.len() {
        let value = args[index].to_string_lossy();
        if value == "--always-approve" {
            always_approve = true;
        } else if value == "--permission-mode" {
            permission_mode = args
                .get(index + 1)
                .map(|next| next.to_string_lossy().into_owned());
            index += 1;
        }
        index += 1;
    }
    if always_approve {
        RuntimeMode::FullAccess
    } else {
        match permission_mode.as_deref() {
            Some("auto") => RuntimeMode::Auto,
            Some("accept-edits") => RuntimeMode::AutoAcceptEdits,
            _ => RuntimeMode::ApprovalRequired,
        }
    }
}
