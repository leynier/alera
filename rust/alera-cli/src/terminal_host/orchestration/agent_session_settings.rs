//! The model, effort and permission mode a native agent conversation was last
//! running with, so a resumed conversation continues where the user left it.
//!
//! Settings use the Agent Profile `managedConfig` key names, which lets the
//! profile flag builders render them. Each agent restores a different subset
//! by itself on resume; for those the launch drops the profile's own flag so a
//! stale value cannot override what the conversation remembers.

use serde_json::{json, Map, Value};

use super::agent_registry::canonical_agent_type;
use super::managed_agent_launch::build_managed_agent_launch;

pub const AGENT_NATIVE_SESSION_SETTINGS_KEY: &str = "agentNativeSessionSettings";

struct ResumePolicy {
    /// Settings the host reapplies on resume, as managed config keys.
    applied: &'static [&'static str],
    /// Flags removed from a resumed launch: the agent restores them from the
    /// conversation (and a launch flag would win), or rejects a change.
    dropped: &'static [&'static str],
}

fn resume_policy(agent_type: &str) -> ResumePolicy {
    match canonical_agent_type(agent_type) {
        // Claude restores the model and plan mode from the transcript unless
        // `--model` is passed; other permission modes and effort are not.
        "claude" => ResumePolicy {
            applied: &["permissionMode", "effort"],
            dropped: &["--model"],
        },
        // `codex resume` keeps whatever the config and flags say.
        "codex" => ResumePolicy {
            applied: &["model", "effort", "sandbox", "approvalPolicy"],
            dropped: &[],
        },
        // Cursor and pi reopen with the conversation's last model.
        "cursor" => ResumePolicy {
            applied: &[],
            dropped: &["--model"],
        },
        "pi" => ResumePolicy {
            applied: &[],
            dropped: &["--model", "--thinking"],
        },
        // Grok refuses to resume with a different `--sandbox`.
        "grok" => ResumePolicy {
            applied: &["model", "effort", "permissionMode"],
            dropped: &["--sandbox"],
        },
        "copilot" => ResumePolicy {
            applied: &["model", "effort", "mode"],
            dropped: &[],
        },
        "agy" => ResumePolicy {
            applied: &["model"],
            dropped: &[],
        },
        _ => ResumePolicy {
            applied: &[],
            dropped: &[],
        },
    }
}

/// Settings a hook payload reports directly.
pub fn settings_from_hook(agent_type: &str, payload: &Value) -> Map<String, Value> {
    let mut settings = Map::new();
    let text = |key: &str| {
        payload
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
    };
    match canonical_agent_type(agent_type) {
        "claude" => {
            put(&mut settings, "model", text("model"));
            put(
                &mut settings,
                "permissionMode",
                text("permission_mode").map(|mode| match mode {
                    // Hooks and transcripts call the ask-every-time mode
                    // `default`; the CLI flag calls it `manual`.
                    "default" => "manual",
                    other => other,
                }),
            );
            let effort = payload
                .get("effort")
                .and_then(|effort| effort.get("level").or(Some(effort)))
                .and_then(Value::as_str);
            put(&mut settings, "effort", effort);
        }
        "codex" | "cursor" => put(&mut settings, "model", text("model")),
        "grok" => put(
            &mut settings,
            "permissionMode",
            text("permission_mode").or_else(|| text("permissionMode")),
        ),
        "agy" => put(
            &mut settings,
            "model",
            text("model_name").or_else(|| text("modelName")),
        ),
        _ => {}
    }
    settings
}

/// Settings from the last `turn_context` line of a Codex rollout file.
pub fn codex_settings_from_rollout_tail(tail: &str) -> Map<String, Value> {
    let mut settings = Map::new();
    let Some(context) = tail.lines().rev().find_map(|line| {
        let value: Value = serde_json::from_str(line).ok()?;
        (value.get("type")? == "turn_context").then(|| value.get("payload").cloned())?
    }) else {
        return settings;
    };
    fn text(value: Option<&Value>) -> Option<&str> {
        value.and_then(Value::as_str).filter(|v| !v.is_empty())
    }
    put(&mut settings, "model", text(context.get("model")));
    put(&mut settings, "effort", text(context.get("effort")));
    put(
        &mut settings,
        "approvalPolicy",
        text(context.get("approval_policy")),
    );
    put(
        &mut settings,
        "sandbox",
        text(context.pointer("/sandbox_policy/type")),
    );
    settings
}

/// Settings from a Grok session's `summary.json`.
pub fn grok_settings_from_summary(summary: &Value) -> Map<String, Value> {
    let mut settings = Map::new();
    let text = |key: &str| {
        summary
            .get(key)
            .and_then(Value::as_str)
            .filter(|v| !v.is_empty())
    };
    put(&mut settings, "model", text("current_model_id"));
    put(&mut settings, "effort", text("reasoning_effort"));
    settings
}

/// Settings from the tail of a Copilot session's `events.jsonl`.
pub fn copilot_settings_from_events_tail(tail: &str) -> Map<String, Value> {
    let mut settings = Map::new();
    for line in tail.lines() {
        let Ok(event) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let data = event.get("data");
        let text = |key: &str| {
            data.and_then(|data| data.get(key))
                .and_then(Value::as_str)
                .filter(|v| !v.is_empty())
        };
        match event.get("type").and_then(Value::as_str) {
            Some("session.model_change") => {
                put(&mut settings, "model", text("newModel"));
                put(&mut settings, "effort", text("reasoningEffort"));
            }
            Some("session.mode_changed") => put(&mut settings, "mode", text("newMode")),
            _ => {}
        }
    }
    settings
}

fn put(settings: &mut Map<String, Value>, key: &str, value: Option<&str>) {
    if let Some(value) = value {
        settings.insert(key.to_string(), json!(value));
    }
}

/// Rewrites a resumed launch's arguments: drops what the agent restores by
/// itself, then replaces each reapplied setting's flag with the value the
/// conversation last reported. A value the flag builder rejects is skipped.
pub fn apply_session_settings(
    agent_type: &str,
    arguments: &mut Vec<String>,
    settings: Option<&Map<String, Value>>,
) {
    let policy = resume_policy(agent_type);
    for flag in policy.dropped {
        remove_flag(arguments, flag, true);
    }
    let Some(settings) = settings else {
        return;
    };
    let mut appended = Vec::new();
    for key in policy.applied {
        let Some(tokens) = setting_tokens(agent_type, key, settings) else {
            continue;
        };
        for flag in replaced_flags(agent_type, key, &tokens) {
            match flag {
                Replaced::Flag(flag, takes_value) => remove_flag(arguments, flag, takes_value),
                Replaced::CodexConfig(name) => remove_codex_config(arguments, name),
            }
        }
        appended.extend(tokens);
    }
    let insert_at = arguments
        .iter()
        .position(|argument| argument == "--")
        .unwrap_or(arguments.len());
    arguments.splice(insert_at..insert_at, appended);
}

/// Tokens to append to an opaque command line. A line that already names a
/// flag keeps the user's own value, since the host never rewrites their text.
pub fn session_settings_for_command(
    agent_type: &str,
    command: &str,
    settings: Option<&Map<String, Value>>,
) -> Vec<String> {
    let Some(settings) = settings else {
        return Vec::new();
    };
    let words = command.split_whitespace().collect::<Vec<_>>();
    let names = |flag: &str| {
        words
            .iter()
            .any(|word| *word == flag || word.starts_with(&format!("{flag}=")))
    };
    let mut appended = Vec::new();
    for key in resume_policy(agent_type).applied {
        let Some(tokens) = setting_tokens(agent_type, key, settings) else {
            continue;
        };
        let conflicts =
            replaced_flags(agent_type, key, &tokens)
                .into_iter()
                .any(|flag| match flag {
                    Replaced::Flag(flag, _) => names(flag),
                    Replaced::CodexConfig(name) => command.contains(&format!("{name}=")),
                });
        if !conflicts {
            appended.extend(tokens);
        }
    }
    appended
}

fn setting_tokens(
    agent_type: &str,
    key: &str,
    settings: &Map<String, Value>,
) -> Option<Vec<String>> {
    let value = settings.get(key)?;
    let config = Value::Object(Map::from_iter([(key.to_string(), value.clone())]));
    let tokens = build_managed_agent_launch(agent_type, &config)
        .ok()?
        .arguments;
    (!tokens.is_empty()).then_some(tokens)
}

enum Replaced {
    Flag(&'static str, bool),
    CodexConfig(&'static str),
}

/// Every spelling of the option a setting renders, plus options that would
/// contradict it.
fn replaced_flags(agent_type: &str, key: &str, tokens: &[String]) -> Vec<Replaced> {
    use Replaced::{CodexConfig, Flag};
    match (canonical_agent_type(agent_type), key) {
        ("codex", "model") => vec![Flag("--model", true), Flag("-m", true)],
        ("codex", "effort") => vec![CodexConfig("model_reasoning_effort")],
        ("codex", "sandbox") => vec![
            Flag("--sandbox", true),
            Flag("-s", true),
            Flag("--dangerously-bypass-approvals-and-sandbox", false),
            Flag("--yolo", false),
            Flag("--full-auto", false),
        ],
        ("codex", "approvalPolicy") => vec![
            Flag("--ask-for-approval", true),
            Flag("-a", true),
            Flag("--dangerously-bypass-approvals-and-sandbox", false),
            Flag("--yolo", false),
            Flag("--full-auto", false),
        ],
        ("claude", "permissionMode") => vec![
            Flag("--permission-mode", true),
            Flag("--dangerously-skip-permissions", false),
        ],
        ("grok", "model") => vec![Flag("--model", true), Flag("-m", true)],
        ("grok", "effort") => vec![Flag("--effort", true), Flag("--reasoning-effort", true)],
        ("grok", "permissionMode") => vec![
            Flag("--permission-mode", true),
            Flag("--always-approve", false),
        ],
        ("copilot", "effort") => vec![Flag("--effort", true), Flag("--reasoning-effort", true)],
        ("copilot", "mode") => vec![
            Flag("--mode", true),
            Flag("--plan", false),
            Flag("--autopilot", false),
        ],
        _ => tokens
            .first()
            .map(|flag| {
                let flag: &'static str = match flag.as_str() {
                    "--model" => "--model",
                    "--effort" => "--effort",
                    _ => return vec![],
                };
                vec![Flag(flag, tokens.len() > 1)]
            })
            .unwrap_or_default(),
    }
}

fn remove_flag(arguments: &mut Vec<String>, flag: &str, takes_value: bool) {
    let prefix = format!("{flag}=");
    let mut index = 0;
    while index < arguments.len() {
        if arguments[index] == "--" {
            return;
        }
        if arguments[index] == flag {
            let end = if takes_value {
                (index + 2).min(arguments.len())
            } else {
                index + 1
            };
            arguments.drain(index..end);
        } else if arguments[index].starts_with(&prefix) {
            arguments.remove(index);
        } else {
            index += 1;
        }
    }
}

fn remove_codex_config(arguments: &mut Vec<String>, name: &str) {
    let prefix = format!("{name}=");
    let mut index = 0;
    while index + 1 < arguments.len() {
        if arguments[index] == "--" {
            return;
        }
        if matches!(arguments[index].as_str(), "--config" | "-c")
            && arguments[index + 1].starts_with(&prefix)
        {
            arguments.drain(index..index + 2);
        } else {
            index += 1;
        }
    }
}

#[cfg(test)]
#[path = "agent_session_settings_tests.rs"]
mod tests;
