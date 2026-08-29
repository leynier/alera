use std::time::Duration;

use gpui::{Context, Window};
use serde_json::{json, Value};

use super::agent_profile_settings::{
    managed_risk_markers, optional_profile_input_value, parse_agent_profile, parse_agent_profiles,
    profile_input_value, set_profile_input,
};
use super::AleraApp;

const AGENT_PROFILE_ORDERING_CAPABILITY: &str = "orchestrationAgentProfileOrderingV1";
pub(super) const AGENT_PROFILE_REVISIONS_CAPABILITY: &str = "orchestrationAgentProfileRevisionsV1";
const MANAGED_AGENT_PROFILES_CAPABILITY: &str = "orchestrationManagedAgentProfilesV1";
pub(super) const SAFE_EDITING_HOST_ERROR: &str =
    "Safe agent profile editing requires a newer runtime host. \
    Restart Alera to replace the running host.";

impl AleraApp {
    pub(super) fn reorder_agent_profiles(
        &mut self,
        dragged_id: String,
        target_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.agent_profile_settings.saving || dragged_id == target_id {
            return;
        }
        let mut reordered = self.agent_profile_settings.profiles.clone();
        let Some(source_index) = reordered
            .iter()
            .position(|profile| profile.id == dragged_id)
        else {
            return;
        };
        let Some(target_index) = reordered.iter().position(|profile| profile.id == target_id)
        else {
            return;
        };
        let profile = reordered.remove(source_index);
        let insertion_index = if source_index < target_index {
            target_index.saturating_sub(1)
        } else {
            target_index
        }
        .min(reordered.len());
        reordered.insert(insertion_index, profile);
        let ids = reordered
            .iter()
            .map(|profile| profile.id.clone())
            .collect::<Vec<_>>();
        let expected_revisions = reordered
            .iter()
            .map(|profile| (profile.id.clone(), Value::from(profile.revision)))
            .collect::<serde_json::Map<_, _>>();
        self.agent_profile_settings.profiles = reordered;
        self.agent_profile_settings.saving = true;
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.toast = None;
        let bridge = self.bridge.clone();
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = async {
                require_agent_profile_capabilities(
                    &bridge,
                    &[
                        (
                            AGENT_PROFILE_ORDERING_CAPABILITY,
                            "Reordering agent profiles requires a newer runtime host. Restart Alera to replace the running host.",
                        ),
                        (AGENT_PROFILE_REVISIONS_CAPABILITY, SAFE_EDITING_HOST_ERROR),
                    ],
                )
                .await?;
                bridge
                    .request_with_timeout(
                        "agentProfile.reorder",
                        json!({
                            "ids": ids,
                            "expectedRevisions": expected_revisions,
                        }),
                        Duration::from_secs(10),
                    )
                    .await
            }
            .await;
            let _ = this.update_in(cx, |this, _, cx| {
                this.agent_profile_settings.saving = false;
                match result.and_then(parse_agent_profiles) {
                    Ok(mut profiles) => {
                        profiles.sort_by(|left, right| {
                            left.sort_order
                                .cmp(&right.sort_order)
                                .then_with(|| left.name.to_ascii_lowercase().cmp(&right.name.to_ascii_lowercase()))
                                .then_with(|| left.id.cmp(&right.id))
                        });
                        this.agent_profile_settings.profiles = profiles;
                        this.sync_workspace_agent_profile_options();
                    }
                    Err(error) => {
                        this.agent_profile_settings.error = Some(error.into());
                        this.refresh_agent_profiles_without_window(cx);
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn refresh_agent_profiles_without_window(&mut self, cx: &mut Context<Self>) {
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("agentProfile.list", json!({})).await;
            let _ = this.update(cx, |this, cx| {
                if let Ok(mut profiles) = result.and_then(parse_agent_profiles) {
                    profiles.sort_by(|left, right| {
                        left.sort_order
                            .cmp(&right.sort_order)
                            .then_with(|| {
                                left.name
                                    .to_ascii_lowercase()
                                    .cmp(&right.name.to_ascii_lowercase())
                            })
                            .then_with(|| left.id.cmp(&right.id))
                    });
                    this.agent_profile_settings.profiles = profiles;
                    this.sync_workspace_agent_profile_options();
                    cx.notify();
                }
            });
        })
        .detach();
    }

    pub(super) fn set_default_agent_profile(
        &mut self,
        profile_id: Option<String>,
        cx: &mut Context<Self>,
    ) {
        let next = profile_id
            .as_deref()
            .map(str::trim)
            .filter(|id| !id.is_empty())
            .map(str::to_owned);
        if self.settings_state.default_agent_profile_id == next {
            return;
        }
        self.settings_state.default_agent_profile_id = next.clone();
        self.persist_settings();
        self.update_runtime_setting(
            "defaultAgentProfileId",
            next.map_or(Value::Null, Value::String),
            cx,
        );
        self.workspace_selected_agent_profile_id = self
            .settings_state
            .default_agent_profile_id
            .clone()
            .filter(|id| {
                self.workspace_agent_profiles
                    .iter()
                    .any(|profile| &profile.id == id)
            });
        cx.notify();
    }

    pub(super) fn clone_agent_profile(
        &mut self,
        profile_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.agent_profile_settings.saving {
            return;
        }
        let Some(source) = self
            .agent_profile_settings
            .profiles
            .iter()
            .find(|profile| profile.id == profile_id)
            .cloned()
        else {
            return;
        };
        let name = next_clone_name(&source.name, &self.agent_profile_settings.profiles);
        self.seed_agent_profile(&source, window, cx);
        self.agent_profile_settings.selected_id = None;
        self.agent_profile_settings.creating_new = true;
        self.agent_profile_settings.original_risk_markers =
            managed_risk_markers(&source.agent_type, &source.managed_config);
        set_profile_input(&self.agent_profile_settings.name_input, name, window, cx);
        self.begin_agent_profile_save(false, window, cx);
    }

    pub(super) fn save_agent_profile(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.begin_agent_profile_save(false, window, cx);
    }

    pub(super) fn confirm_agent_profile_risk(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.agent_profile_settings.risk_confirmation_open = false;
        self.begin_agent_profile_save(true, window, cx);
    }

    pub(super) fn cancel_agent_profile_risk(&mut self, cx: &mut Context<Self>) {
        self.agent_profile_settings.risk_confirmation_open = false;
        cx.notify();
    }

    fn begin_agent_profile_save(
        &mut self,
        risk_confirmed: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.agent_profile_settings.saving {
            return;
        }
        let name = profile_input_value(&self.agent_profile_settings.name_input, cx);
        if name.is_empty() {
            self.agent_profile_settings.error = Some("Name is required.".into());
            cx.notify();
            return;
        }
        let command = profile_input_value(&self.agent_profile_settings.command_input, cx);
        if self.agent_profile_settings.launch_mode == "command" && command.is_empty() {
            self.agent_profile_settings.error = Some("Command is required.".into());
            cx.notify();
            return;
        }
        if self.agent_profile_settings.launch_mode == "managed" && !risk_confirmed {
            let next_risks = managed_risk_markers(
                &self.agent_profile_settings.adapter,
                &self.agent_profile_settings.managed_config,
            );
            if !next_risks.is_subset(&self.agent_profile_settings.original_risk_markers) {
                self.agent_profile_settings.risk_confirmation_open = true;
                cx.notify();
                return;
            }
        }
        let mut payload = json!({
            "name": name,
            "agentType": self.agent_profile_settings.adapter,
            "launchMode": self.agent_profile_settings.launch_mode,
            "command": command,
            "customPrompt": self
                .agent_profile_settings
                .custom_prompt_input
                .read(cx)
                .value()
                .trim()
                .to_owned(),
            "description": profile_input_value(&self.agent_profile_settings.description_input, cx),
            "quotaGroup": optional_profile_input_value(&self.agent_profile_settings.quota_group_input, cx),
        });
        if let Some(id) = &self.agent_profile_settings.selected_id {
            payload["id"] = Value::String(id.clone());
            let Some(profile) = self
                .agent_profile_settings
                .profiles
                .iter()
                .find(|profile| &profile.id == id)
            else {
                self.agent_profile_settings.error = Some(
                    "The selected agent profile no longer exists. Refresh and try again.".into(),
                );
                cx.notify();
                return;
            };
            payload["expectedRevision"] = Value::from(profile.revision);
        }
        if self.agent_profile_settings.launch_mode == "managed" {
            payload["managedConfig"] =
                Value::Object(self.agent_profile_settings.managed_config.clone());
        }
        self.persist_agent_profile(payload, window, cx);
    }

    fn persist_agent_profile(
        &mut self,
        payload: Value,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.agent_profile_settings.saving = true;
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.toast = None;
        let bridge = self.bridge.clone();
        let required_capabilities = agent_profile_upsert_capabilities(&payload);
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = async {
                require_agent_profile_capabilities(&bridge, &required_capabilities).await?;
                bridge
                    .request_with_timeout("agentProfile.upsert", payload, Duration::from_secs(10))
                    .await
            }
            .await;
            let _ = this.update_in(cx, |this, window, cx| {
                this.agent_profile_settings.saving = false;
                match result.and_then(|value| parse_agent_profile(&value)) {
                    Ok(profile) => {
                        if let Some(existing) = this
                            .agent_profile_settings
                            .profiles
                            .iter_mut()
                            .find(|candidate| candidate.id == profile.id)
                        {
                            *existing = profile.clone();
                        } else {
                            this.agent_profile_settings.profiles.push(profile.clone());
                            this.agent_profile_settings
                                .profiles
                                .sort_by(|left, right| left.name.cmp(&right.name));
                        }
                        this.seed_agent_profile(&profile, window, cx);
                        this.agent_profile_settings.toast = Some("Agent Profile Saved".into());
                        this.sync_workspace_agent_profile_options();
                    }
                    Err(error) => this.agent_profile_settings.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn sync_workspace_agent_profile_options(&mut self) {
        self.workspace_agent_profiles = self
            .agent_profile_settings
            .profiles
            .iter()
            .map(|profile| super::AgentProfileOption {
                id: profile.id.clone(),
                name: profile.name.clone(),
            })
            .collect();
        self.workspace_selected_agent_profile_id = self
            .workspace_selected_agent_profile_id
            .clone()
            .filter(|id| {
                self.workspace_agent_profiles
                    .iter()
                    .any(|profile| &profile.id == id)
            })
            .or_else(|| {
                self.settings_state
                    .default_agent_profile_id
                    .as_deref()
                    .filter(|id| {
                        self.workspace_agent_profiles
                            .iter()
                            .any(|profile| &profile.id == id)
                    })
                    .map(str::to_owned)
            })
            .or_else(|| {
                self.workspace_agent_profiles
                    .first()
                    .map(|profile| profile.id.clone())
            });
    }
}

fn agent_profile_upsert_capabilities(payload: &Value) -> Vec<(&'static str, &'static str)> {
    let mut requirements = Vec::new();
    if payload.get("id").is_some() {
        requirements.push((AGENT_PROFILE_REVISIONS_CAPABILITY, SAFE_EDITING_HOST_ERROR));
    }
    if payload.get("launchMode").and_then(Value::as_str) == Some("managed") {
        requirements.push((
            MANAGED_AGENT_PROFILES_CAPABILITY,
            "Managed agent profiles require a newer runtime host. Restart Alera to replace the running host, or use Command mode.",
        ));
    }
    requirements
}

pub(super) async fn require_agent_profile_capabilities(
    bridge: &crate::runtime_bridge::RuntimeBridge,
    requirements: &[(&str, &str)],
) -> Result<(), String> {
    if requirements.is_empty() {
        return Ok(());
    }
    let status = bridge
        .request_with_timeout("status.get", json!({}), Duration::from_secs(10))
        .await?;
    let capabilities = status.get("runtimeCapabilities").and_then(Value::as_array);
    for (capability, message) in requirements {
        let supported = capabilities
            .is_some_and(|items| items.iter().any(|item| item.as_str() == Some(*capability)));
        if !supported {
            return Err((*message).to_owned());
        }
    }
    Ok(())
}

fn next_clone_name(
    source_name: &str,
    profiles: &[super::agent_profile_settings::AgentProfileRecord],
) -> String {
    let base = format!("{} Copy", source_name.trim());
    let names = profiles
        .iter()
        .map(|profile| profile.name.trim().to_ascii_lowercase())
        .collect::<std::collections::BTreeSet<_>>();
    if !names.contains(&base.to_ascii_lowercase()) {
        return base;
    }
    for suffix in 2.. {
        let candidate = format!("{base} {suffix}");
        if !names.contains(&candidate.to_ascii_lowercase()) {
            return candidate;
        }
    }
    unreachable!("profile clone suffix space is unbounded")
}
