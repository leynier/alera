//! Local helper processes and explicit external endpoints use distinct options.

use alera_provider_protocol::ProviderError;
use std::collections::BTreeMap;

use super::super::super::provider_factory::ProviderLaunch;
use super::super::os_environment;
use super::{
    merged_args, option_bool, option_string, validate_external_process_options, ProductionConfig,
};

pub(super) fn cursor(
    launch: &ProviderLaunch,
    env: &BTreeMap<String, String>,
    model: Option<String>,
) -> Result<ProductionConfig, ProviderError> {
    let instance = launch.instance.as_ref();
    let url = option_string(instance, "bridgeUrl")?;
    let token = option_string(instance, "bridgeBearerToken")?;
    let alias = option_string(instance, "bearerToken")?;
    if token.is_some() && alias.is_some() && token != alias {
        return Err(ProviderError::Validation(
            "Cursor bridge bearer token aliases conflict.".into(),
        ));
    }
    let token = token.or(alias);
    let config = alera_provider_cursor::CursorProviderConfig {
        provider_instance_id: launch.provider_instance_id.clone(),
        bridge_url: url.clone().unwrap_or_default(),
        bridge_bearer_token: token.clone().unwrap_or_default(),
        allow_remote_bridge: option_bool(instance, "allowRemoteBridge")?,
        api_key: option_string(instance, "apiKey")?.or_else(|| env.get("CURSOR_API_KEY").cloned()),
        cwd: launch.cwd.clone(),
        model,
        ..Default::default()
    };
    if url.is_some() {
        validate_external_process_options("cursor", instance, &launch.env)?;
        if token.is_none() {
            return Err(ProviderError::Validation(
                "Cursor bridge bearer token is required.".into(),
            ));
        }
        return Ok(ProductionConfig::Cursor(Box::new(config), None));
    }
    if token.is_some() {
        return Err(ProviderError::Unsupported("Cursor bridge bearer token requires bridgeUrl; local bridges supply their own handshake token.".into()));
    }
    let mut bridge = cursor_agent_sdk::CursorBridgeConfig::default();
    bridge.process.executable = instance
        .and_then(|value| value.executable.clone())
        .unwrap_or_else(|| "cursor-sdk-bridge".into());
    let mut args = Vec::new();
    if let Some(cwd) = &launch.cwd {
        args.extend(["--workspace".into(), cwd.as_os_str().to_owned()]);
    }
    bridge.process.args = merged_args(args, instance);
    bridge.process.cwd = launch.cwd.clone();
    bridge.process.env = os_environment(env);
    if let Some(api_key) = &config.api_key {
        bridge
            .process
            .env
            .entry("CURSOR_API_KEY".into())
            .or_insert_with(|| api_key.into());
    }
    bridge
        .process
        .env
        .entry("CURSOR_SDK_CLIENT_LANGUAGE".into())
        .or_insert_with(|| "rust".into());
    bridge.allow_remote_endpoint = config.allow_remote_bridge;
    Ok(ProductionConfig::Cursor(
        Box::new(config),
        Some(Box::new(bridge)),
    ))
}

pub(super) fn opencode(
    launch: &ProviderLaunch,
    env: &BTreeMap<String, String>,
    model: Option<String>,
) -> Result<ProductionConfig, ProviderError> {
    let instance = launch.instance.as_ref();
    let mut config = alera_provider_opencode::OpenCodeProviderConfig::default();
    config.provider_instance_id = launch.provider_instance_id.clone();
    config.executable = instance
        .and_then(|value| value.executable.clone())
        .unwrap_or(config.executable);
    config.args = merged_args(config.args, instance);
    config.cwd = launch.cwd.clone();
    config.env = os_environment(env);
    config.server_url = option_string(instance, "serverUrl")?;
    config.server_password = option_string(instance, "serverPassword")?;
    config.directory = launch.cwd.clone();
    config.model = model;
    if let Some(generation) = option_string(instance, "generation")? {
        config.generation = match generation.as_str() {
            "legacy1" => alera_provider_opencode::OpenCodeGeneration::Legacy1,
            "v2" => alera_provider_opencode::OpenCodeGeneration::V2,
            _ => {
                return Err(ProviderError::Validation(
                    "OpenCode generation must be legacy1 or v2.".into(),
                ))
            }
        };
    }
    if config.server_url.is_some() {
        validate_external_process_options("opencode", instance, &launch.env)?;
        if !launch.mcp_servers.is_empty() {
            return Err(ProviderError::Unsupported(
                "An external OpenCode server cannot attach chat-scoped MCP servers.".into(),
            ));
        }
    }
    Ok(ProductionConfig::OpenCode(Box::new(config)))
}
