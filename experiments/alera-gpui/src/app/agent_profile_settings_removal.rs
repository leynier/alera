use std::time::Duration;

use gpui::{Context, Window};
use serde_json::json;

use super::agent_profile_removal::parse_agent_profile_removal_impact;
use super::agent_profile_settings_persistence::{
    require_agent_profile_capabilities, AGENT_PROFILE_REVISIONS_CAPABILITY, SAFE_EDITING_HOST_ERROR,
};
use super::AleraApp;

const AGENT_PROFILE_REMOVAL_CAPABILITY: &str = "orchestrationAgentProfileRemovalV1";
const REMOVAL_HOST_ERROR: &str = "Deleting agent profiles requires a newer runtime host. \
    Restart Alera to replace the running host.";

impl AleraApp {
    pub(super) fn inspect_agent_profile_removal(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.agent_profile_settings.saving {
            return;
        }
        let Some(id) = self.agent_profile_settings.selected_id.clone() else {
            return;
        };
        let Some(expected_revision) = self
            .agent_profile_settings
            .profiles
            .iter()
            .find(|profile| profile.id == id)
            .map(|profile| profile.revision)
        else {
            self.agent_profile_settings.error =
                Some("The selected agent profile no longer exists. Refresh and try again.".into());
            cx.notify();
            return;
        };
        self.agent_profile_settings.saving = true;
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.removal_confirmation = None;
        let bridge = self.bridge.clone();
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = async {
                require_agent_profile_capabilities(
                    &bridge,
                    &[
                        (AGENT_PROFILE_REVISIONS_CAPABILITY, SAFE_EDITING_HOST_ERROR),
                        (AGENT_PROFILE_REMOVAL_CAPABILITY, REMOVAL_HOST_ERROR),
                    ],
                )
                .await?;
                bridge
                    .request_with_timeout(
                        "agentProfile.removalImpact",
                        json!({"id": id, "expectedRevision": expected_revision}),
                        Duration::from_secs(10),
                    )
                    .await
            }
            .await;
            let _ = this.update_in(cx, |this, _, cx| {
                this.agent_profile_settings.saving = false;
                match result.and_then(|value| parse_agent_profile_removal_impact(&value)) {
                    Ok(impact) => {
                        this.agent_profile_settings.removal_confirmation = Some(impact);
                    }
                    Err(error) => this.agent_profile_settings.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn cancel_agent_profile_removal(&mut self, cx: &mut Context<Self>) {
        self.agent_profile_settings.removal_confirmation = None;
        cx.notify();
    }

    pub(super) fn confirm_agent_profile_removal(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(impact) = self.agent_profile_settings.removal_confirmation.take() else {
            return;
        };
        if impact.has_blocking_references() {
            self.agent_profile_settings.removal_confirmation = Some(impact);
            return;
        }
        let Some(expected_revision) = impact.revision else {
            self.agent_profile_settings.error =
                Some("The selected agent profile no longer exists. Refresh and try again.".into());
            cx.notify();
            return;
        };
        let id = impact.profile_id;
        self.agent_profile_settings.saving = true;
        self.agent_profile_settings.error = None;
        let bridge = self.bridge.clone();
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = async {
                require_agent_profile_capabilities(
                    &bridge,
                    &[
                        (AGENT_PROFILE_REVISIONS_CAPABILITY, SAFE_EDITING_HOST_ERROR),
                        (AGENT_PROFILE_REMOVAL_CAPABILITY, REMOVAL_HOST_ERROR),
                    ],
                )
                .await?;
                bridge
                    .request_with_timeout(
                        "agentProfile.remove",
                        json!({
                            "id": id,
                            "expectedRevision": expected_revision,
                            "confirmed": true,
                        }),
                        Duration::from_secs(10),
                    )
                    .await
            }
            .await;
            let _ = this.update_in(cx, |this, window, cx| {
                this.agent_profile_settings.saving = false;
                match result {
                    Ok(_) => this.apply_removed_agent_profile(&id, window, cx),
                    Err(error) => this.agent_profile_settings.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn apply_removed_agent_profile(
        &mut self,
        id: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.settings_state.default_agent_profile_id.as_deref() == Some(id) {
            self.settings_state.default_agent_profile_id = None;
        }
        self.agent_profile_settings
            .profiles
            .retain(|profile| profile.id != id);
        if let Some(next) = self.agent_profile_settings.profiles.first().cloned() {
            self.seed_agent_profile(&next, window, cx);
        } else {
            self.new_agent_profile(window, cx);
            self.agent_profile_settings.creating_new = false;
        }
        self.agent_profile_settings.toast = None;
        self.sync_workspace_agent_profile_options();
    }
}
