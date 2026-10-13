//! Pure launch builders keep policy and process configuration reviewable.

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;

use alera_provider_protocol::ProviderError;
use serde_json::Value;

use super::super::provider_factory::{ProviderInstanceConfig, ProviderLaunch};
use super::super::provider_traits::provider_traits;
use super::os_environment;

#[path = "production_connection_config.rs"]
mod connections;

pub(super) enum ProductionConfig {
    Codex(Box<alera_provider_codex::CodexProviderConfig>),
    Claude(Box<alera_provider_claude::ClaudeProviderConfig>),
    Cursor(
        Box<alera_provider_cursor::CursorProviderConfig>,
        Option<Box<cursor_agent_sdk::CursorBridgeConfig>>,
    ),
    Grok(Box<alera_provider_grok::GrokProviderConfig>),
    Antigravity(Box<alera_provider_antigravity::AntigravityProviderConfig>),
    Registry(Box<alera_provider_acp_registry::AcpRegistryProviderConfig>),
    Pi(Box<alera_provider_pi::PiProviderConfig>),
    Muse(Box<alera_provider_muse::MuseProviderConfig>),
    OpenCode(Box<alera_provider_opencode::OpenCodeProviderConfig>),
}

pub(super) fn build_config(
    launch: &ProviderLaunch,
    env: &BTreeMap<String, String>,
) -> Result<ProductionConfig, ProviderError> {
    let instance = launch.instance.as_ref();
    validate_options(&launch.provider, instance)?;
    let traits = provider_traits(&launch.provider).expect("provider validated");
    let mode = serde_json::to_value(launch.runtime_mode).expect("runtime mode is serializable");
    if !traits
        .runtime_modes
        .contains(&mode.as_str().expect("runtime mode is a string"))
    {
        return Err(ProviderError::Unsupported(format!(
            "{} cannot honor runtime mode {}",
            launch.provider, mode
        )));
    }
    // Persisted instance options cannot override the chat's requested policy.
    let model = launch
        .model
        .clone()
        .or_else(|| instance.and_then(|value| value.default_model.clone()));
    let executable = instance.and_then(|value| value.executable.clone());
    let os_env = os_environment(env);
    match launch.provider.as_str() {
        "codex" => {
            let mut config = alera_provider_codex::CodexProviderConfig::default();
            config.executable = executable.unwrap_or(config.executable);
            config.args = merged_args(config.args, instance);
            config.cwd = launch.cwd.clone();
            config.env = os_env;
            config.instance_id = launch.provider_instance_id.clone();
            config.model = model;
            Ok(ProductionConfig::Codex(Box::new(config)))
        }
        "claudeAgent" => {
            reject_args("Claude Code", instance)?;
            let config = alera_provider_claude::ClaudeProviderConfig {
                provider_instance_id: launch.provider_instance_id.clone(),
                options: alera_provider_claude::ClaudeAgentOptions {
                    cli_path: executable,
                    cwd: launch.cwd.clone(),
                    model,
                    env: env.clone(),
                    ..Default::default()
                },
            };
            Ok(ProductionConfig::Claude(Box::new(config)))
        }
        "cursor" => connections::cursor(launch, env, model),
        "grok" => {
            reject_args("Grok ACP", instance)?;
            let mut config = alera_provider_grok::GrokProviderConfig::default();
            config.executable = executable.unwrap_or(config.executable);
            config.cwd = launch.cwd.clone();
            config.env = os_env;
            config.instance_id = launch.provider_instance_id.clone();
            config.model = model;
            config.runtime_mode = launch.runtime_mode;
            if let Some(method) = option_string(instance, "authMethod")? {
                config.auth_method =
                    serde_json::from_value(Value::String(method)).map_err(|_| {
                        ProviderError::Validation(
                            "Grok authMethod must be api_key or cached_token".into(),
                        )
                    })?;
            }
            config.validate()?;
            Ok(ProductionConfig::Grok(Box::new(config)))
        }
        "antigravity" => {
            let mut config = alera_provider_antigravity::AntigravityProviderConfig::default();
            config.executable = executable.unwrap_or(config.executable);
            config.args = merged_args(config.args, instance);
            config.cwd = launch.cwd.clone();
            config.env = os_env;
            config.instance_id = launch.provider_instance_id.clone();
            config.model = model;
            config.runtime_mode = launch.runtime_mode;
            config.profile_dir = option_string(instance, "profileDir")?.map(PathBuf::from);
            if let Some(method) = option_string(instance, "authMethodId")? {
                config.auth_method_id = method;
            }
            config.validate()?;
            Ok(ProductionConfig::Antigravity(Box::new(config)))
        }
        "acpRegistry" => {
            let mut config = alera_provider_acp_registry::AcpRegistryProviderConfig::default();
            config.source = alera_provider_acp_registry::AcpRegistrySource::Local;
            config.agent_id = option_string(instance, "agentId")?
                .unwrap_or_else(|| launch.provider_instance_id.clone());
            config.executable = executable;
            config.args = merged_args(config.args, instance);
            config.cwd = launch.cwd.clone();
            config.env = os_env;
            config.auth_method_id = option_string(instance, "authMethodId")?;
            config.instance_id = launch.provider_instance_id.clone();
            config.custom_models = instance
                .map(|value| value.models.clone())
                .unwrap_or_default();
            config.model = model;
            config.runtime_mode = launch.runtime_mode;
            config.validate()?;
            Ok(ProductionConfig::Registry(Box::new(config)))
        }
        "pi" => {
            let mut config = alera_provider_pi::PiProviderConfig::default();
            config.executable = executable.unwrap_or(config.executable);
            config.args = merged_args(config.args, instance);
            config.cwd = launch.cwd.clone();
            config.env = os_env;
            config.instance_id = launch.provider_instance_id.clone();
            config.model = model;
            config.runtime_mode = launch.runtime_mode;
            config.mcp_servers = launch.mcp_servers.clone();
            for server in &config.mcp_servers {
                server.validate()?;
                if !traits.capabilities.mcp_injection.supports(server) {
                    return Err(ProviderError::Unsupported(format!(
                        "Pi cannot attach MCP server {}",
                        server.name
                    )));
                }
            }
            Ok(ProductionConfig::Pi(Box::new(config)))
        }
        "muse" => {
            let defaults = muse_agent_sdk::MuseClientOptions::default();
            let config = alera_provider_muse::MuseProviderConfig {
                provider_instance_id: launch.provider_instance_id.clone(),
                options: muse_agent_sdk::MuseClientOptions {
                    executable: executable.unwrap_or(defaults.executable),
                    args: merged_args(defaults.args, instance),
                    cwd: launch.cwd.clone(),
                    env: os_env,
                    ..defaults
                },
            };
            // Model and runtime policy are applied by Muse's session boundary.
            Ok(ProductionConfig::Muse(Box::new(config)))
        }
        "opencode" => connections::opencode(launch, env, model),
        _ => unreachable!("provider validated"),
    }
}

pub(super) fn validate_options(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
) -> Result<(), ProviderError> {
    let supported = match provider {
        "codex" | "claudeAgent" | "pi" | "muse" => &[][..],
        "grok" => &["authMethod"][..],
        "antigravity" => &["profileDir", "authMethodId"][..],
        "acpRegistry" => &["agentId", "authMethodId"][..],
        "cursor" => &[
            "bridgeUrl",
            "bridgeBearerToken",
            "bearerToken",
            "allowRemoteBridge",
            "apiKey",
        ][..],
        "opencode" => &["serverUrl", "serverPassword", "generation"][..],
        other => {
            return Err(ProviderError::Unsupported(format!(
                "Unknown agent chat provider: {other}"
            )))
        }
    };
    if let Some(instance) = instance {
        if instance.provider != provider {
            return Err(ProviderError::Validation(
                "Provider instance belongs to a different provider.".into(),
            ));
        }
        if instance
            .executable
            .as_ref()
            .is_some_and(|path| path.as_os_str().is_empty())
        {
            return Err(ProviderError::Validation(
                "Provider executable must not be empty.".into(),
            ));
        }
        for key in instance.options.keys() {
            if !supported.contains(&key.as_str()) {
                return Err(ProviderError::Unsupported(format!(
                    "{provider} instance option `{key}` is not implemented"
                )));
            }
            if key == "allowRemoteBridge" {
                option_bool(Some(instance), key)?;
            } else {
                option_string(Some(instance), key)?;
            }
        }
        if matches!(provider, "grok" | "claudeAgent") {
            reject_args(provider, Some(instance))?;
        }
    }
    Ok(())
}

pub(super) fn option_string(
    instance: Option<&ProviderInstanceConfig>,
    key: &str,
) -> Result<Option<String>, ProviderError> {
    let Some(value) = instance.and_then(|value| value.options.get(key)) else {
        return Ok(None);
    };
    let value = value
        .as_str()
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| {
            ProviderError::Validation(format!("Provider option `{key}` must be a nonempty string"))
        })?;
    Ok(Some(value.to_owned()))
}

fn option_bool(
    instance: Option<&ProviderInstanceConfig>,
    key: &str,
) -> Result<bool, ProviderError> {
    match instance.and_then(|value| value.options.get(key)) {
        None => Ok(false),
        Some(Value::Bool(value)) => Ok(*value),
        Some(_) => Err(ProviderError::Validation(format!(
            "Provider option `{key}` must be a boolean"
        ))),
    }
}

fn merged_args(
    defaults: Vec<OsString>,
    instance: Option<&ProviderInstanceConfig>,
) -> Vec<OsString> {
    let Some(args) = instance.and_then(|value| value.args.as_ref()) else {
        return defaults;
    };
    let args: Vec<OsString> = args.iter().map(OsString::from).collect();
    if !defaults.is_empty() && args.starts_with(&defaults) {
        return args;
    }
    defaults.into_iter().chain(args).collect()
}

fn reject_args(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
) -> Result<(), ProviderError> {
    if instance
        .and_then(|value| value.args.as_ref())
        .is_some_and(|args| !args.is_empty())
    {
        return Err(ProviderError::Unsupported(format!(
            "{provider} custom args are not supported by its adapter boundary"
        )));
    }
    Ok(())
}

pub(super) fn validate_external_process_options(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
    launch_env: &BTreeMap<String, String>,
) -> Result<(), ProviderError> {
    if !launch_env.is_empty()
        || instance.is_some_and(|value| {
            value.executable.is_some()
                || value.args.as_ref().is_some_and(|args| !args.is_empty())
                || !value.env.is_empty()
        })
    {
        return Err(ProviderError::Unsupported(format!("An external {provider} endpoint cannot apply executable, args, or environment overrides; configure a locally managed process")));
    }
    Ok(())
}
