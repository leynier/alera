use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::RuntimeAiTextGenerationSettings;
use serde_json::{json, Value};
use tokio::io::AsyncWriteExt;
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::ai_text_grok_plan::plan_grok_command;
use super::ai_text_workspace_identity::{parse_workspace_identity, workspace_identity_prompt};
use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

const MAX_ARGV_PROMPT_BYTES: usize = 24_000;
const MAX_OUTPUT_BYTES: usize = 1024 * 1024;
const SUPPORTED_AGENTS: [&str; 10] = [
    "codex", "claude", "copilot", "cursor", "agy", "opencode", "pi", "amp", "grok", "custom",
];

static ACTIVE_GENERATIONS: OnceLock<Mutex<HashMap<String, oneshot::Sender<()>>>> = OnceLock::new();

pub(super) struct AiTextCommandPlan {
    pub(super) binary: String,
    pub(super) arguments: Vec<String>,
    pub(super) stdin_payload: Option<String>,
    pub(super) label: String,
    pub(super) environment: HashMap<String, String>,
    pub(super) temporary_directory: Option<PathBuf>,
}

impl ServerActor {
    pub(super) fn start_ai_text_workspace_identity(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let project_id = required_non_blank(payload, "projectId")?;
        let initial_prompt = required_non_blank(payload, "prompt")?;
        let project = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let (cancel_tx, cancel_rx) = oneshot::channel();
        let mut active = active_generations()
            .lock()
            .map_err(|_| HostError::state("AI text generation state is unavailable."))?;
        if active.contains_key(&operation_id) {
            return Err(HostError::state(
                "AI text generation is already running for this operation.",
            ));
        }
        active.insert(operation_id.clone(), cancel_tx);
        drop(active);
        tokio::spawn(async move {
            let result = async {
                let project_record = project
                    .find_project(&project_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| HostError::state(format!("Project not found: {project_id}")))?;
                let settings = project
                    .effective_ai_text_generation_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                generate_workspace_identity(
                    &project_record.repo_path,
                    &initial_prompt,
                    settings,
                    cancel_rx,
                )
                .await
            }
            .await;
            if let Ok(mut active) = active_generations().lock() {
                active.remove(&operation_id);
            }
            let _ = inbox.send(ServerCommand::AiTextGenerationFinished {
                client_id,
                request_id,
                result,
            });
        });
        Ok(())
    }

    pub(super) fn cancel_ai_text_generation(&mut self, payload: &Value) -> HostResult<Value> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let canceled = active_generations()
            .lock()
            .map_err(|_| HostError::state("AI text generation state is unavailable."))?
            .remove(&operation_id)
            .is_some_and(|sender| sender.send(()).is_ok());
        Ok(json!({"canceled": canceled}))
    }

    pub(super) fn handle_ai_text_generation_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        match result {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
    }
}

pub(super) fn active_generations() -> &'static Mutex<HashMap<String, oneshot::Sender<()>>> {
    ACTIVE_GENERATIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

async fn generate_workspace_identity(
    working_directory: &str,
    initial_prompt: &str,
    settings: RuntimeAiTextGenerationSettings,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<Value> {
    if !settings.enabled {
        return Err(HostError::state("AI text generation is disabled."));
    }
    if !SUPPORTED_AGENTS.contains(&settings.agent.as_str()) {
        return Err(HostError::format(
            "The configured AI text agent is unsupported.",
        ));
    }
    let prompt = workspace_identity_prompt(
        initial_prompt,
        settings
            .instructions_by_operation
            .get("workspaceIdentity")
            .map(String::as_str)
            .unwrap_or_default(),
    );
    let plan = plan_command(&settings, "workspaceIdentity", &prompt)?;
    let timeout_seconds = settings.timeout_seconds;
    let result = run_command(plan, working_directory, timeout_seconds, cancel_rx).await?;
    parse_workspace_identity(&result)
}

pub(super) fn plan_command(
    settings: &RuntimeAiTextGenerationSettings,
    operation: &str,
    prompt: &str,
) -> HostResult<AiTextCommandPlan> {
    let prompt_settings = settings.prompt_settings_by_operation.get(operation);
    let agent = prompt_settings
        .and_then(|value| value.agent.as_deref())
        .unwrap_or(&settings.agent);
    if agent == "custom" {
        return plan_custom_command(&settings.custom_command, prompt);
    }
    let selected_model = prompt_settings
        .and_then(|value| value.model.as_deref())
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            settings
                .selected_model_by_agent
                .get(agent)
                .map(String::as_str)
                .filter(|value| !value.trim().is_empty())
        });
    let model = selected_model.unwrap_or_else(|| default_model(agent));
    let thinking = settings
        .selected_thinking_by_operation
        .get(operation)
        .and_then(|values| values.get(model))
        .or_else(|| settings.selected_thinking_by_model.get(model))
        .map(String::as_str)
        .filter(|value| !value.trim().is_empty());
    let timeout = settings.timeout_seconds;
    let (binary, arguments, stdin_payload, label) = match agent {
        "claude" => (
            "claude",
            vec![
                "-p",
                "--output-format",
                "text",
                "--model",
                model,
                "--permission-mode",
                "plan",
            ]
            .into_iter()
            .map(str::to_string)
            .chain(
                thinking
                    .map(|value| vec!["--effort".to_string(), value.to_string()])
                    .unwrap_or_default(),
            )
            .collect(),
            Some(prompt.to_string()),
            "Claude Code",
        ),
        "codex" => (
            "codex",
            vec![
                "exec".to_string(),
                "--ephemeral".to_string(),
                "--skip-git-repo-check".to_string(),
                "-s".to_string(),
                "read-only".to_string(),
                "--model".to_string(),
                model.to_string(),
            ]
            .into_iter()
            .chain(
                thinking
                    .map(|value| vec!["-c".to_string(), format!("model_reasoning_effort={value}")])
                    .unwrap_or_default(),
            )
            .collect(),
            Some(prompt.to_string()),
            "Codex",
        ),
        "copilot" => (
            "copilot",
            vec![
                "--prompt",
                prompt,
                "--silent",
                "--stream",
                "off",
                "--no-custom-instructions",
                "--model",
                model,
            ]
            .into_iter()
            .map(str::to_string)
            .chain(
                thinking
                    .map(|value| vec!["--effort".to_string(), value.to_string()])
                    .unwrap_or_default(),
            )
            .collect(),
            None,
            "GitHub Copilot",
        ),
        "cursor" => (
            "cursor-agent",
            vec![
                "--print",
                "--mode",
                "ask",
                "--trust",
                "--output-format",
                "text",
                "--model",
                model,
                prompt,
            ]
            .into_iter()
            .map(str::to_string)
            .collect(),
            None,
            "Cursor",
        ),
        "agy" => {
            let mut arguments = vec![
                "--print".to_string(),
                "--sandbox".to_string(),
                "--print-timeout".to_string(),
                format!("{timeout}s"),
            ];
            if selected_model.is_some() {
                arguments.extend(["--model".to_string(), model.to_string()]);
            }
            ("agy", arguments, Some(prompt.to_string()), "Antigravity")
        }
        "opencode" => (
            "opencode",
            vec![
                "run".to_string(),
                "--model".to_string(),
                model.to_string(),
                "--agent".to_string(),
                "build".to_string(),
                "--format".to_string(),
                "default".to_string(),
            ]
            .into_iter()
            .chain(
                thinking
                    .map(|value| vec!["--variant".to_string(), value.to_string()])
                    .unwrap_or_default(),
            )
            .collect(),
            Some(prompt.to_string()),
            "OpenCode",
        ),
        "pi" => (
            "pi",
            vec![
                "--print",
                "--no-session",
                "--no-tools",
                "--no-extensions",
                "--no-skills",
                "--no-context-files",
                "--mode",
                "text",
                "--model",
                model,
            ]
            .into_iter()
            .map(str::to_string)
            .chain(
                thinking
                    .map(|value| vec!["--thinking".to_string(), value.to_string()])
                    .unwrap_or_default(),
            )
            .collect(),
            Some(prompt.to_string()),
            "Pi",
        ),
        "amp" => (
            "amp",
            vec![
                "--execute",
                "--no-notifications",
                "--no-ide",
                "--no-jetbrains",
                "--mode",
                model,
            ]
            .into_iter()
            .map(str::to_string)
            .chain(
                thinking
                    .map(|value| vec!["--effort".to_string(), value.to_string()])
                    .unwrap_or_default(),
            )
            .collect(),
            Some(prompt.to_string()),
            "Amp",
        ),
        "grok" => return plan_grok_command(model, thinking, prompt),
        _ => {
            return Err(HostError::format(
                "The configured AI text agent is unsupported.",
            ))
        }
    };
    if stdin_payload.is_none() && prompt.len() > MAX_ARGV_PROMPT_BYTES {
        return Err(HostError::format(
            "The selected AI text agent cannot receive this prompt safely. Choose an agent that supports stdin.",
        ));
    }
    Ok(AiTextCommandPlan {
        binary: binary.to_string(),
        arguments,
        stdin_payload,
        label: label.to_string(),
        environment: HashMap::new(),
        temporary_directory: None,
    })
}

fn plan_custom_command(template: &str, prompt: &str) -> HostResult<AiTextCommandPlan> {
    let tokens = tokenize_command(template);
    if tokens.is_empty() {
        return Err(HostError::format("The custom AI text command is empty."));
    }
    let uses_placeholder = tokens.iter().any(|token| token.contains("{prompt}"));
    let values: Vec<String> = tokens
        .into_iter()
        .map(|token| token.replace("{prompt}", prompt))
        .collect();
    Ok(AiTextCommandPlan {
        binary: values[0].clone(),
        arguments: values[1..].to_vec(),
        stdin_payload: (!uses_placeholder).then(|| prompt.to_string()),
        label: values[0].clone(),
        environment: HashMap::new(),
        temporary_directory: None,
    })
}

fn tokenize_command(template: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut quote = None;
    for character in template.chars() {
        match (quote, character) {
            (Some(active), value) if value == active => quote = None,
            (None, '"' | '\'') => quote = Some(character),
            (None, value) if value.is_whitespace() => {
                if !current.is_empty() {
                    tokens.push(std::mem::take(&mut current));
                }
            }
            _ => current.push(character),
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    tokens
}

pub(super) async fn run_command(
    plan: AiTextCommandPlan,
    working_directory: &str,
    timeout_seconds: u64,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<String> {
    let mut command = windowless_async_command(&plan.binary);
    command
        .args(&plan.arguments)
        .current_dir(working_directory)
        .kill_on_drop(true)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .stdin(if plan.stdin_payload.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
    if let Some(path) = crate::login_shell_environment::login_shell_merged_path(
        std::env::var("PATH").ok().as_deref(),
    )
    .await
    {
        command.env("PATH", path);
    }
    command.envs(&plan.environment);
    let mut child = command.spawn().map_err(|_| {
        HostError::state(format!(
            "{} could not be started. Check that {} is installed and on PATH.",
            plan.label, plan.binary
        ))
    })?;
    if let Some(payload) = plan.stdin_payload {
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| HostError::state("AI text process stdin is unavailable."))?;
        stdin
            .write_all(payload.as_bytes())
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
    }
    let output_future = child.wait_with_output();
    tokio::pin!(output_future);
    let result = tokio::select! {
        _ = cancel_rx => Err(HostError::state("AI text generation was canceled.")),
        _ = tokio::time::sleep(Duration::from_secs(timeout_seconds)) => {
            Err(HostError::state(format!("AI text generation timed out after {timeout_seconds}s.")))
        }
        output = &mut output_future => {
            let output = output.map_err(|error| HostError::state(error.to_string()))?;
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                let detail = stderr.lines().find(|line| !line.trim().is_empty()).unwrap_or_default();
                Err(HostError::state(if detail.is_empty() {
                    format!("{} failed. Check the agent CLI configuration and try again.", plan.label)
                } else {
                    format!("{} failed: {}", plan.label, detail.trim())
                }))
            } else if output.stdout.len() > MAX_OUTPUT_BYTES {
                Err(HostError::state(format!("{} returned too much output.", plan.label)))
            } else {
                Ok(stdout)
            }
        }
    };
    if let Some(directory) = plan.temporary_directory {
        let _ = std::fs::remove_dir_all(directory);
    }
    result
}

fn default_model(agent: &str) -> &'static str {
    match agent {
        "claude" => "sonnet",
        "codex" => "gpt-5.5",
        "copilot" => "gpt-5.4",
        "cursor" => "auto",
        // An empty model lets AGY use its own configured/default model.
        "agy" => "",
        "opencode" => "opencode/deepseek-v4-flash-free",
        "pi" => "github-copilot/gpt-5.4-mini",
        "amp" => "smart",
        "grok" => "grok-4.5",
        _ => "custom",
    }
}

#[cfg(test)]
#[path = "ai_text_requests_tests.rs"]
mod tests;
