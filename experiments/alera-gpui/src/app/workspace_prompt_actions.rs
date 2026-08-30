use std::collections::BTreeSet;
use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, ClipboardEntry, Context, ParentElement as _,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::Paste;
use serde_json::{json, Value};

use super::app_helpers::flutter_state_error;
use super::dialogs::{primary_button, primary_icon_button, secondary_button};
use super::workspace_actions::deferred_setup_command_from_payload;
use super::workspace_prompt_agent_launch::{
    finish_prompt_workspace_success, launch_agent_profile, AgentProfileLaunchError,
};
use super::AleraApp;
use crate::icons::loading_indicator;
use crate::theme;

#[derive(Clone, Debug)]
pub(super) struct PromptWorkspaceCreation {
    pub workspace_id: String,
    pub deferred_setup_command: Option<String>,
}

impl AleraApp {
    /// Intercept image-only paste in the prompt field while preserving normal
    /// text paste for the input component's built-in action.
    pub(super) fn on_prompt_paste(
        &mut self,
        _: &Paste,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(clipboard) = cx.read_from_clipboard() else {
            cx.propagate();
            return;
        };
        if clipboard.text().is_some() {
            cx.propagate();
            return;
        }
        let Some(image) = clipboard.entries().iter().find_map(|entry| match entry {
            ClipboardEntry::Image(image) => Some(image),
            ClipboardEntry::String(_) | ClipboardEntry::ExternalPaths(_) => None,
        }) else {
            cx.propagate();
            return;
        };
        match save_prompt_clipboard_image(image) {
            Ok(path) => self.workspace_prompt_input.update(cx, |input, cx| {
                input.insert(path, window, cx);
            }),
            Err(error) => {
                self.error = Some(error.into());
                cx.notify();
            }
        }
        cx.stop_propagation();
    }

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
                            .text_size(crate::theme::body_size())
                            .child(self.workspace_prompt_phase.unwrap_or("Working")),
                    )
                    .when(self.workspace_prompt_active_operation_id.is_some(), |row| {
                        row.child(
                            secondary_button("cancel-workspace-generation", "Cancel").on_click(
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
                        secondary_button("open-created-workspace", "Open Workspace").on_click(
                            cx.listener(|this, _, _, cx| {
                                this.open_created_prompt_workspace(cx);
                            }),
                        ),
                    )
                    .child(
                        primary_button("retry-workspace-agent", "Retry Agent", false).on_click(
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
                        .on_click(cx.listener(
                            move |this, _, window, cx| {
                                if !disabled {
                                    this.create_prompt_workspace(window, cx);
                                }
                            },
                        )),
                    )
                },
            )
    }

    pub(super) fn create_prompt_workspace(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.workspace_creation_busy {
            return;
        }
        let prompt = input_value(&self.workspace_prompt_input, cx);
        let selections = self
            .selected_workspace_project_id
            .clone()
            .zip(self.selected_workspace_source_branch.clone())
            .zip(self.workspace_selected_agent_profile_id.clone());
        let Some(((project_id, source_branch), profile_id)) =
            selections.filter(|_| !prompt.is_empty())
        else {
            self.error = Some("Complete The Prompt, Project, Branch, And Agent Profile.".into());
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
        self.workspace_prompt_agent_launch_mutation_id = None;
        self.workspace_prompt_original_agent_launch_idempotent = None;
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
                        finish_prompt_workspace_error(&this, cx, flutter_state_error(error));
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
                        "FormatException: Runtime response is missing \"branchName\".".to_owned(),
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
                        "FormatException: Runtime response is missing \"workspaceName\"."
                            .to_owned(),
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
                        finish_prompt_workspace_error(&this, cx, flutter_state_error(error));
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
                        finish_prompt_workspace_error(&this, cx, flutter_state_error(error));
                        return;
                    }
                }
            }
            let Some(creation) = creation else {
                finish_prompt_workspace_error(
                    &this,
                    cx,
                    flutter_state_error(collision_error.unwrap_or_else(|| {
                        "AI Assist could not generate an available workspace identity.".to_owned()
                    })),
                );
                return;
            };
            let Some(workspace_id) = workspace_id_from_payload(&creation) else {
                finish_prompt_workspace_error(
                    &this,
                    cx,
                    "FormatException: Runtime response must be a JSON object.".to_owned(),
                );
                return;
            };
            let deferred_setup_command = deferred_setup_command_from_payload(&creation);
            let client_mutation_id = uuid::Uuid::new_v4().to_string();
            let _ = this.update(cx, |this, cx| {
                this.workspace_prompt_created = Some(PromptWorkspaceCreation {
                    workspace_id: workspace_id.clone(),
                    deferred_setup_command: deferred_setup_command.clone(),
                });
                this.workspace_prompt_agent_launch_mutation_id =
                    Some(client_mutation_id.clone());
                this.workspace_prompt_original_agent_launch_idempotent = Some(true);
                this.workspace_prompt_phase = Some("Starting Agent");
                cx.notify();
            });
            let launch = launch_agent_profile(
                &bridge,
                json!({
                    "workspaceId": workspace_id,
                    "profileId": profile_id,
                    "prompt": prompt,
                    "clientMutationId": client_mutation_id,
                }),
                false,
            )
            .await;
            match launch {
                Ok(launch) => {
                    let _ = this.update(cx, |this, cx| {
                        this.workspace_prompt_original_agent_launch_idempotent =
                            Some(launch.idempotent);
                        cx.notify();
                    });
                    finish_prompt_workspace_success(
                        &this,
                        cx,
                        window_handle,
                        workspace_id,
                        launch.payload,
                        deferred_setup_command,
                        create_another,
                    );
                }
                Err(error) => {
                    if matches!(&error, AgentProfileLaunchError::NonIdempotent(_)) {
                        let _ = this.update(cx, |this, cx| {
                            this.workspace_prompt_original_agent_launch_idempotent = Some(false);
                            cx.notify();
                        });
                    }
                    finish_prompt_workspace_error(
                        &this,
                        cx,
                        flutter_state_error(error.message()),
                    )
                }
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

    pub(super) fn open_created_prompt_workspace(&mut self, cx: &mut Context<Self>) {
        let Some(creation) = self.workspace_prompt_created.take() else {
            return;
        };
        self.queue_deferred_workspace_setup(
            creation.workspace_id.clone(),
            creation.deferred_setup_command,
            None,
        );
        self.selected_workspace_id = Some(creation.workspace_id);
        self.selected_tab_id = None;
        self.show_new_workspace_dialog = false;
        self.workspace_prompt_phase = None;
        self.workspace_prompt_agent_launch_mutation_id = None;
        self.workspace_prompt_original_agent_launch_idempotent = None;
        self.error = None;
        self.refresh(cx);
    }
}

pub(super) fn finish_prompt_workspace_error(
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

pub(super) fn input_value(
    input: &gpui::Entity<gpui_component::input::TextareaState>,
    cx: &Context<AleraApp>,
) -> String {
    input.read(cx).value().trim().to_owned()
}

pub(super) fn save_prompt_clipboard_image(image: &gpui::Image) -> Result<String, String> {
    use std::io::Write as _;

    let decoded = image::load_from_memory(&image.bytes)
        .map_err(|error| format!("Could Not Paste Clipboard Image: {error}"))?;
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|error| format!("Could Not Paste Clipboard Image: {error}"))?
        .as_nanos();
    let path = std::env::temp_dir().join(format!("alera-paste-{}-{nonce}.png", std::process::id()));
    let file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .map_err(|error| format!("Could Not Paste Clipboard Image: {error}"))?;
    let mut writer = std::io::BufWriter::new(file);
    decoded
        .write_to(&mut writer, image::ImageFormat::Png)
        .map_err(|error| format!("Could Not Paste Clipboard Image: {error}"))?;
    writer
        .flush()
        .map_err(|error| format!("Could Not Paste Clipboard Image: {error}"))?;
    Ok(path.to_string_lossy().replace('\x1b', "␛"))
}

fn workspace_id_from_payload(payload: &Value) -> Option<String> {
    payload
        .get("workspace")
        .and_then(Value::as_object)
        .and_then(|workspace| workspace.get("id"))
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
