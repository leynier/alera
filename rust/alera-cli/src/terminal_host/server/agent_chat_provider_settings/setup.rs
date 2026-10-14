//! Opaque human setup selection. Recipes and credentials stay on the host.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use super::{envelope, store_error, ProviderSettingsService};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::TerminalHostLaunch;

pub(crate) const SETUP_WORKSPACE_ID: &str = "__alera_command_terminal__";

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProviderSetupContext {
    pub provider_instance_id: String,
    pub action: String,
}

impl ProviderSetupContext {
    pub(crate) fn from_json(value: &Value) -> HostResult<Self> {
        let context: Self = serde_json::from_value(value.clone()).map_err(|_| {
            HostError::format("Provider setup must contain only providerInstanceId and action.")
        })?;
        if context.provider_instance_id.trim().is_empty()
            || context.provider_instance_id.len() > 4096
            || context.provider_instance_id.contains('\0')
            || !matches!(context.action.as_str(), "signIn" | "install" | "update")
        {
            return Err(HostError::format(
                "Provider setup instance or action is invalid.",
            ));
        }
        Ok(context)
    }
}

#[derive(Clone)]
pub(super) struct SetupRecipe {
    pub action: &'static str,
    pub label: &'static str,
    pub executable: PathBuf,
    pub arguments: Vec<String>,
}

pub(super) fn verified_recipes(provider: &str, executable: &Path) -> Vec<SetupRecipe> {
    let mut recipes = Vec::new();
    let mut add = |action, label, binary: PathBuf, args: &[&str]| {
        recipes.push(SetupRecipe {
            action,
            label,
            executable: binary,
            arguments: args.iter().map(|value| (*value).to_owned()).collect(),
        })
    };
    let normalized = executable.to_string_lossy().replace('\\', "/");
    match provider {
        "codex" => {
            add("signIn", "Sign In", executable.into(), &["login"]);
            if executable == Path::new("codex") {
                add(
                    "install",
                    "Install",
                    "npm".into(),
                    &["install", "-g", "@openai/codex@latest"],
                );
            }
            if normalized.contains("/packages/standalone/") {
                add("update", "Update", executable.into(), &["update"]);
            }
        }
        "claudeAgent" => {
            add("signIn", "Sign In", executable.into(), &["auth", "login"]);
            if executable == Path::new("claude") {
                add(
                    "install",
                    "Install",
                    "npm".into(),
                    &["install", "-g", "@anthropic-ai/claude-code@latest"],
                );
            }
            if normalized.contains("/.local/share/claude/")
                || normalized.ends_with("/.local/bin/claude")
                || normalized.ends_with("/.local/bin/claude.exe")
            {
                add("update", "Update", executable.into(), &["update"]);
            }
        }
        "pi" => {
            if executable == Path::new("pi") {
                add(
                    "install",
                    "Install",
                    "npm".into(),
                    &[
                        "install",
                        "-g",
                        "--ignore-scripts",
                        "@earendil-works/pi-coding-agent",
                    ],
                );
            }
            add("update", "Update", executable.into(), &["update", "--self"]);
        }
        _ => {}
    }
    recipes
}

pub(super) fn default_executable(provider: &str) -> Option<PathBuf> {
    match provider {
        "codex" => Some("codex".into()),
        "claudeAgent" => Some("claude".into()),
        "pi" => Some("pi".into()),
        _ => None,
    }
}

impl ProviderSettingsService {
    pub(crate) async fn validate_provider_setup(
        &self,
        context: &ProviderSetupContext,
    ) -> HostResult<()> {
        self.setup_instance(context).await.map(|_| ())
    }

    async fn setup_instance(
        &self,
        context: &ProviderSetupContext,
    ) -> HostResult<(
        super::super::agent_chat_runtime::provider_factory::ProviderInstanceConfig,
        SetupRecipe,
    )> {
        ProviderSetupContext::from_json(&json!(context))?;
        if self
            .migration_error
            .read()
            .is_ok_and(|error| error.is_some())
        {
            return Err(setup_error(
                "providerMigrationRequired",
                "Provider settings migration must be repaired before setup.",
            ));
        }
        let records = self
            .store
            .agent_chat_provider_instances()
            .await
            .map_err(store_error)?;
        let record = records
            .instances
            .into_iter()
            .find(|record| record.provider_instance_id == context.provider_instance_id);
        let mut config = match record {
            Some(record) => envelope::config(&record.envelope, record.secret_refs),
            None => envelope::config(
                &envelope::default_envelope(&context.provider_instance_id).ok_or_else(|| {
                    setup_error(
                        "providerMissing",
                        "The selected agent instance no longer exists.",
                    )
                })?,
                BTreeMap::new(),
            ),
        };
        if !config.enabled {
            return Err(setup_error(
                "providerUnavailable",
                "The selected agent instance is turned off.",
            ));
        }
        if config.args.as_ref().is_some_and(|args| !args.is_empty())
            || !config.options.is_empty()
            || config
                .secret_refs
                .keys()
                .any(|name| name.starts_with("option:"))
        {
            return Err(setup_error(
                "unsupported",
                "Setup cannot honor custom launch arguments or options for this instance.",
            ));
        }
        let executable = config
            .executable
            .clone()
            .or_else(|| default_executable(&config.provider))
            .ok_or_else(|| {
                setup_error("unsupported", "This agent has no verified setup recipe.")
            })?;
        let recipe = verified_recipes(&config.provider, &executable)
            .into_iter()
            .find(|recipe| recipe.action == context.action)
            .ok_or_else(|| {
                setup_error(
                    "unsupported",
                    "This agent does not support the requested setup action.",
                )
            })?;
        config.credential_scope = Some((self.runtime_dir.clone(), self.runtime_id.clone()));
        Ok((config, recipe))
    }

    /// Called after terminal hook preparation and immediately before PTY spawn.
    pub(crate) async fn prepare_provider_setup_launch(
        &self,
        launch: &mut TerminalHostLaunch,
    ) -> HostResult<()> {
        let environment =
            alera_core::login_shell_environment::login_shell_variables_with_process_overrides()
                .await;
        self.prepare_provider_setup_with_environment(launch, environment)
            .await
    }

    async fn prepare_provider_setup_with_environment(
        &self,
        launch: &mut TerminalHostLaunch,
        mut environment: BTreeMap<String, String>,
    ) -> HostResult<()> {
        let context = launch
            .provider_setup
            .as_ref()
            .ok_or_else(|| HostError::format("Provider setup context is required."))?;
        let (config, recipe) = self.setup_instance(context).await?;
        environment.extend(std::mem::take(&mut launch.environment));
        // The selected profile wins over the desktop's inherited defaults.
        environment.extend(config.env.clone());
        for (name, reference) in &config.secret_refs {
            let value = self.secrets.load(reference).await?.ok_or_else(|| {
                setup_error(
                    "providerCredentialMissing",
                    "A saved provider credential is missing. Replace it in Providers Settings.",
                )
            })?;
            environment.insert(name.clone(), value);
        }
        launch.label = recipe.label.into();
        launch.shell = recipe.executable.to_string_lossy().into_owned();
        launch.arguments = recipe.arguments;
        if cfg!(windows)
            && (launch.shell == "npm"
                || launch.shell.to_ascii_lowercase().ends_with(".cmd")
                || launch.shell.to_ascii_lowercase().ends_with(".bat"))
        {
            if launch.shell.contains(['"', '\n', '\r', '%']) {
                return Err(HostError::format("Provider setup executable is invalid."));
            }
            let command = std::iter::once(&launch.shell)
                .chain(launch.arguments.iter())
                .map(|argument| format!("\"{}\"", argument.replace('"', "\"\"")))
                .collect::<Vec<_>>()
                .join(" ");
            launch.shell = "cmd.exe".into();
            launch.arguments = vec![
                "/d".into(),
                "/s".into(),
                "/c".into(),
                format!("\"{command}\""),
            ];
        }
        launch.environment = environment;
        Ok(())
    }
}

fn setup_error(code: &str, message: &str) -> HostError {
    HostError::conflict(code, message, json!({}))
}

#[cfg(test)]
#[path = "setup_tests.rs"]
mod tests;
