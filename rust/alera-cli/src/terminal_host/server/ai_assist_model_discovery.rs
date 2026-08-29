use std::process::Stdio;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(60);
const MAX_DISCOVERY_OUTPUT_BYTES: usize = 4 * 1024 * 1024;
const OPENAI_THINKING_LEVELS: [(&str, &str); 4] = [
    ("low", "Low"),
    ("medium", "Medium"),
    ("high", "High"),
    ("xhigh", "Extra High"),
];
const CLAUDE_THINKING_LEVELS: [(&str, &str); 5] = [
    ("low", "Low"),
    ("medium", "Medium"),
    ("high", "High"),
    ("xhigh", "Extra High"),
    ("max", "Max"),
];
const BASIC_THINKING_LEVELS: [(&str, &str); 3] =
    [("low", "Low"), ("medium", "Medium"), ("high", "High")];
const GROK_THINKING_LEVELS: [(&str, &str); 7] = [
    ("default", "Grok Default"),
    ("none", "None"),
    ("minimal", "Minimal"),
    ("low", "Low"),
    ("medium", "Medium"),
    ("high", "High"),
    ("xhigh", "Extra High"),
];

struct DiscoverySpec {
    agent: String,
    label: &'static str,
    binary: Option<&'static str>,
    arguments: &'static [&'static str],
    fallback_models: Vec<Value>,
    default_model_id: &'static str,
}

impl ServerActor {
    pub(super) fn start_ai_assist_model_discovery(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let agent = required_non_blank(payload, "agent")?.to_ascii_lowercase();
        let spec = discovery_spec(&agent)
            .ok_or_else(|| HostError::format(format!("{agent} does not support AI Assist.")))?;
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = Ok(discover_models(spec).await);
            let _ = inbox.send(ServerCommand::HostToolFinished {
                client_id,
                request_id,
                result,
                operation_id: None,
                skill: None,
            });
        });
        Ok(())
    }
}

async fn discover_models(spec: DiscoverySpec) -> Value {
    let Some(binary) = spec.binary else {
        return success_payload(&spec, spec.fallback_models.clone());
    };
    let mut command = windowless_async_command(binary);
    command
        .args(spec.arguments)
        .kill_on_drop(true)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    crate::login_shell_environment::apply_login_shell_path(&mut command).await;
    let child = match command.spawn() {
        Ok(child) => child,
        Err(_) => {
            return failure_payload(
                &spec,
                format!(
                "{} model discovery could not be started. Check that {} is installed and on PATH.",
                spec.label, binary
            ),
            )
        }
    };
    let output = match tokio::time::timeout(DISCOVERY_TIMEOUT, child.wait_with_output()).await {
        Ok(Ok(output)) => output,
        Ok(Err(error)) => return failure_payload(&spec, error.to_string()),
        Err(_) => {
            return failure_payload(
                &spec,
                format!(
                    "{} model discovery timed out after {}s.",
                    spec.label,
                    DISCOVERY_TIMEOUT.as_secs()
                ),
            )
        }
    };
    if output.stdout.len() + output.stderr.len() > MAX_DISCOVERY_OUTPUT_BYTES {
        return failure_payload(
            &spec,
            format!("{} returned too much model data.", spec.label),
        );
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() {
        let detail = failure_detail(&stdout, &stderr);
        let message = detail.map_or_else(
            || {
                format!(
                    "{} model discovery failed. Check the agent CLI configuration and try again.",
                    spec.label
                )
            },
            |detail| format!("{} model discovery failed: {detail}", spec.label),
        );
        return failure_payload(&spec, message);
    }
    let mut models = parse_models(&spec.agent, &stdout);
    if models.is_empty() && !stderr.trim().is_empty() {
        models = parse_models(&spec.agent, &stderr);
    }
    if models.is_empty() {
        if !spec.fallback_models.is_empty() {
            return success_payload(&spec, spec.fallback_models.clone());
        }
        return failure_payload(
            &spec,
            format!("{} returned no available models.", spec.label),
        );
    }
    success_payload(&spec, models)
}

fn success_payload(spec: &DiscoverySpec, models: Vec<Value>) -> Value {
    let default_model_id = if models
        .iter()
        .any(|model| model.get("id").and_then(Value::as_str) == Some(spec.default_model_id))
    {
        spec.default_model_id.to_string()
    } else {
        models
            .first()
            .and_then(|model| model.get("id"))
            .and_then(Value::as_str)
            .unwrap_or(spec.default_model_id)
            .to_string()
    };
    json!({
        "success": true,
        "agent": spec.agent,
        "models": models,
        "defaultModelId": default_model_id,
    })
}

fn failure_payload(spec: &DiscoverySpec, error: String) -> Value {
    json!({
        "success": false,
        "agent": spec.agent,
        "models": spec.fallback_models,
        "defaultModelId": spec.default_model_id,
        "error": error,
    })
}

fn discovery_spec(agent: &str) -> Option<DiscoverySpec> {
    let (label, binary, arguments, fallback_models, default_model_id) = match agent {
        "claude" => (
            "Claude Code",
            None,
            &[][..],
            vec![
                model("haiku", "Haiku", &[], None),
                model("sonnet", "Sonnet", &CLAUDE_THINKING_LEVELS, Some("low")),
                model("opus", "Opus", &CLAUDE_THINKING_LEVELS, Some("low")),
            ],
            "sonnet",
        ),
        "codex" => (
            "Codex",
            Some("codex"),
            &["debug", "models"][..],
            vec![
                model("gpt-5.5", "GPT-5.5", &OPENAI_THINKING_LEVELS, Some("low")),
                model("gpt-5.4", "GPT-5.4", &OPENAI_THINKING_LEVELS, Some("low")),
                model(
                    "gpt-5.4-mini",
                    "GPT-5.4 Mini",
                    &OPENAI_THINKING_LEVELS,
                    Some("low"),
                ),
            ],
            "gpt-5.5",
        ),
        "copilot" => (
            "GitHub Copilot",
            None,
            &[][..],
            vec![
                model("auto", "Auto", &[], None),
                model("gpt-5.4", "GPT-5.4", &OPENAI_THINKING_LEVELS, Some("low")),
                model(
                    "gpt-5.4-mini",
                    "GPT-5.4 Mini",
                    &OPENAI_THINKING_LEVELS,
                    Some("low"),
                ),
            ],
            "gpt-5.4",
        ),
        "cursor" => (
            "Cursor",
            Some("cursor-agent"),
            &["--list-models"][..],
            vec![model("auto", "Auto", &[], None)],
            "auto",
        ),
        "agy" => (
            "Antigravity",
            Some("agy"),
            &["models"][..],
            vec![
                model(
                    "Gemini 3.5 Flash (Medium)",
                    "Gemini 3.5 Flash (Medium)",
                    &[],
                    None,
                ),
                model(
                    "Gemini 3.5 Flash (High)",
                    "Gemini 3.5 Flash (High)",
                    &[],
                    None,
                ),
                model(
                    "Gemini 3.5 Flash (Low)",
                    "Gemini 3.5 Flash (Low)",
                    &[],
                    None,
                ),
            ],
            "Gemini 3.5 Flash (Medium)",
        ),
        "opencode" => (
            "OpenCode",
            Some("opencode"),
            &["models"][..],
            vec![model(
                "opencode/deepseek-v4-flash-free",
                "OpenCode DeepSeek V4 Flash Free",
                &[],
                None,
            )],
            "opencode/deepseek-v4-flash-free",
        ),
        "pi" => (
            "Pi",
            Some("pi"),
            &["--list-models"][..],
            vec![model(
                "github-copilot/gpt-5.4-mini",
                "GitHub Copilot GPT-5.4 Mini",
                &OPENAI_THINKING_LEVELS,
                Some("low"),
            )],
            "github-copilot/gpt-5.4-mini",
        ),
        "amp" => (
            "Amp",
            None,
            &[][..],
            vec![
                model("smart", "Smart", &[], None),
                model("rush", "Rush", &[], None),
                model("large", "Large", &BASIC_THINKING_LEVELS, Some("low")),
                model("deep", "Deep", &BASIC_THINKING_LEVELS, Some("low")),
            ],
            "smart",
        ),
        "grok" => (
            "Grok Build",
            Some("grok"),
            &["models"][..],
            vec![model(
                "grok-4.5",
                "Grok 4.5",
                &GROK_THINKING_LEVELS,
                Some("default"),
            )],
            "grok-4.5",
        ),
        _ => return None,
    };
    Some(DiscoverySpec {
        agent: agent.to_string(),
        label,
        binary,
        arguments,
        fallback_models,
        default_model_id,
    })
}

fn parse_models(agent: &str, output: &str) -> Vec<Value> {
    match agent {
        "codex" => parse_codex_models(output),
        "cursor" => parse_cursor_models(output),
        "pi" => parse_pi_models(output),
        "grok" => parse_grok_models(output),
        _ => parse_line_models(output),
    }
}

fn parse_line_models(output: &str) -> Vec<Value> {
    unique_models(
        output
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(|id| model(id, &label_from_model_id(id), &[], None))
            .collect(),
    )
}

fn parse_cursor_models(output: &str) -> Vec<Value> {
    unique_models(
        output
            .lines()
            .filter_map(|line| line.trim().split_once(" - "))
            .map(|(id, label)| {
                let label = label
                    .trim()
                    .trim_end_matches(" (default)")
                    .trim_end_matches(" (current)");
                model(id.trim(), label, &[], None)
            })
            .collect(),
    )
}

fn parse_codex_models(output: &str) -> Vec<Value> {
    let Ok(value) = serde_json::from_str::<Value>(output) else {
        return Vec::new();
    };
    unique_models(
        value
            .get("models")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|item| {
                let id = item.get("slug").and_then(Value::as_str)?;
                let label = item.get("display_name").and_then(Value::as_str)?;
                let default = item
                    .get("default_reasoning_level")
                    .and_then(Value::as_str)
                    .unwrap_or("low");
                Some(model(id, label, &OPENAI_THINKING_LEVELS, Some(default)))
            })
            .collect(),
    )
}

fn parse_pi_models(output: &str) -> Vec<Value> {
    unique_models(
        output
            .lines()
            .filter_map(|line| {
                let parts = line.split_whitespace().collect::<Vec<_>>();
                (parts.len() >= 2 && parts[0] != "provider").then(|| {
                    let id = format!("{}/{}", parts[0], parts[1]);
                    model(&id, &label_from_model_id(&id), &[], None)
                })
            })
            .collect(),
    )
}

fn parse_grok_models(output: &str) -> Vec<Value> {
    unique_models(
        output
            .lines()
            .filter_map(|line| {
                let line = line.trim();
                let id = line
                    .strip_prefix("* ")
                    .or_else(|| line.strip_prefix("- "))?
                    .trim_end_matches(" (default)")
                    .trim();
                (!id.is_empty()).then(|| {
                    model(
                        id,
                        &label_from_model_id(id),
                        &GROK_THINKING_LEVELS,
                        Some("default"),
                    )
                })
            })
            .collect(),
    )
}

fn model(id: &str, label: &str, thinking: &[(&str, &str)], default: Option<&str>) -> Value {
    json!({
        "id": id,
        "label": label,
        "thinkingLevels": thinking
            .iter()
            .map(|(id, label)| json!({"id": id, "label": label}))
            .collect::<Vec<_>>(),
        "defaultThinkingLevel": default,
    })
}

fn unique_models(models: Vec<Value>) -> Vec<Value> {
    let mut seen = std::collections::HashSet::new();
    models
        .into_iter()
        .filter(|model| {
            model
                .get("id")
                .and_then(Value::as_str)
                .is_some_and(|id| seen.insert(id.to_string()))
        })
        .collect()
}

fn label_from_model_id(id: &str) -> String {
    id.split(['/', '-'])
        .filter(|part| !part.is_empty())
        .map(|part| {
            if part.eq_ignore_ascii_case("gpt") {
                "GPT".to_string()
            } else if part.len() <= 3
                && part
                    .chars()
                    .next()
                    .is_some_and(|character| character.is_ascii_digit())
            {
                part.to_ascii_uppercase()
            } else {
                let mut characters = part.chars();
                characters
                    .next()
                    .map(|first| first.to_uppercase().chain(characters).collect())
                    .unwrap_or_default()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn failure_detail(stdout: &str, stderr: &str) -> Option<String> {
    let detail = stdout
        .lines()
        .chain(stderr.lines())
        .rev()
        .find(|line| !line.trim().is_empty())?
        .trim();
    Some(detail.chars().take(240).collect())
}

#[cfg(test)]
#[path = "ai_assist_model_discovery_tests.rs"]
mod tests;
