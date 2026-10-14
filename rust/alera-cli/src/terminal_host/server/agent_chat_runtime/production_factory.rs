//! Constructs adapters through their existing process and connection boundaries.

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

use alera_agent_http::{HttpClientConfig, ReqwestTransport};
use alera_provider_protocol::ProviderError;
use async_trait::async_trait;

use super::provider_factory::{
    BoxedProvider, ProviderFactory, ProviderInstanceConfig, ProviderLaunch, ProviderStatus,
};

#[path = "production_launch_config.rs"]
mod launch_config;
#[path = "production_opencode_generation.rs"]
mod opencode_generation;
#[path = "production_owned_provider.rs"]
mod owned_provider;
#[cfg(test)]
#[path = "production_factory_tests.rs"]
mod tests;

use launch_config::{build_config, ProductionConfig};
use owned_provider::OwnedProvider;
#[path = "../agent_chat_provider_settings/production_catalog.rs"]
mod inspection;
use inspection::resolve_instance;

#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct ProductionProviderFactory;

#[async_trait]
impl ProviderFactory for ProductionProviderFactory {
    async fn spawn(&self, launch: &ProviderLaunch) -> Result<BoxedProvider, ProviderError> {
        let mut launch = launch.clone();
        launch.instance = resolve_instance(launch.instance.as_ref()).await?;
        let launch = &launch;
        let env = hydrated_environment(launch.instance.as_ref(), &launch.env).await?;
        let mut config = build_config(launch, &env)?;
        if let ProductionConfig::OpenCode(config) = &mut config {
            opencode_generation::resolve(launch, config).await?;
        }
        match config {
            ProductionConfig::Codex(config) => Ok(Box::new(
                alera_provider_codex::CodexProvider::spawn(*config).await?,
            )),
            ProductionConfig::Claude(config) => Ok(Box::new(
                alera_provider_claude::ClaudeProvider::new(*config)?,
            )),
            ProductionConfig::Cursor(config, Some(bridge)) => {
                Ok(Box::new(OwnedProvider::cursor(*config, *bridge).await?))
            }
            ProductionConfig::Cursor(config, None) => Ok(Box::new(
                alera_provider_cursor::CursorProvider::connect(*config)?,
            )),
            ProductionConfig::Grok(config) => Ok(Box::new(
                alera_provider_grok::GrokProvider::spawn(*config).await?,
            )),
            ProductionConfig::Antigravity(config) => Ok(Box::new(
                alera_provider_antigravity::AntigravityProvider::spawn(*config).await?,
            )),
            ProductionConfig::Registry(config) => Ok(Box::new(
                alera_provider_acp_registry::AcpRegistryProvider::spawn(*config).await?,
            )),
            ProductionConfig::Pi(config) => Ok(Box::new(
                alera_provider_pi::PiProvider::spawn(*config).await?,
            )),
            ProductionConfig::Muse(config) => {
                Ok(Box::new(alera_provider_muse::MuseProvider::new(*config)?))
            }
            ProductionConfig::OpenCode(config) if config.server_url.is_none() => {
                Ok(Box::new(OwnedProvider::opencode(*config).await?))
            }
            ProductionConfig::OpenCode(config) => {
                let transport = ReqwestTransport::new(HttpClientConfig {
                    base_url: config
                        .server_url
                        .clone()
                        .expect("external server URL checked"),
                    request_timeout: config.request_timeout,
                    ..Default::default()
                })
                .map_err(|error| ProviderError::Protocol(error.to_string()))?;
                Ok(Box::new(alera_provider_opencode::OpenCodeProvider::new(
                    transport, *config,
                )))
            }
        }
    }

    async fn availability(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
    ) -> Result<(), String> {
        let instance = resolve_instance(instance)
            .await
            .map_err(|_| "Provider credentials are unavailable.".to_owned())?;
        let instance = instance.as_ref();
        let environment = hydrated_environment(instance, &BTreeMap::new())
            .await
            .map_err(|error| error.to_string())?;
        let launch = ProviderLaunch {
            chat_id: "availability".into(),
            generation: 0,
            provider: provider.into(),
            provider_instance_id: instance
                .map(|value| value.provider_instance_id.clone())
                .unwrap_or_else(|| provider.into()),
            cwd: None,
            model: None,
            runtime_mode: Default::default(),
            instance: instance.cloned(),
            mcp_servers: Vec::new(),
            env: BTreeMap::new(),
        };
        let executable =
            match build_config(&launch, &environment).map_err(|error| error.to_string())? {
                ProductionConfig::Codex(config) => config.executable,
                ProductionConfig::Claude(config) => {
                    config.options.cli_path.unwrap_or_else(|| "claude".into())
                }
                ProductionConfig::Cursor(_, Some(bridge)) => bridge.process.executable,
                ProductionConfig::Cursor(config, None) => {
                    return cursor_agent_sdk::CursorClient::connect(config.client_config())
                        .map(|_| ())
                        .map_err(|error| error.to_string());
                }
                ProductionConfig::Grok(config) => config.executable,
                ProductionConfig::Antigravity(config) => config.executable,
                ProductionConfig::Registry(config) => {
                    config.executable.expect("local recipe validated")
                }
                ProductionConfig::Pi(config) => config.executable,
                ProductionConfig::Muse(config) => config.options.executable,
                ProductionConfig::OpenCode(config) if config.server_url.is_some() => {
                    return ReqwestTransport::new(HttpClientConfig {
                        base_url: config.server_url.expect("external URL checked"),
                        request_timeout: config.request_timeout,
                        ..Default::default()
                    })
                    .map(|_| ())
                    .map_err(|error| error.to_string());
                }
                ProductionConfig::OpenCode(config) => config.executable,
            };
        executable_available(Some(&executable), "", &environment)
    }

    async fn status(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
    ) -> ProviderStatus {
        inspection::status(self, provider, instance).await
    }
    async fn discover_model_metadata(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
        cwd: Option<PathBuf>,
    ) -> Option<Result<Vec<serde_json::Value>, String>> {
        inspection::models(provider, instance, cwd).await
    }
    async fn discover_models(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
        cwd: Option<PathBuf>,
    ) -> Option<Result<Vec<String>, String>> {
        self.discover_model_metadata(provider, instance, cwd)
            .await
            .map(|result| {
                result.map(|models| {
                    models
                        .into_iter()
                        .filter_map(|model| model["id"].as_str().map(str::to_owned))
                        .collect()
                })
            })
    }
    async fn validate_reasoning_effort(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
        cwd: Option<PathBuf>,
        model: Option<&str>,
        effort: &str,
    ) -> Result<(), String> {
        inspection::validate_effort(provider, instance, cwd, model, effort).await
    }

    async fn cached_verified_auth_status(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
    ) -> Option<(String, String)> {
        inspection::cached_auth_evidence(provider, instance).await
    }
}

pub(crate) fn validate_instance(instance: &ProviderInstanceConfig) -> Result<(), ProviderError> {
    launch_config::validate_options(&instance.provider, Some(instance))
}

async fn hydrated_environment(
    instance: Option<&ProviderInstanceConfig>,
    overrides: &BTreeMap<String, String>,
) -> Result<BTreeMap<String, String>, ProviderError> {
    let environment = alera_core::login_shell_environment::login_shell_command_environment()
        .await
        .unwrap_or_else(|| std::env::vars().collect());
    Ok(merge_environment(environment, instance, overrides))
}

fn merge_environment(
    mut environment: BTreeMap<String, String>,
    instance: Option<&ProviderInstanceConfig>,
    overrides: &BTreeMap<String, String>,
) -> BTreeMap<String, String> {
    if let Some(instance) = instance {
        environment.extend(instance.env.clone());
    }
    environment.extend(overrides.clone());
    environment
}

fn os_environment(values: &BTreeMap<String, String>) -> BTreeMap<OsString, OsString> {
    values
        .iter()
        .map(|(key, value)| (key.into(), value.into()))
        .collect()
}

fn executable_available(
    explicit: Option<&Path>,
    default: &str,
    environment: &BTreeMap<String, String>,
) -> Result<(), String> {
    let candidate = explicit
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from(default));
    if candidate.as_os_str().is_empty() {
        return Err("Provider executable is not configured.".into());
    }
    let paths = if candidate.is_absolute() || candidate.components().count() > 1 {
        vec![candidate.clone()]
    } else {
        std::env::split_paths(
            environment
                .get("PATH")
                .map(String::as_str)
                .unwrap_or_default(),
        )
        .flat_map(|directory| executable_candidates(directory.join(&candidate), environment))
        .collect()
    };
    if paths.iter().any(|path| executable_file(path)) {
        Ok(())
    } else {
        Err(format!(
            "Provider executable is unavailable: {}",
            candidate.display()
        ))
    }
}

fn executable_candidates(path: PathBuf, _environment: &BTreeMap<String, String>) -> Vec<PathBuf> {
    #[cfg(windows)]
    if path.extension().is_none() {
        let extensions = _environment
            .get("PATHEXT")
            .map(String::as_str)
            .unwrap_or(".COM;.EXE;.BAT;.CMD");
        return extensions
            .split(';')
            .filter(|value| !value.is_empty())
            .map(|extension| {
                let mut candidate = path.as_os_str().to_owned();
                candidate.push(extension);
                PathBuf::from(candidate)
            })
            .collect();
    }
    vec![path]
}

fn executable_file(path: &Path) -> bool {
    let Ok(metadata) = std::fs::metadata(path) else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}
