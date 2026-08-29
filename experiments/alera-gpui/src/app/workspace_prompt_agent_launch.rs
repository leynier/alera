use std::time::Duration;

use gpui::{AppContext as _, Context, Window};
use serde_json::{json, Value};

use super::app_helpers::flutter_state_error;
use super::workspace_prompt_actions::{finish_prompt_workspace_error, input_value};
use super::AleraApp;
use crate::runtime_bridge::RuntimeBridge;

const AGENT_PROFILE_LAUNCH_IDEMPOTENCY_CAPABILITY: &str =
    "agentProfileLaunchIdempotencyV1";
const UNKNOWN_IDEMPOTENT_LAUNCH_REQUEST: &str =
    "Unknown terminal host request: agentProfile.launchIdempotent";

pub(super) struct AgentProfileLaunchResult {
    pub(super) payload: Value,
    pub(super) idempotent: bool,
}

pub(super) enum AgentProfileLaunchError {
    Request(String),
    NonIdempotent(String),
}

impl AgentProfileLaunchError {
    pub(super) fn message(&self) -> String {
        match self {
            Self::Request(error) | Self::NonIdempotent(error) => error.clone(),
        }
    }
}

impl AleraApp {
    pub(super) fn retry_prompt_workspace_agent(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.workspace_creation_busy {
            return;
        }
        let Some(creation) = self.workspace_prompt_created.clone() else {
            return;
        };
        let Some(profile_id) = self.workspace_selected_agent_profile_id.clone() else {
            self.error = Some("Select An Agent Profile".into());
            cx.notify();
            return;
        };
        let prompt = input_value(&self.workspace_prompt_input, cx);
        let mutation_id = self.workspace_prompt_agent_launch_mutation_id.clone();
        let original_was_idempotent = self.workspace_prompt_original_agent_launch_idempotent;
        let create_another = self.create_another_workspace;
        let bridge = self.bridge.clone();
        let window_handle = window.window_handle();
        self.workspace_creation_busy = true;
        self.workspace_prompt_phase = Some("Starting Agent");
        self.error = None;
        cx.notify();
        cx.spawn(async move |this, cx| {
            let host_supports_idempotency = supports_idempotent_agent_launch(&bridge).await;
            if original_was_idempotent != Some(true) || !host_supports_idempotency {
                finish_prompt_workspace_error(
                    &this,
                    cx,
                    "Unsupported operation: Update Alera on this host before retrying agent launch safely."
                        .to_owned(),
                );
                return;
            }
            let Some(mutation_id) = mutation_id else {
                finish_prompt_workspace_error(
                    &this,
                    cx,
                    flutter_state_error("The original agent launch identity is unavailable."),
                );
                return;
            };
            let result = launch_agent_profile(
                &bridge,
                json!({
                    "workspaceId": creation.workspace_id,
                    "profileId": profile_id,
                    "prompt": prompt,
                    "clientMutationId": mutation_id,
                }),
                true,
            )
            .await;
            match result {
                Ok(launch) => finish_prompt_workspace_success(
                    &this,
                    cx,
                    window_handle,
                    creation.workspace_id,
                    launch.payload,
                    creation.deferred_setup_command.clone(),
                    create_another,
                ),
                Err(error) => {
                    finish_prompt_workspace_error(&this, cx, flutter_state_error(error.message()))
                }
            }
        })
        .detach();
    }
}

pub(super) async fn launch_agent_profile(
    bridge: &RuntimeBridge,
    payload: Value,
    require_idempotency: bool,
) -> Result<AgentProfileLaunchResult, AgentProfileLaunchError> {
    match bridge
        .request_with_timeout(
            "agentProfile.launchIdempotent",
            payload.clone(),
            Duration::from_secs(2 * 60),
        )
        .await
    {
        Ok(payload) => Ok(AgentProfileLaunchResult {
            payload,
            idempotent: true,
        }),
        Err(error) if !require_idempotency && is_unknown_idempotent_launch_request(&error) =>
        {
            bridge
                .request_with_timeout(
                    "agentProfile.launch",
                    payload,
                    Duration::from_secs(2 * 60),
                )
                .await
                .map(|payload| AgentProfileLaunchResult {
                    payload,
                    idempotent: false,
                })
                .map_err(AgentProfileLaunchError::NonIdempotent)
        }
        Err(error) => Err(AgentProfileLaunchError::Request(error)),
    }
}

fn is_unknown_idempotent_launch_request(error: &str) -> bool {
    error
        .trim()
        .trim_end_matches('.')
        .ends_with(UNKNOWN_IDEMPOTENT_LAUNCH_REQUEST)
}

async fn supports_idempotent_agent_launch(bridge: &RuntimeBridge) -> bool {
    bridge
        .request("status.get", json!({}))
        .await
        .ok()
        .and_then(|status| status.get("runtimeCapabilities").cloned())
        .and_then(|capabilities| capabilities.as_array().cloned())
        .is_some_and(|capabilities| {
            capabilities.iter().any(|capability| {
                capability.as_str() == Some(AGENT_PROFILE_LAUNCH_IDEMPOTENCY_CAPABILITY)
            })
        })
}

pub(super) fn finish_prompt_workspace_success(
    this: &gpui::WeakEntity<AleraApp>,
    cx: &mut gpui::AsyncApp,
    window_handle: gpui::AnyWindowHandle,
    workspace_id: String,
    launch: Value,
    deferred_setup_command: Option<String>,
    create_another: bool,
) {
    let _ = cx.update_window(window_handle, |_, window, cx| {
        let _ = this.update(cx, |this, cx| {
            this.workspace_creation_busy = false;
            this.workspace_prompt_phase = None;
            this.workspace_prompt_active_operation_id = None;
            this.workspace_prompt_created = None;
            this.workspace_prompt_agent_launch_mutation_id = None;
            this.workspace_prompt_original_agent_launch_idempotent = None;
            let agent_tab_id = tab_id_from_launch(&launch);
            this.selected_tab_id = agent_tab_id.clone();
            this.queue_deferred_workspace_setup(
                workspace_id.clone(),
                deferred_setup_command,
                agent_tab_id,
            );
            this.selected_workspace_id = Some(workspace_id);
            this.show_new_workspace_dialog = create_another;
            this.new_workspace_step = super::NewWorkspaceStep::Entry;
            this.workspace_prompt_dropdown = None;
            this.error = None;
            if create_another {
                this.workspace_prompt_input
                    .update(cx, |input, cx| input.set_value("", window, cx));
                this.workspace_selected_parent_id = None;
            }
            this.refresh(cx);
        });
    });
}

fn tab_id_from_launch(launch: &Value) -> Option<String> {
    launch
        .get("tab")
        .and_then(Value::as_object)
        .and_then(|tab| tab.get("id"))
        .and_then(Value::as_str)
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::is_unknown_idempotent_launch_request;

    #[test]
    fn legacy_fallback_matches_only_the_unknown_idempotent_request() {
        assert!(is_unknown_idempotent_launch_request(
            "Unknown terminal host request: agentProfile.launchIdempotent"
        ));
        assert!(is_unknown_idempotent_launch_request(
            "Bad state: Unknown terminal host request: agentProfile.launchIdempotent."
        ));
        assert!(!is_unknown_idempotent_launch_request(
            "Runtime connection closed before replying."
        ));
    }
}
