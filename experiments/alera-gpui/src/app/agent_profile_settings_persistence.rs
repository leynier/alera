use std::time::Duration;

use gpui::{Context, Window};
use serde_json::{json, Value};

use super::agent_profile_settings::{
    managed_risk_markers, optional_profile_input_value, parse_agent_profile, profile_input_value,
};
use super::AleraApp;

impl AleraApp {
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
            "description": profile_input_value(&self.agent_profile_settings.description_input, cx),
            "quotaGroup": optional_profile_input_value(&self.agent_profile_settings.quota_group_input, cx),
        });
        if let Some(id) = &self.agent_profile_settings.selected_id {
            payload["id"] = Value::String(id.clone());
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
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout("agentProfile.upsert", payload, Duration::from_secs(10))
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

    pub(super) fn remove_agent_profile(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.agent_profile_settings.saving {
            return;
        }
        let Some(id) = self.agent_profile_settings.selected_id.clone() else {
            return;
        };
        self.agent_profile_settings.saving = true;
        self.agent_profile_settings.error = None;
        let bridge = self.bridge.clone();
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "agentProfile.remove",
                    json!({"id": id}),
                    Duration::from_secs(10),
                )
                .await;
            let _ = this.update_in(cx, |this, window, cx| {
                this.agent_profile_settings.saving = false;
                match result {
                    Ok(_) => {
                        this.agent_profile_settings
                            .profiles
                            .retain(|profile| profile.id != id);
                        if let Some(next) = this.agent_profile_settings.profiles.first().cloned() {
                            this.seed_agent_profile(&next, window, cx);
                        } else {
                            this.new_agent_profile(window, cx);
                            this.agent_profile_settings.creating_new = false;
                        }
                        this.agent_profile_settings.toast = Some("Agent Profile Removed".into());
                        this.sync_workspace_agent_profile_options();
                    }
                    Err(error) => this.agent_profile_settings.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn sync_workspace_agent_profile_options(&mut self) {
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
                self.workspace_agent_profiles
                    .first()
                    .map(|profile| profile.id.clone())
            });
    }
}
