use std::collections::BTreeSet;
use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, AppContext as _, Context, InteractiveElement as _,
    ParentElement as _, Styled as _, Window,
};
use serde_json::{json, Value};

use super::dialogs::{primary_button, primary_icon_button, secondary_button};
use super::{AleraApp, NewWorkspaceStep};
use crate::icons::loading_indicator;
use crate::theme;

#[derive(Clone, Debug)]
pub(super) struct PromptWorkspaceCreation {
    pub workspace_id: String,
}

impl AleraApp {
    pub(super) fn render_workspace_prompt_actions(
        &self,
        _prompt_is_empty: bool,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        // Flutter keeps Create And Start Agent enabled with an empty prompt so
        // submission can surface the inline validation message.
        let disabled = self.workspace_creation_busy
            || self.workspace_profiles_loading
            || self.workspace_agent_profiles.is_empty();
        div()
            .flex()
            .items_center()
            .justify_end()
            .gap_2()
            .mt_4()
            .when(self.workspace_creation_busy, |row| {
                row.child(loading_indicator(16.0, theme::text_muted()))
                    .child(
                        div()
                            .ml_2()
                            .flex_1()
                            .text_sm()
                            .child(self.workspace_prompt_phase.unwrap_or("Working")),
                    )
                    .when(self.workspace_prompt_active_operation_id.is_some(), |row| {
                        row.child(
                            secondary_button("cancel-workspace-generation", "Cancel")
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        this.cancel_prompt_workspace_generation(cx);
                                    }),
                                ),
                        )
                    })
            })
            .when(
                !self.workspace_creation_busy && self.workspace_prompt_created.is_some(),
                |row| {
                    row.child(
                        secondary_button("open-created-workspace", "Open Workspace").on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(|this, _, _, cx| {
                                this.open_created_prompt_workspace(cx);
                            }),
                        ),
                    )
                    .child(
                        primary_button("retry-workspace-agent", "Retry Agent", false)
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(|this, _, window, cx| {
                                    this.retry_prompt_workspace_agent(window, cx);
                                }),
                            ),
                    )
                },
            )
            .when(
                !self.workspace_creation_busy && self.workspace_prompt_created.is_none(),
                |row| {
                    row.child(
                        primary_icon_button(
                            "create-prompt-workspace",
                            crate::icons::AleraIcon::Agent,
                            "Create And Start Agent",
                            disabled,
                        )
                        .on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(move |this, _, window, cx| {
                                if !disabled {
                                    this.create_prompt_workspace(window, cx);
                                }
                            }),
                        ),
                    )
                },
            )
    }

    pub(super) fn create_prompt_workspace(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.workspace_creation_busy {
            return;
        }
        let prompt = input_value(&self.workspace_prompt_input, cx);
        if prompt.is_empty() {
            self.error = Some("Initial Prompt Is Required".into());
            cx.notify();
            return;
        }
        let Some(project_id) = self.selected_workspace_project_id.clone() else {
            self.error = Some("Select A Project".into());
            cx.notify();
            return;
        };
        let source_branch = self
            .selected_workspace_source_branch
            .clone()
            .unwrap_or_else(|| "main".to_string());
        let Some(profile_id) = self.workspace_selected_agent_profile_id.clone() else {
            self.error = Some("Select An Agent Profile".into());
            cx.notify();
            return;
        };
        let existing_workspace_branches = self
            .selected_workspace_project()
            .into_iter()
            .flat_map(|project| &project.workspaces)
            .filter_map(|workspace| workspace.branch.clone())
            .collect::<BTreeSet<_>>();
        let parent_workspace_id = self.workspace_selected_parent_id.clone();
        let create_another = self.create_another_workspace;
        let bridge = self.bridge.clone();
        let window_handle = window.window_handle();
        self.workspace_creation_busy = true;
        self.workspace_prompt_phase = Some("Generating Workspace Identity");
        self.workspace_prompt_created = None;
        self.error = None;
        cx.notify();

        cx.spawn(async move |this, cx| {
            let mut creation = None;
            let mut collision_error = None;
            for attempt in 0..2 {
                let operation_id = format!(
                    "gpui-workspace-{}-{}-{attempt}",
                    std::process::id(),
                    chrono::Utc::now().timestamp_millis()
                );
                let identity_prompt = if attempt == 0 {
                    prompt.clone()
                } else {
                    format!(
                        "{prompt}\n\nThe previous generated workspace identity was unavailable. Generate a different workspace name and branch."
                    )
                };
                let _ = this.update(cx, |this, cx| {
                    this.workspace_prompt_phase = Some("Generating Workspace Identity");
                    this.workspace_prompt_active_operation_id = Some(operation_id.clone());
                    cx.notify();
                });
                let identity_result = bridge
                    .request_with_timeout(
                        "aiText.workspaceIdentity.generate",
                        json!({
                            "operationId": operation_id,
                            "projectId": project_id,
                            "prompt": identity_prompt,
                        }),
                        Duration::from_secs(11 * 60),
                    )
                    .await;
                let _ = this.update(cx, |this, cx| {
                    if this.workspace_prompt_active_operation_id.as_deref()
                        == Some(operation_id.as_str())
                    {
                        this.workspace_prompt_active_operation_id = None;
                    }
                    cx.notify();
                });
                let identity = match identity_result {
                    Ok(identity) => identity,
                    Err(error) => {
                        finish_prompt_workspace_error(&this, cx, error);
                        return;
                    }
                };
                let Some(branch) = identity
                    .get("branchName")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
                else {
                    finish_prompt_workspace_error(
                        &this,
                        cx,
                        "Generated Identity Omitted Branch Name".to_owned(),
                    );
                    return;
                };
                let Some(name) = identity
                    .get("workspaceName")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
                else {
                    finish_prompt_workspace_error(
                        &this,
                        cx,
                        "Generated Identity Omitted Workspace Name".to_owned(),
                    );
                    return;
                };
                let _ = this.update(cx, |this, cx| {
                    this.workspace_prompt_phase = Some("Checking Generated Branch");
                    cx.notify();
                });
                let branch_state = match bridge
                    .request(
                        "project.branches.list",
                        json!({"projectId": project_id}),
                    )
                    .await
                {
                    Ok(value) => value,
                    Err(error) => {
                        finish_prompt_workspace_error(&this, cx, error);
                        return;
                    }
                };
                let branch_exists = existing_workspace_branches.contains(&branch)
                    || branch_array(&branch_state, "branches").contains(&branch)
                    || branch_array(&branch_state, "localBranches").contains(&branch);
                if branch_exists {
                    collision_error = Some(format!(
                        "The Generated Branch \"{branch}\" Already Exists."
                    ));
                    continue;
                }
                let _ = this.update(cx, |this, cx| {
                    this.workspace_prompt_phase = Some("Creating Workspace");
                    cx.notify();
                });
                let mut create_payload = json!({
                    "projectId": project_id,
                    "branch": branch,
                    "name": name,
                    "sourceBranch": source_branch,
                    "reuseExistingBranch": false,
                    "deferSetup": true,
                });
                if let (Some(object), Some(parent_workspace_id)) =
                    (create_payload.as_object_mut(), parent_workspace_id.clone())
                {
                    object.insert(
                        "parentWorkspaceId".to_string(),
                        Value::String(parent_workspace_id),
                    );
                }
                match bridge
                    .request_with_timeout(
                        "workspace.createManaged",
                        create_payload,
                        Duration::from_secs(30 * 60),
                    )
                    .await
                {
                    Ok(payload) => {
                        creation = Some(payload);
                        break;
                    }
                    Err(error) if attempt == 0 && looks_like_collision(&error) => {
                        collision_error = Some(error);
                    }
                    Err(error) => {
                        finish_prompt_workspace_error(&this, cx, error);
                        return;
                    }
                }
            }
            let Some(creation) = creation else {
                finish_prompt_workspace_error(
                    &this,
                    cx,
                    collision_error.unwrap_or_else(|| {
                        "AI Text Could Not Generate An Available Workspace Identity.".to_owned()
                    }),
                );
                return;
            };
            let Some(workspace_id) = workspace_id_from_payload(&creation) else {
                finish_prompt_workspace_error(
                    &this,
                    cx,
                    "Workspace Creation Omitted Workspace Id".to_owned(),
                );
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.workspace_prompt_created = Some(PromptWorkspaceCreation {
                    workspace_id: workspace_id.clone(),
                });
                this.workspace_prompt_phase = Some("Starting Agent");
                cx.notify();
            });
            let launch = bridge
                .request_with_timeout(
                    "agentProfile.launch",
                    json!({
                        "workspaceId": workspace_id,
                        "profileId": profile_id,
                        "prompt": prompt,
                    }),
                    Duration::from_secs(2 * 60),
                )
                .await;
            match launch {
                Ok(launch) => finish_prompt_workspace_success(
                    &this,
                    cx,
                    window_handle,
                    workspace_id,
                    launch,
                    create_another,
                ),
                Err(error) => finish_prompt_workspace_error(&this, cx, error),
            }
        })
        .detach();
    }

    pub(super) fn cancel_prompt_workspace_generation(&mut self, cx: &mut Context<Self>) {
        let Some(operation_id) = self.workspace_prompt_active_operation_id.clone() else {
            return;
        };
        let bridge = self.bridge.clone();
        cx.spawn(async move |_, _| {
            let _ = bridge
                .request("aiText.cancel", json!({"operationId": operation_id}))
                .await;
        })
        .detach();
    }

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
        let create_another = self.create_another_workspace;
        let bridge = self.bridge.clone();
        let window_handle = window.window_handle();
        self.workspace_creation_busy = true;
        self.workspace_prompt_phase = Some("Starting Agent");
        self.error = None;
        cx.notify();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "agentProfile.launch",
                    json!({
                        "workspaceId": creation.workspace_id,
                        "profileId": profile_id,
                        "prompt": prompt,
                    }),
                    Duration::from_secs(2 * 60),
                )
                .await;
            match result {
                Ok(launch) => finish_prompt_workspace_success(
                    &this,
                    cx,
                    window_handle,
                    creation.workspace_id,
                    launch,
                    create_another,
                ),
                Err(error) => finish_prompt_workspace_error(&this, cx, error),
            }
        })
        .detach();
    }

    pub(super) fn open_created_prompt_workspace(&mut self, cx: &mut Context<Self>) {
        let Some(creation) = self.workspace_prompt_created.take() else {
            return;
        };
        self.selected_workspace_id = Some(creation.workspace_id);
        self.selected_tab_id = None;
        self.show_new_workspace_dialog = false;
        self.workspace_prompt_phase = None;
        self.error = None;
        self.refresh(cx);
    }
}

fn finish_prompt_workspace_error(
    this: &gpui::WeakEntity<AleraApp>,
    cx: &mut gpui::AsyncApp,
    error: String,
) {
    let _ = this.update(cx, |this, cx| {
        this.workspace_creation_busy = false;
        this.workspace_prompt_phase = None;
        this.workspace_prompt_active_operation_id = None;
        this.error = Some(error.into());
        cx.notify();
    });
}

fn finish_prompt_workspace_success(
    this: &gpui::WeakEntity<AleraApp>,
    cx: &mut gpui::AsyncApp,
    window_handle: gpui::AnyWindowHandle,
    workspace_id: String,
    launch: Value,
    create_another: bool,
) {
    let _ = cx.update_window(window_handle, |_, window, cx| {
        let _ = this.update(cx, |this, cx| {
            this.workspace_creation_busy = false;
            this.workspace_prompt_phase = None;
            this.workspace_prompt_active_operation_id = None;
            this.workspace_prompt_created = None;
            this.selected_workspace_id = Some(workspace_id);
            this.selected_tab_id = tab_id_from_launch(&launch);
            this.show_new_workspace_dialog = create_another;
            this.new_workspace_step = NewWorkspaceStep::Entry;
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

fn input_value(
    input: &gpui::Entity<gpui_component::input::InputState>,
    cx: &Context<AleraApp>,
) -> String {
    input.read(cx).value().trim().to_owned()
}

fn workspace_id_from_payload(payload: &Value) -> Option<String> {
    payload
        .get("workspace")
        .and_then(Value::as_object)
        .and_then(|workspace| workspace.get("id"))
        .and_then(Value::as_str)
        .map(str::to_owned)
}

fn tab_id_from_launch(launch: &Value) -> Option<String> {
    launch
        .get("tab")
        .and_then(Value::as_object)
        .and_then(|tab| tab.get("id"))
        .and_then(Value::as_str)
        .map(str::to_owned)
}

fn branch_array(value: &Value, key: &str) -> BTreeSet<String> {
    value
        .get(key)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect()
}

fn looks_like_collision(error: &str) -> bool {
    let error = error.to_lowercase();
    error.contains("already exists") || error.contains("workspace for branch")
}

#[cfg(test)]
#[path = "workspace_prompt_actions_tests.rs"]
mod tests;
