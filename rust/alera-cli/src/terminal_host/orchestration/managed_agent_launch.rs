use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use super::agent_registry::adapter_for;

#[path = "managed_agent_launch_args.rs"]
mod managed_agent_launch_args;
use managed_agent_launch_args::{
    bool_value, enum_value, push_enum, push_flag, push_non_negative_integer, push_positive_number,
    push_string, require_known_keys, string_value,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ManagedAgentLaunch {
    pub executable: String,
    pub arguments: Vec<String>,
}

/// The profile switcher Claude Code profiles may launch through. It takes the
/// profile as its first positional argument and forwards everything after it to
/// `claude` unchanged, which is why only the executable and that one argument
/// change.
const CCS_EXECUTABLE: &str = "ccs";

/// One reasoning-effort enum serves both of Codex's effort settings.
const CODEX_EFFORTS: &[&str] = &["minimal", "low", "medium", "high", "xhigh", "max", "ultra"];

pub fn build_managed_agent_launch(
    agent_type: &str,
    config: &Value,
) -> Result<ManagedAgentLaunch, String> {
    let adapter =
        adapter_for(agent_type).ok_or_else(|| format!("unsupported agent type: {agent_type}"))?;
    let values = config
        .as_object()
        .ok_or_else(|| "managedConfig must be an object.".to_string())?;
    let mut executable = adapter.default_command.to_string();
    let mut arguments = Vec::new();
    match agent_type {
        "codex" => build_codex(values, &mut arguments)?,
        "claude" => {
            if let Some(launcher) = build_claude(values, &mut arguments)? {
                executable = launcher;
            }
        }
        "copilot" => build_copilot(values, &mut arguments)?,
        "cursor" => build_cursor(values, &mut arguments)?,
        "agy" => build_agy(values, &mut arguments)?,
        "opencode" => build_opencode(values, &mut arguments)?,
        "opencode2" => build_opencode2(values, &mut arguments)?,
        "pi" => build_pi(values, &mut arguments)?,
        "amp" => build_amp(values, &mut arguments)?,
        "grok" => build_grok(values, &mut arguments)?,
        _ => return Err(format!("unsupported managed agent type: {agent_type}")),
    }
    Ok(ManagedAgentLaunch {
        executable,
        arguments,
    })
}

fn build_codex(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(
        values,
        &[
            "model",
            "effort",
            "planModeEffort",
            "sandbox",
            "approvalPolicy",
            "webSearch",
            "bypassApprovalsAndSandbox",
        ],
    )?;
    push_string(values, "model", "--model", arguments)?;
    if let Some(effort) = enum_value(values, "effort", CODEX_EFFORTS)? {
        arguments.extend([
            "--config".to_string(),
            format!("model_reasoning_effort={effort}"),
        ]);
    }
    // Codex has no launch-time way to enter plan mode, so this only sets how
    // hard it thinks once the user is in it.
    if let Some(effort) = enum_value(values, "planModeEffort", CODEX_EFFORTS)? {
        arguments.extend([
            "--config".to_string(),
            format!("plan_mode_reasoning_effort={effort}"),
        ]);
    }
    let bypass = bool_value(values, "bypassApprovalsAndSandbox")?;
    if bypass == Some(true) {
        if values.contains_key("sandbox") || values.contains_key("approvalPolicy") {
            return Err(
                "Codex bypassApprovalsAndSandbox conflicts with sandbox and approvalPolicy."
                    .to_string(),
            );
        }
        arguments.push("--dangerously-bypass-approvals-and-sandbox".to_string());
    } else {
        push_enum(
            values,
            "sandbox",
            "--sandbox",
            &["read-only", "workspace-write", "danger-full-access"],
            arguments,
        )?;
        push_enum(
            values,
            "approvalPolicy",
            "--ask-for-approval",
            &["untrusted", "on-request", "never"],
            arguments,
        )?;
    }
    push_flag(values, "webSearch", "--search", arguments)?;
    Ok(())
}

/// Returns the executable to launch instead of `claude`, if the profile routes
/// through a CCS profile.
fn build_claude(
    values: &Map<String, Value>,
    arguments: &mut Vec<String>,
) -> Result<Option<String>, String> {
    require_known_keys(
        values,
        &[
            "model",
            "effort",
            "agent",
            "permissionMode",
            "allowSkipPermissions",
            "ccsProfile",
        ],
    )?;
    let launcher = match string_value(values, "ccsProfile")? {
        None => None,
        Some(profile) => {
            // The profile is the first positional argument, so a dash-prefixed
            // value would be read as an option of the switcher itself.
            if profile.starts_with('-') {
                return Err("ccsProfile must not start with a dash.".to_string());
            }
            if profile.split_whitespace().count() > 1 {
                return Err("ccsProfile must be a single profile name.".to_string());
            }
            arguments.push(profile.to_string());
            Some(CCS_EXECUTABLE.to_string())
        }
    };
    push_string(values, "model", "--model", arguments)?;
    push_enum(
        values,
        "effort",
        "--effort",
        &["low", "medium", "high", "xhigh", "max"],
        arguments,
    )?;
    push_string(values, "agent", "--agent", arguments)?;
    push_enum(
        values,
        "permissionMode",
        "--permission-mode",
        &[
            "acceptEdits",
            "auto",
            "bypassPermissions",
            "manual",
            "dontAsk",
            "plan",
        ],
        arguments,
    )?;
    // Only makes bypass reachable in the session; `permissionMode` is what
    // decides whether it starts there.
    push_flag(
        values,
        "allowSkipPermissions",
        "--allow-dangerously-skip-permissions",
        arguments,
    )?;
    Ok(launcher)
}

fn build_copilot(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(
        values,
        &[
            "model",
            "effort",
            "agent",
            "mode",
            "context",
            "allowAll",
            "maxAiCredits",
            "maxAutopilotContinues",
            "noAskUser",
        ],
    )?;
    push_string(values, "model", "--model", arguments)?;
    push_enum(
        values,
        "effort",
        "--effort",
        &["none", "minimal", "low", "medium", "high", "xhigh", "max"],
        arguments,
    )?;
    push_string(values, "agent", "--agent", arguments)?;
    push_enum(
        values,
        "mode",
        "--mode",
        &["interactive", "plan", "autopilot"],
        arguments,
    )?;
    push_enum(
        values,
        "context",
        "--context",
        &["default", "long_context"],
        arguments,
    )?;
    push_flag(values, "allowAll", "--allow-all", arguments)?;
    push_positive_number(values, "maxAiCredits", "--max-ai-credits", arguments)?;
    push_non_negative_integer(
        values,
        "maxAutopilotContinues",
        "--max-autopilot-continues",
        arguments,
    )?;
    push_flag(values, "noAskUser", "--no-ask-user", arguments)
}

fn build_cursor(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(
        values,
        &[
            "model",
            "mode",
            "permissionMode",
            "sandbox",
            "trustWorkspace",
        ],
    )?;
    push_string(values, "model", "--model", arguments)?;
    push_enum(values, "mode", "--mode", &["plan", "ask"], arguments)?;
    if let Some(mode) = enum_value(values, "permissionMode", &["autoReview", "force"])? {
        arguments.push(
            match mode {
                "autoReview" => "--auto-review",
                "force" => "--force",
                _ => unreachable!(),
            }
            .to_string(),
        );
    }
    push_enum(
        values,
        "sandbox",
        "--sandbox",
        &["enabled", "disabled"],
        arguments,
    )?;
    push_flag(values, "trustWorkspace", "--trust", arguments)
}

fn build_agy(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(
        values,
        &[
            "model",
            "effort",
            "agent",
            "mode",
            "skipPermissions",
            "sandbox",
        ],
    )?;
    push_string(values, "model", "--model", arguments)?;
    push_enum(
        values,
        "effort",
        "--effort",
        &["low", "medium", "high"],
        arguments,
    )?;
    push_string(values, "agent", "--agent", arguments)?;
    push_enum(
        values,
        "mode",
        "--mode",
        &["accept-edits", "plan"],
        arguments,
    )?;
    push_flag(
        values,
        "skipPermissions",
        "--dangerously-skip-permissions",
        arguments,
    )?;
    push_flag(values, "sandbox", "--sandbox", arguments)
}

fn build_opencode(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(values, &["model", "agent", "autoApprove"])?;
    push_string(values, "model", "--model", arguments)?;
    push_string(values, "agent", "--agent", arguments)?;
    push_flag(values, "autoApprove", "--auto", arguments)
}

// Interactive opencode2 only accepts --auto on the default TUI command.
// Model/agent remain accepted in profile config for UI parity and run-mode
// consumers, but they are not emitted on the interactive launch line.
fn build_opencode2(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(values, &["model", "agent", "autoApprove"])?;
    push_flag(values, "autoApprove", "--auto", arguments)
}

fn build_pi(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(values, &["model", "thinking", "projectTrust"])?;
    push_string(values, "model", "--model", arguments)?;
    push_enum(
        values,
        "thinking",
        "--thinking",
        &["off", "minimal", "low", "medium", "high", "xhigh", "max"],
        arguments,
    )?;
    if let Some(trust) = enum_value(values, "projectTrust", &["approve", "ignore"])? {
        arguments.push(
            match trust {
                "approve" => "--approve",
                "ignore" => "--no-approve",
                _ => unreachable!(),
            }
            .to_string(),
        );
    }
    Ok(())
}

fn build_amp(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(values, &["mode", "fast"])?;
    push_enum(
        values,
        "mode",
        "--mode",
        &["low", "medium", "high", "ultra"],
        arguments,
    )?;
    push_flag(values, "fast", "--fast", arguments)
}

fn build_grok(values: &Map<String, Value>, arguments: &mut Vec<String>) -> Result<(), String> {
    require_known_keys(
        values,
        &[
            "model",
            "effort",
            "agent",
            "permissionMode",
            "sandbox",
            "disableWebSearch",
        ],
    )?;
    push_string(values, "model", "--model", arguments)?;
    push_enum(
        values,
        "effort",
        "--effort",
        &["none", "minimal", "low", "medium", "high", "xhigh", "max"],
        arguments,
    )?;
    push_string(values, "agent", "--agent", arguments)?;
    push_enum(
        values,
        "permissionMode",
        "--permission-mode",
        &[
            "default",
            "acceptEdits",
            "auto",
            "dontAsk",
            "bypassPermissions",
            "plan",
        ],
        arguments,
    )?;
    push_enum(
        values,
        "sandbox",
        "--sandbox",
        &["off", "workspace", "devbox", "read-only", "strict"],
        arguments,
    )?;
    push_flag(
        values,
        "disableWebSearch",
        "--disable-web-search",
        arguments,
    )
}

#[cfg(test)]
#[path = "managed_agent_launch_tests.rs"]
mod tests;
