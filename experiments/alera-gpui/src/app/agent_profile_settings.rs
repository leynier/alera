use std::collections::{BTreeMap, BTreeSet};

use gpui::{AppContext as _, Context, Entity, FocusHandle, SharedString, Window};
use gpui_component::input::InputState;
use serde_json::{Map, Value};

use super::AleraApp;
use crate::icons::AgentIcon;

#[derive(Clone, Debug)]
pub(super) struct AgentProfileRecord {
    pub(super) id: String,
    pub(super) name: String,
    pub(super) agent_type: String,
    pub(super) command: String,
    pub(super) launch_mode: String,
    pub(super) managed_config: Map<String, Value>,
    pub(super) description: String,
    pub(super) quota_group: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum AgentProfileDropdown {
    Adapter,
    LaunchMode,
    Managed(&'static str),
}

pub(super) struct AgentProfileSettingsState {
    pub(super) profiles: Vec<AgentProfileRecord>,
    pub(super) selected_id: Option<String>,
    pub(super) creating_new: bool,
    pub(super) loading: bool,
    pub(super) load_error: Option<SharedString>,
    pub(super) saving: bool,
    pub(super) error: Option<SharedString>,
    pub(super) toast: Option<SharedString>,
    pub(super) dropdown: Option<AgentProfileDropdown>,
    pub(super) dropdown_focus: FocusHandle,
    pub(super) dropdown_highlighted_index: usize,
    pub(super) dropdown_filter_input: Entity<InputState>,
    pub(super) risk_confirmation_open: bool,
    pub(super) original_risk_markers: BTreeSet<String>,
    pub(super) discovered_personas: BTreeMap<String, Vec<String>>,
    pub(super) persona_discovery_busy: BTreeSet<String>,
    pub(super) persona_discovery_errors: BTreeMap<String, SharedString>,
    pub(super) persona_auto_discovered: BTreeSet<String>,
    pub(super) adapter: String,
    pub(super) launch_mode: String,
    pub(super) managed_config: Map<String, Value>,
    pub(super) name_input: Entity<InputState>,
    pub(super) command_input: Entity<InputState>,
    pub(super) model_input: Entity<InputState>,
    pub(super) persona_input: Entity<InputState>,
    pub(super) max_ai_credits_input: Entity<InputState>,
    pub(super) max_autopilot_continues_input: Entity<InputState>,
    pub(super) description_input: Entity<InputState>,
    pub(super) quota_group_input: Entity<InputState>,
}

impl AgentProfileSettingsState {
    pub(super) fn new(window: &mut Window, cx: &mut Context<AleraApp>) -> Self {
        Self {
            profiles: Vec::new(),
            selected_id: None,
            creating_new: false,
            loading: false,
            load_error: None,
            saving: false,
            error: None,
            toast: None,
            dropdown: None,
            dropdown_focus: cx.focus_handle().tab_stop(true),
            dropdown_highlighted_index: 0,
            dropdown_filter_input: cx.new(|cx| {
                InputState::new(window, cx)
                    .placeholder("Search")
                    .clean_on_escape()
            }),
            risk_confirmation_open: false,
            original_risk_markers: BTreeSet::new(),
            discovered_personas: BTreeMap::new(),
            persona_discovery_busy: BTreeSet::new(),
            persona_discovery_errors: BTreeMap::new(),
            persona_auto_discovered: BTreeSet::new(),
            adapter: "codex".to_owned(),
            launch_mode: "managed".to_owned(),
            managed_config: Map::new(),
            name_input: cx.new(|cx| InputState::new(window, cx).placeholder("Name")),
            command_input: cx.new(|cx| InputState::new(window, cx).placeholder("Command")),
            model_input: cx.new(|cx| InputState::new(window, cx)),
            persona_input: cx.new(|cx| InputState::new(window, cx)),
            max_ai_credits_input: cx.new(|cx| InputState::new(window, cx)),
            max_autopilot_continues_input: cx.new(|cx| InputState::new(window, cx)),
            description_input: cx.new(|cx| InputState::new(window, cx).placeholder("Description")),
            quota_group_input: cx.new(|cx| InputState::new(window, cx).placeholder("Quota Group")),
        }
    }

    pub(super) fn managed_inputs(&self) -> Vec<(&'static str, Entity<InputState>)> {
        vec![
            ("model", self.model_input.clone()),
            ("agent", self.persona_input.clone()),
            ("maxAiCredits", self.max_ai_credits_input.clone()),
            (
                "maxAutopilotContinues",
                self.max_autopilot_continues_input.clone(),
            ),
            ("description", self.description_input.clone()),
            ("quotaGroup", self.quota_group_input.clone()),
        ]
    }
}

pub(super) fn parse_agent_profiles(payload: Value) -> Result<Vec<AgentProfileRecord>, String> {
    let items = payload
        .get("items")
        .and_then(Value::as_array)
        .or_else(|| payload.as_array())
        .ok_or_else(|| "Agent Profile List Omitted Items".to_owned())?;
    items.iter().map(parse_agent_profile).collect()
}

pub(super) fn parse_agent_profile(value: &Value) -> Result<AgentProfileRecord, String> {
    let string = |key: &str| {
        value
            .get(key)
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or_else(|| format!("Agent Profile Omitted {}", title_from_key(key)))
    };
    Ok(AgentProfileRecord {
        id: string("id")?,
        name: string("name")?,
        agent_type: string("agentType")?,
        command: string("command")?,
        launch_mode: value
            .get("launchMode")
            .and_then(Value::as_str)
            .unwrap_or("command")
            .to_owned(),
        managed_config: value
            .get("managedConfig")
            .and_then(Value::as_object)
            .cloned()
            .unwrap_or_default(),
        description: value
            .get("description")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned(),
        quota_group: value
            .get("quotaGroup")
            .and_then(Value::as_str)
            .map(str::to_owned),
    })
}

pub(super) fn adapter_label(adapter: &str) -> &'static str {
    match adapter {
        "codex" => "Codex",
        "claude" => "Claude Code",
        "copilot" => "GitHub Copilot",
        "cursor" => "Cursor",
        "agy" => "Antigravity",
        "opencode" => "OpenCode",
        "pi" => "Pi",
        "amp" => "Amp",
        _ => "Unknown",
    }
}

pub(super) fn adapter_icon(adapter: &str) -> AgentIcon {
    match adapter {
        "claude" => AgentIcon::Claude,
        "copilot" => AgentIcon::Copilot,
        "cursor" => AgentIcon::Cursor,
        "agy" => AgentIcon::Agy,
        "opencode" => AgentIcon::OpenCode,
        "pi" => AgentIcon::Pi,
        "amp" => AgentIcon::Amp,
        _ => AgentIcon::Codex,
    }
}

pub(super) fn default_agent_command(adapter: &str) -> &'static str {
    match adapter {
        "codex" => "codex",
        "claude" => "claude",
        "copilot" => "copilot",
        "cursor" => "cursor-agent",
        "agy" => "agy",
        "opencode" => "opencode",
        "pi" => "pi",
        "amp" => "amp",
        _ => "codex",
    }
}

pub(super) fn managed_command_preview(adapter: &str, config: &Map<String, Value>) -> String {
    let mut args = Vec::new();
    match adapter {
        "codex" => {
            push_string_option(&mut args, config, "model", "--model");
            if let Some(effort) = config.get("effort").and_then(Value::as_str) {
                args.push("--config".to_owned());
                args.push(format!("model_reasoning_effort={effort}"));
            }
            if config
                .get("bypassApprovalsAndSandbox")
                .and_then(Value::as_bool)
                == Some(true)
            {
                args.push("--dangerously-bypass-approvals-and-sandbox".to_owned());
            } else {
                push_string_option(&mut args, config, "sandbox", "--sandbox");
                push_string_option(&mut args, config, "approvalPolicy", "--ask-for-approval");
            }
            if config.get("webSearch").and_then(Value::as_bool) == Some(true) {
                args.push("--search".to_owned());
            }
        }
        "claude" => {
            push_string_option(&mut args, config, "model", "--model");
            push_string_option(&mut args, config, "effort", "--effort");
            push_string_option(&mut args, config, "agent", "--agent");
            push_string_option(&mut args, config, "permissionMode", "--permission-mode");
        }
        "copilot" => {
            for (key, flag) in [
                ("model", "--model"),
                ("effort", "--effort"),
                ("agent", "--agent"),
                ("mode", "--mode"),
                ("context", "--context"),
            ] {
                push_string_option(&mut args, config, key, flag);
            }
        }
        "cursor" => {
            push_string_option(&mut args, config, "model", "--model");
            push_string_option(&mut args, config, "mode", "--mode");
            push_string_option(&mut args, config, "sandbox", "--sandbox");
        }
        "agy" => {
            for (key, flag) in [
                ("model", "--model"),
                ("effort", "--effort"),
                ("agent", "--agent"),
                ("mode", "--mode"),
            ] {
                push_string_option(&mut args, config, key, flag);
            }
        }
        "opencode" => {
            push_string_option(&mut args, config, "model", "--model");
            push_string_option(&mut args, config, "agent", "--agent");
        }
        "pi" => {
            push_string_option(&mut args, config, "model", "--model");
            push_string_option(&mut args, config, "thinking", "--thinking");
        }
        "amp" => push_string_option(&mut args, config, "mode", "--mode"),
        _ => {}
    }
    std::iter::once(default_agent_command(adapter).to_owned())
        .chain(args)
        .collect::<Vec<_>>()
        .join(" ")
}

pub(super) fn managed_risk_markers(adapter: &str, config: &Map<String, Value>) -> BTreeSet<String> {
    let mut markers = BTreeSet::new();
    let mut mark = |condition: bool, marker: &str| {
        if condition {
            markers.insert(marker.to_owned());
        }
    };
    let string_is = |key: &str, value: &str| config.get(key).and_then(Value::as_str) == Some(value);
    let enabled = |key: &str| config.get(key).and_then(Value::as_bool) == Some(true);
    match adapter {
        "codex" => {
            mark(
                enabled("bypassApprovalsAndSandbox"),
                "bypassApprovalsAndSandbox",
            );
            mark(
                string_is("sandbox", "danger-full-access"),
                "dangerFullAccess",
            );
            mark(string_is("approvalPolicy", "never"), "neverAsk");
        }
        "claude" => {
            mark(
                string_is("permissionMode", "bypassPermissions"),
                "bypassPermissions",
            );
            mark(string_is("permissionMode", "dontAsk"), "dontAsk");
        }
        "copilot" => {
            mark(enabled("allowAll"), "allowAll");
            mark(string_is("mode", "autopilot"), "autopilot");
            mark(enabled("noAskUser"), "noAskUser");
        }
        "cursor" => {
            mark(string_is("permissionMode", "force"), "force");
            mark(string_is("sandbox", "disabled"), "sandboxDisabled");
            mark(enabled("trustWorkspace"), "trustWorkspace");
        }
        "agy" => mark(enabled("skipPermissions"), "skipPermissions"),
        "opencode" => mark(enabled("autoApprove"), "autoApprove"),
        "pi" => mark(string_is("projectTrust", "approve"), "projectTrust"),
        _ => {}
    }
    markers
}

pub(super) fn managed_risk_warning(adapter: &str, config: &Map<String, Value>) -> &'static str {
    match adapter {
        "codex"
            if config
                .get("bypassApprovalsAndSandbox")
                .and_then(Value::as_bool)
                == Some(true) =>
        {
            "This Profile Will Bypass Codex Approvals And Sandbox Protections."
        }
        "codex" => "This Profile Reduces Codex Approval Or Sandbox Protections.",
        "claude" => "This Profile Lets Claude Continue With Reduced Permission Prompts.",
        "copilot" => "This Profile Lets Copilot Take Broader Actions With Less Supervision.",
        "cursor" => "This Profile Reduces Cursor Review, Sandbox, Or Trust Protections.",
        "agy" => "This Profile Lets Antigravity Skip Permission Checks.",
        "opencode" => "This Profile Lets OpenCode Approve Actions Automatically.",
        "pi" => "This Profile Pre-Approves Project Trust For Pi.",
        _ => "",
    }
}

fn push_string_option(args: &mut Vec<String>, config: &Map<String, Value>, key: &str, flag: &str) {
    if let Some(value) = config.get(key).and_then(Value::as_str) {
        if !value.is_empty() {
            args.push(flag.to_owned());
            args.push(quote_preview(value));
        }
    }
}

fn quote_preview(value: &str) -> String {
    if value
        .chars()
        .all(|character| character.is_ascii_alphanumeric() || "_./:=+-".contains(character))
    {
        value.to_owned()
    } else {
        format!("'{}'", value.replace('\'', "'\"'\"'"))
    }
}

fn title_from_key(key: &str) -> String {
    let mut title = String::new();
    for character in key.chars() {
        if character.is_ascii_uppercase() {
            title.push(' ');
        }
        if title.is_empty() {
            title.push(character.to_ascii_uppercase());
        } else {
            title.push(character);
        }
    }
    title
}

pub(super) fn set_profile_input(
    input: &Entity<InputState>,
    value: impl Into<String>,
    window: &mut Window,
    cx: &mut Context<AleraApp>,
) {
    let value = value.into();
    input.update(cx, |input, cx| input.set_value(value, window, cx));
}

pub(super) fn profile_input_value(input: &Entity<InputState>, cx: &Context<AleraApp>) -> String {
    input.read(cx).value().trim().to_owned()
}

pub(super) fn optional_profile_input_value(
    input: &Entity<InputState>,
    cx: &Context<AleraApp>,
) -> Option<String> {
    let value = profile_input_value(input, cx);
    (!value.is_empty()).then_some(value)
}

pub(super) fn profile_number_text(value: Option<&Value>) -> String {
    value
        .and_then(Value::as_f64)
        .map(|number| {
            if number.fract() == 0.0 {
                format!("{number:.0}")
            } else {
                number.to_string()
            }
        })
        .unwrap_or_default()
}

#[cfg(test)]
#[path = "agent_profile_settings_tests.rs"]
mod tests;
