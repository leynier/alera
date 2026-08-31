use std::collections::{BTreeSet, HashMap};
use std::io::Read;

use alera_core::runtime::{AgentProfile, AgentProfileLaunchMode};
use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Map, Value};

use crate::cli::{
    AgentProfileCreateArgs, AgentProfileLaunchModeArg, AgentProfileUpdateArgs,
    ManagedConfigInputArgs,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct AgentProfileDraft {
    pub name: String,
    pub agent_type: String,
    pub command: String,
    pub launch_mode: AgentProfileLaunchMode,
    pub managed_config: Option<Value>,
    pub custom_prompt: String,
    pub description: String,
    pub quota_group: Option<String>,
}

impl AgentProfileDraft {
    pub(crate) fn create_payload(self) -> Value {
        let mut payload = Map::from_iter([
            ("name".to_string(), json!(self.name)),
            ("agentType".to_string(), json!(self.agent_type)),
            ("command".to_string(), json!(self.command)),
            ("launchMode".to_string(), json!(self.launch_mode.as_str())),
            ("customPrompt".to_string(), json!(self.custom_prompt)),
            ("description".to_string(), json!(self.description)),
            ("quotaGroup".to_string(), json!(self.quota_group)),
        ]);
        if let Some(config) = self.managed_config {
            payload.insert("managedConfig".to_string(), config);
        }
        Value::Object(payload)
    }

    pub(crate) fn update_payload(self, id: &str, expected_revision: i64) -> Value {
        let mut payload = self.create_payload();
        let object = payload
            .as_object_mut()
            .expect("agent profile draft payload must be an object");
        object.insert("id".to_string(), json!(id));
        object.insert("expectedRevision".to_string(), json!(expected_revision));
        payload
    }
}

pub(crate) fn managed_config_for_create(
    args: &AgentProfileCreateArgs,
    stdin: &mut impl Read,
) -> Result<Option<Value>> {
    validate_launch_inputs(
        launch_mode(args.launch_mode),
        args.command.is_some(),
        has_managed_config_input(&args.managed),
    )?;
    read_managed_config(&args.managed, stdin)
}

pub(crate) fn managed_config_for_update(
    existing: &AgentProfile,
    args: &AgentProfileUpdateArgs,
    stdin: &mut impl Read,
) -> Result<Option<Value>> {
    let launch_mode = args
        .launch_mode
        .map(launch_mode)
        .unwrap_or(existing.launch_mode);
    validate_launch_inputs(
        launch_mode,
        args.command.is_some(),
        has_managed_config_input(&args.managed),
    )?;
    read_managed_config(&args.managed, stdin)
}

pub(crate) fn draft_for_create(
    args: &AgentProfileCreateArgs,
    managed_config: Option<Value>,
) -> Result<AgentProfileDraft> {
    let launch_mode = launch_mode(args.launch_mode);
    let (command, managed_config) =
        launch_values(launch_mode, args.command.as_deref(), managed_config, None)?;
    Ok(AgentProfileDraft {
        name: required_trimmed(&args.name, "name")?,
        agent_type: required_trimmed(&args.agent_type, "agent type")?,
        command,
        launch_mode,
        managed_config,
        custom_prompt: trimmed_or_default(args.custom_prompt.as_deref()),
        description: trimmed_or_default(args.description.as_deref()),
        quota_group: trimmed_optional(args.quota_group.as_deref()),
    })
}

pub(crate) fn draft_for_update(
    existing: &AgentProfile,
    args: &AgentProfileUpdateArgs,
    managed_config: Option<Value>,
) -> Result<AgentProfileDraft> {
    let launch_mode = args
        .launch_mode
        .map(launch_mode)
        .unwrap_or(existing.launch_mode);
    let agent_type = match args.agent_type.as_deref() {
        Some(value) => required_trimmed(value, "agent type")?,
        None => existing.agent_type.clone(),
    };
    if launch_mode == AgentProfileLaunchMode::Managed
        && existing.launch_mode == AgentProfileLaunchMode::Managed
        && existing.agent_type != agent_type
        && managed_config.is_none()
    {
        bail!(
            "changing --agent-type on a managed profile requires explicit managed configuration (--managed-config, --managed-config-file, or --managed-config-stdin)"
        );
    }
    let reusable_existing = (existing.launch_mode == launch_mode
        && existing.agent_type == agent_type)
        .then_some(existing);
    let (command, managed_config) = launch_values(
        launch_mode,
        args.command.as_deref(),
        managed_config,
        reusable_existing,
    )?;
    let draft = AgentProfileDraft {
        name: match args.name.as_deref() {
            Some(value) => required_trimmed(value, "name")?,
            None => existing.name.clone(),
        },
        agent_type,
        command,
        launch_mode,
        managed_config,
        custom_prompt: updated_text(
            &existing.custom_prompt,
            args.custom_prompt.as_deref(),
            args.clear_custom_prompt,
        ),
        description: updated_text(
            &existing.description,
            args.description.as_deref(),
            args.clear_description,
        ),
        quota_group: if args.clear_quota_group {
            None
        } else if let Some(value) = args.quota_group.as_deref() {
            trimmed_optional(Some(value))
        } else {
            existing.quota_group.clone()
        },
    };
    if draft == draft_from_profile(existing) {
        bail!("agent profile update does not change any fields");
    }
    Ok(draft)
}

fn launch_values(
    launch_mode: AgentProfileLaunchMode,
    command: Option<&str>,
    managed_config: Option<Value>,
    reusable_existing: Option<&AgentProfile>,
) -> Result<(String, Option<Value>)> {
    match launch_mode {
        AgentProfileLaunchMode::Command => {
            if managed_config.is_some() {
                bail!("managed configuration is only valid with --launch-mode managed");
            }
            let command = match command {
                Some(value) => required_trimmed(value, "command")?,
                None => reusable_existing
                    .filter(|profile| profile.launch_mode == AgentProfileLaunchMode::Command)
                    .map(|profile| profile.command.clone())
                    .ok_or_else(|| anyhow!("--command is required for Command launch mode"))?,
            };
            Ok((command, None))
        }
        AgentProfileLaunchMode::Managed => {
            if command.is_some() {
                bail!("--command is only valid with --launch-mode command");
            }
            let config = managed_config
                .or_else(|| reusable_existing.and_then(|profile| profile.managed_config.clone()))
                .unwrap_or_else(|| json!({}));
            Ok((String::new(), Some(config)))
        }
    }
}

fn validate_launch_inputs(
    launch_mode: AgentProfileLaunchMode,
    has_command: bool,
    has_managed_config: bool,
) -> Result<()> {
    match launch_mode {
        AgentProfileLaunchMode::Command if has_managed_config => {
            bail!("managed configuration is only valid with --launch-mode managed");
        }
        AgentProfileLaunchMode::Managed if has_command => {
            bail!("--command is only valid with --launch-mode command");
        }
        _ => Ok(()),
    }
}

fn has_managed_config_input(args: &ManagedConfigInputArgs) -> bool {
    args.managed_config.is_some() || args.managed_config_file.is_some() || args.managed_config_stdin
}

fn draft_from_profile(profile: &AgentProfile) -> AgentProfileDraft {
    AgentProfileDraft {
        name: profile.name.clone(),
        agent_type: profile.agent_type.clone(),
        command: if profile.launch_mode == AgentProfileLaunchMode::Command {
            profile.command.clone()
        } else {
            String::new()
        },
        launch_mode: profile.launch_mode,
        managed_config: profile.managed_config.clone(),
        custom_prompt: profile.custom_prompt.clone(),
        description: profile.description.clone(),
        quota_group: profile.quota_group.clone(),
    }
}

pub(crate) fn read_managed_config(
    args: &ManagedConfigInputArgs,
    stdin: &mut impl Read,
) -> Result<Option<Value>> {
    let contents = if let Some(raw) = args.managed_config.as_deref() {
        Some(raw.to_string())
    } else if let Some(path) = args.managed_config_file.as_deref() {
        Some(
            std::fs::read_to_string(path)
                .with_context(|| format!("failed to read managed configuration from {path}"))?,
        )
    } else if args.managed_config_stdin {
        let mut contents = String::new();
        stdin
            .read_to_string(&mut contents)
            .context("failed to read managed configuration from standard input")?;
        Some(contents)
    } else {
        None
    };
    contents
        .map(|contents| {
            let value: Value = serde_json::from_str(&contents)
                .context("managed configuration must be valid JSON")?;
            if !value.is_object() {
                bail!("managed configuration must be a JSON object");
            }
            Ok(value)
        })
        .transpose()
}

pub(crate) fn ensure_expected_revision(
    profile: &AgentProfile,
    expected_revision: Option<i64>,
) -> Result<i64> {
    if expected_revision.is_some_and(|expected| expected != profile.revision) {
        bail!(
            "agent profile revision conflict for {}: expected {}, current {}",
            profile.id,
            expected_revision.expect("checked as present"),
            profile.revision
        );
    }
    Ok(expected_revision.unwrap_or(profile.revision))
}

pub(crate) fn ensure_risk_confirmation(
    existing: Option<&AgentProfile>,
    draft: &AgentProfileDraft,
    confirmed: bool,
) -> Result<()> {
    if draft.launch_mode != AgentProfileLaunchMode::Managed {
        return Ok(());
    }
    let next = risk_markers(
        &draft.agent_type,
        draft.managed_config.as_ref().unwrap_or(&Value::Null),
    );
    let original = existing
        .filter(|profile| {
            profile.launch_mode == AgentProfileLaunchMode::Managed
                && profile.agent_type == draft.agent_type
        })
        .map(|profile| {
            risk_markers(
                &profile.agent_type,
                profile.managed_config.as_ref().unwrap_or(&Value::Null),
            )
        })
        .unwrap_or_default();
    let introduced = next.difference(&original).copied().collect::<Vec<_>>();
    if !introduced.is_empty() && !confirmed {
        bail!(
            "managed configuration introduces reduced protections ({}); retry with --confirm-reduced-protections",
            introduced.join(", ")
        );
    }
    Ok(())
}

pub(crate) fn parse_revision_overrides(values: &[String]) -> Result<HashMap<String, i64>> {
    let mut revisions = HashMap::new();
    for value in values {
        let (id, revision) = value
            .split_once('=')
            .ok_or_else(|| anyhow!("expected revision must use ID=REVISION: {value}"))?;
        let id = required_trimmed(id, "profile id")?;
        let revision = revision
            .parse::<i64>()
            .ok()
            .filter(|revision| *revision >= 0)
            .ok_or_else(|| anyhow!("revision must be a non-negative integer: {value}"))?;
        if revisions.insert(id.clone(), revision).is_some() {
            bail!("duplicate expected revision for profile: {id}");
        }
    }
    Ok(revisions)
}

fn risk_markers(agent_type: &str, config: &Value) -> BTreeSet<&'static str> {
    let Some(config) = config.as_object() else {
        return BTreeSet::new();
    };
    let mut markers = BTreeSet::new();
    let mut mark = |condition: bool, marker| {
        if condition {
            markers.insert(marker);
        }
    };
    match agent_type {
        "codex" => {
            mark(
                config.get("bypassApprovalsAndSandbox") == Some(&Value::Bool(true)),
                "bypassApprovalsAndSandbox",
            );
            mark(
                config.get("sandbox").and_then(Value::as_str) == Some("danger-full-access"),
                "dangerFullAccess",
            );
            mark(
                config.get("approvalPolicy").and_then(Value::as_str) == Some("never"),
                "neverAsk",
            );
        }
        "claude" => {
            mark(
                config.get("permissionMode").and_then(Value::as_str) == Some("bypassPermissions"),
                "bypassPermissions",
            );
            mark(
                config.get("permissionMode").and_then(Value::as_str) == Some("dontAsk"),
                "dontAsk",
            );
            mark(
                config.get("allowSkipPermissions") == Some(&Value::Bool(true)),
                "allowSkipPermissions",
            );
        }
        "copilot" => {
            mark(
                config.get("allowAll") == Some(&Value::Bool(true)),
                "allowAll",
            );
            mark(
                config.get("mode").and_then(Value::as_str) == Some("autopilot"),
                "autopilot",
            );
            mark(
                config.get("noAskUser") == Some(&Value::Bool(true)),
                "noAskUser",
            );
        }
        "cursor" => {
            mark(
                config.get("permissionMode").and_then(Value::as_str) == Some("force"),
                "force",
            );
            mark(
                config.get("sandbox").and_then(Value::as_str) == Some("disabled"),
                "sandboxDisabled",
            );
            mark(
                config.get("trustWorkspace") == Some(&Value::Bool(true)),
                "trustWorkspace",
            );
        }
        "agy" => mark(
            config.get("skipPermissions") == Some(&Value::Bool(true)),
            "skipPermissions",
        ),
        "opencode" | "opencode2" => mark(
            config.get("autoApprove") == Some(&Value::Bool(true)),
            "autoApprove",
        ),
        "pi" => mark(
            config.get("projectTrust").and_then(Value::as_str) == Some("approve"),
            "projectTrust",
        ),
        "grok" => {
            mark(
                config.get("permissionMode").and_then(Value::as_str) == Some("bypassPermissions"),
                "bypassPermissions",
            );
            mark(
                config.get("permissionMode").and_then(Value::as_str) == Some("dontAsk"),
                "dontAsk",
            );
        }
        _ => {}
    }
    markers
}

fn launch_mode(value: AgentProfileLaunchModeArg) -> AgentProfileLaunchMode {
    value
        .as_wire()
        .parse()
        .expect("clap launch modes must match the runtime model")
}

fn required_trimmed(value: &str, field: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        bail!("agent profile {field} is required");
    }
    Ok(value.to_string())
}

fn trimmed_or_default(value: Option<&str>) -> String {
    value.map(str::trim).unwrap_or_default().to_string()
}

fn trimmed_optional(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn updated_text(existing: &str, value: Option<&str>, clear: bool) -> String {
    if clear {
        String::new()
    } else {
        value
            .map(str::trim)
            .map(str::to_string)
            .unwrap_or_else(|| existing.to_string())
    }
}

#[cfg(test)]
#[path = "agent_profile_input_tests.rs"]
mod tests;
