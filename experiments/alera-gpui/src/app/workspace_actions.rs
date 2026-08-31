use gpui::{Context, Entity, Window};
use gpui_component::input::InputState;
use serde_json::{json, Value};

use super::workspace_prompt_dropdown::AgentProfileOption;
use super::{AleraApp, NewWorkspaceMode, NewWorkspaceStep};

/// Deferred worktree setup that must be materialized as a visible Setup tab
/// once the newly-created workspace is present in the next snapshot.
#[derive(Clone, Debug)]
pub(super) struct PendingWorkspaceSetup {
    pub workspace_id: String,
    pub command: String,
    pub activate_tab_id: Option<String>,
}

impl AleraApp {
    pub(super) fn queue_deferred_workspace_setup(
        &mut self,
        workspace_id: String,
        command: Option<String>,
        activate_tab_id: Option<String>,
    ) {
        let Some(command) = command.map(|command| command.trim().to_owned()) else {
            return;
        };
        if command.is_empty() {
            return;
        }
        self.pending_workspace_setup = Some(PendingWorkspaceSetup {
            workspace_id,
            command,
            activate_tab_id,
        });
    }

    /// Called after a workspace snapshot is installed. The runtime returns a
    /// deferred setup command with workspace creation; GPUI must turn it into
    /// the same visible, auto-closing Setup terminal Flutter opens.
    pub(super) fn open_pending_workspace_setup(&mut self, cx: &mut Context<Self>) {
        let Some(pending) = self.pending_workspace_setup.clone() else {
            return;
        };
        if self.selected_workspace_id.as_deref() != Some(pending.workspace_id.as_str())
            || self.snapshot.workspace(&pending.workspace_id).is_none()
        {
            return;
        }
        if self.tab_mutation_busy {
            return;
        }
        if self.snapshot.tabs.iter().any(|tab| {
            tab.workspace_id == pending.workspace_id
                && tab.title == "Setup"
                && tab
                    .payload
                    .get("autoCloseOnSuccess")
                    .and_then(Value::as_bool)
                    == Some(true)
        }) {
            self.pending_workspace_setup = None;
            return;
        }
        self.pending_workspace_setup = None;
        self.open_deferred_setup_terminal(pending, cx);
    }

    fn open_deferred_setup_terminal(
        &mut self,
        pending: PendingWorkspaceSetup,
        cx: &mut Context<Self>,
    ) {
        let timestamp = chrono::Utc::now();
        let tab_id = format!(
            "gpui-setup-tab-{}-{}",
            std::process::id(),
            timestamp.timestamp_micros()
        );
        let mut layout = self.snapshot.layout.clone();
        if layout.is_none() {
            let group_id = format!("gpui-group-{}", pending.workspace_id);
            let mut groups = std::collections::BTreeMap::new();
            groups.insert(
                group_id.clone(),
                crate::model::WorkbenchPaneGroup {
                    id: group_id.clone(),
                    tab_ids: Vec::new(),
                    active_tab_id: None,
                },
            );
            layout = Some(crate::model::WorkbenchLayout {
                workspace_id: pending.workspace_id.clone(),
                root: crate::model::WorkbenchLayoutNode::Leaf {
                    group_id: group_id.clone(),
                },
                groups,
                active_group_id: group_id,
            });
        }
        if let Some(layout) = layout.as_mut() {
            layout.add_tab_to_active_group(tab_id.clone());
        }
        let bridge = self.bridge.clone();
        let workspace_id = pending.workspace_id;
        let command = pending.command;
        let activate_tab_id = pending.activate_tab_id;
        self.tab_mutation_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "tab.upsert",
                    json!({
                        "id": tab_id,
                        "workspaceId": workspace_id,
                        "kind": "terminal",
                        "title": "Setup",
                        "createdAt": timestamp.to_rfc3339(),
                        "updatedAt": timestamp.to_rfc3339(),
                        "payload": {
                            "terminalSessionId": tab_id,
                            "initialCommand": command,
                            "initialCommandOnce": true,
                            "spawnOnCreate": true,
                            "autoCloseOnSuccess": true,
                        },
                    }),
                )
                .await;
            let result = match result {
                Ok(tab) => super::tab_actions::persist_layout(&bridge, layout)
                    .await
                    .map(|_| tab),
                Err(error) => Err(error),
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(tab) => {
                        this.selected_tab_id = activate_tab_id
                            .or_else(|| tab.get("id").and_then(Value::as_str).map(str::to_owned));
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn open_new_workspace_dialog(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let project_id = self.selected_workspace_id.as_deref()
            .and_then(|workspace_id| self.snapshot.project_for_workspace(workspace_id))
            .map(|project| project.id.clone())
            .or_else(|| self.active_project_id.clone());
        self.open_new_workspace_dialog_for_project(project_id, window, cx);
    }

    pub(super) fn open_new_workspace_dialog_for_project(
        &mut self,
        project_id: Option<String>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.workspace_creation_busy {return;}
        if !self
            .snapshot
            .projects
            .iter()
            .any(|project| project.kind == "gitRepository")
        {
            self.error = Some("Add A Git Project Before Creating A Workspace".into());
            cx.notify();
            return;
        }
        let project = self.snapshot.projects.iter().find(|project| {
                project_id.as_deref() == Some(project.id.as_str()) && project.kind == "gitRepository"
            })
            .or_else(|| self.workspace_prompt_projects().into_iter().next());
        self.selected_workspace_project_id = project.map(|project| project.id.clone());
        self.selected_workspace_source_branch = Some("main".to_string());
        self.workspace_source_branches.clear();
        self.workspace_local_branches.clear();
        self.workspace_branches_loading = false;
        self.workspace_reuse_existing_branch = false;
        self.workspace_synced_name = None;
        self.new_workspace_mode = NewWorkspaceMode::FromPrompt;
        self.new_workspace_step = NewWorkspaceStep::Entry;
        self.workspace_prompt_dropdown = None;
        self.workspace_selected_parent_id = self
            .workspace_parent_options()
            .into_iter()
            .find_map(|(workspace_id, _)| workspace_id);
        self.create_another_workspace = false;
        self.workspace_prompt_phase = None;
        self.workspace_prompt_active_operation_id = None;
        self.workspace_prompt_created = None;
        self.workspace_prompt_agent_launch_mutation_id = None;
        self.workspace_prompt_original_agent_launch_idempotent = None;
        self.show_new_workspace_dialog = true;
        self.workspace_prompt_scroll_handle.set_offset(gpui::point(gpui::px(0.0), gpui::px(0.0)));
        self.workspace_prompt_input.update(cx, |input, cx| input.set_value("", window, cx));
        self.reset_manual_workspace_source(window,cx);
        for input in [&self.workspace_project_search_input,&self.workspace_branch_search_input,&self.workspace_branch_input,&self.workspace_name_input] {
            input.update(cx,|input,cx|input.set_value("",window,cx));
        }
        self.error = None;
        self.load_workspace_prompt_profiles(cx);
        if let Some(project_id) = self.selected_workspace_project_id.clone() {
            self.load_workspace_branches(project_id, cx);
        }
        let prompt_input = self.workspace_prompt_input.clone();
        window.on_next_frame(move |window, cx| {
            prompt_input.update(cx, |input, cx| input.focus(window, cx));
        });
        cx.notify();
    }

    pub(super) fn load_workspace_branches(&mut self, project_id: String, cx: &mut Context<Self>) {
        self.workspace_branches_generation=self.workspace_branches_generation.wrapping_add(1);
        let generation=self.workspace_branches_generation;
        self.workspace_branches_loading = true;
        self.workspace_source_branches.clear();
        self.workspace_local_branches.clear();
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("project.branches.list", json!({"projectId": project_id}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if !this.show_new_workspace_dialog
                    || this.workspace_branches_generation!=generation
                    || this.selected_workspace_project_id.as_deref() != Some(project_id.as_str()) {
                    return;
                }
                this.workspace_branches_loading = false;
                match result {
                    Ok(value) => {
                        this.workspace_source_branches = string_array(&value, "branches");
                        this.workspace_local_branches = string_array(&value, "localBranches");
                        let candidates = if this.workspace_reuse_existing_branch {
                            this.available_local_workspace_branches()
                        } else {
                            this.workspace_source_branches.clone()
                        };
                        this.selected_workspace_source_branch =
                            preferred_workspace_branch(&candidates);
                        this.error = None;
                    }
                    Err(error) => this.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn load_workspace_prompt_profiles(&mut self, cx: &mut Context<Self>) {
        self.workspace_profiles_generation=self.workspace_profiles_generation.wrapping_add(1);
        let generation=self.workspace_profiles_generation;
        self.workspace_profiles_loading = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("agentProfile.list", json!({})).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if !this.show_new_workspace_dialog || this.workspace_profiles_generation!=generation {return;}
                this.workspace_profiles_loading = false;
                match result.and_then(parse_agent_profile_options) {
                    Ok(profiles) => {
                        let selected = this
                            .workspace_selected_agent_profile_id
                            .clone()
                            .filter(|id| profiles.iter().any(|profile| &profile.id == id))
                            .or_else(|| {
                                this.settings_state
                                    .default_agent_profile_id
                                    .as_deref()
                                    .filter(|id| profiles.iter().any(|profile| &profile.id == id))
                                    .map(str::to_owned)
                            })
                            .or_else(|| profiles.first().map(|profile| profile.id.clone()));
                        this.workspace_agent_profiles = profiles;
                        this.workspace_selected_agent_profile_id = selected;
                    }
                    Err(error) => this.error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn select_new_workspace_mode(
        &mut self,
        mode: NewWorkspaceMode,
        cx: &mut Context<Self>,
    ) {
        if self.workspace_creation_busy {return;}
        self.new_workspace_mode = mode;
        self.workspace_prompt_scroll_handle.set_offset(gpui::point(gpui::px(0.0), gpui::px(0.0)));
        self.new_workspace_step = NewWorkspaceStep::Entry;
        self.error = None;
        cx.notify();
    }

    pub(super) fn continue_manual_workspace(&mut self, cx: &mut Context<Self>) {
        if self.workspace_creation_busy {return;}
        self.new_workspace_mode = NewWorkspaceMode::Manual;
        self.new_workspace_step = NewWorkspaceStep::ManualSelection;
        self.workspace_selected_parent_id = None;
        self.error = None;
        cx.notify();
    }

    pub(super) fn continue_manual_workspace_settings(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.manual_workspace_source_required() {
            let source = input_value(&self.workspace_manual_source_input,cx);
            self.selected_workspace_source_branch = (!source.is_empty()).then_some(source);
        }
        if self.selected_workspace_source_branch.is_none() {
            self.error = Some(if self.workspace_reuse_existing_branch {
                "Existing Branch Is Required".into()
            } else {
                "Source Branch Is Required".into()
            });
            cx.notify();
            return;
        }
        if self.workspace_reuse_existing_branch {
            let branch = self
                .selected_workspace_source_branch
                .clone()
                .unwrap_or_default();
            self.workspace_branch_input.update(cx, |input, cx| {
                input.set_value(branch.clone(), window, cx);
            });
            self.workspace_name_input.update(cx, |input, cx| {
                input.set_value(branch.clone(), window, cx);
            });
            self.workspace_synced_name = Some(branch);
        }
        self.new_workspace_step = NewWorkspaceStep::ManualSettings;
        self.error = None;
        let input=if self.workspace_reuse_existing_branch {&self.workspace_name_input} else {&self.workspace_branch_input};
        input.update(cx,|input,cx|input.focus(window,cx));
        cx.notify();
    }

    pub(super) fn back_new_workspace(&mut self, cx: &mut Context<Self>) {
        if self.workspace_creation_busy {return;}
        self.new_workspace_step = match self.new_workspace_step {
            NewWorkspaceStep::ManualSettings => NewWorkspaceStep::ManualSelection,
            NewWorkspaceStep::ManualSelection => NewWorkspaceStep::Entry,
            NewWorkspaceStep::Entry => NewWorkspaceStep::Entry,
        };
        cx.notify();
    }

    pub(super) fn select_workspace_project(&mut self, project_id: String, cx: &mut Context<Self>) {
        if self.workspace_creation_busy {return;}
        self.selected_workspace_project_id = Some(project_id.clone());
        self.selected_workspace_source_branch = None;
        self.workspace_selected_parent_id = self
            .workspace_parent_options()
            .into_iter()
            .find_map(|(workspace_id, _)| workspace_id);
        self.workspace_source_branches.clear();
        self.workspace_local_branches.clear();
        self.load_workspace_branches(project_id, cx);
        cx.notify();
    }

    pub(super) fn select_workspace_source_branch(
        &mut self,
        branch: String,
        cx: &mut Context<Self>,
    ) {
        self.selected_workspace_source_branch = Some(branch);
        cx.notify();
    }

    pub(super) fn select_manual_workspace_source_branch(
        &mut self,
        branch: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.selected_workspace_source_branch = Some(branch.clone());
        if self.workspace_reuse_existing_branch {
            self.workspace_branch_input.update(cx, |input, cx| {
                input.set_value(branch.clone(), window, cx);
            });
            self.workspace_name_input.update(cx, |input, cx| {
                input.set_value(branch.clone(), window, cx);
            });
            self.workspace_synced_name = Some(branch);
        }
        cx.notify();
    }

    pub(super) fn set_workspace_reuse_existing_branch(
        &mut self,
        reuse: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.workspace_reuse_existing_branch == reuse {
            return;
        }
        self.workspace_reuse_existing_branch = reuse;
        self.reset_manual_workspace_source(window,cx);
        let candidates = if reuse {
            self.available_local_workspace_branches()
        } else {
            self.workspace_source_branches.clone()
        };
        self.selected_workspace_source_branch = preferred_workspace_branch(&candidates);
        self.workspace_branch_search_input.update(cx, |input, cx| {
            input.set_placeholder(
                if reuse {
                    "Search Existing Branches"
                } else {
                    "Search Source Branches"
                },
                window,
                cx,
            );
            input.set_value("", window, cx);
        });
        if reuse {
            let branch = self
                .selected_workspace_source_branch
                .clone()
                .unwrap_or_default();
            self.workspace_branch_input.update(cx, |input, cx| {
                input.set_value(branch.clone(), window, cx);
            });
            self.workspace_name_input.update(cx, |input, cx| {
                input.set_value(branch.clone(), window, cx);
            });
            self.workspace_synced_name = (!branch.is_empty()).then_some(branch);
        } else {
            self.workspace_branch_input.update(cx, |input, cx| {
                input.set_value("", window, cx);
            });
            self.workspace_name_input.update(cx, |input, cx| {
                input.set_value("", window, cx);
            });
            self.workspace_synced_name = None;
        }
        self.error = None;
        if self.manual_workspace_source_required() {
            self.workspace_manual_source_input.update(cx,|input,cx|input.focus(window,cx));
        }
        cx.notify();
    }

    pub(super) fn available_local_workspace_branches(&self) -> Vec<String> {
        let used = self
            .selected_workspace_project()
            .into_iter()
            .flat_map(|project| &project.workspaces)
            .filter_map(|workspace| workspace.branch.as_deref())
            .filter(|branch| !branch.is_empty() && *branch != "HEAD")
            .collect::<std::collections::BTreeSet<_>>();
        self.workspace_local_branches
            .iter()
            .filter(|branch| !used.contains(branch.as_str()))
            .cloned()
            .collect()
    }

    pub(super) fn toggle_create_another_workspace(&mut self, cx: &mut Context<Self>) {
        if self.workspace_creation_busy {return;}
        self.create_another_workspace = !self.create_another_workspace;
        cx.notify();
    }

    pub(super) fn close_new_workspace_dialog(&mut self, cx: &mut Context<Self>) {
        if self.workspace_creation_busy {
            return;
        }
        self.show_new_workspace_dialog = false;
        self.workspace_branches_generation=self.workspace_branches_generation.wrapping_add(1);
        self.workspace_profiles_generation=self.workspace_profiles_generation.wrapping_add(1);
        self.workspace_branches_loading=false;
        self.workspace_profiles_loading=false;
        cx.notify();
    }

}

fn parse_agent_profile_options(value: Value) -> Result<Vec<AgentProfileOption>, String> {
    value
        .get("items")
        .and_then(Value::as_array)
        .ok_or_else(|| "Agent Profile List Omitted Items".to_string())?
        .iter()
        .map(|profile| {
            Ok(AgentProfileOption {
                id: profile
                    .get("id")
                    .and_then(Value::as_str)
                    .ok_or_else(|| "Agent Profile Omitted Id".to_string())?
                    .to_owned(),
                name: profile
                    .get("name")
                    .and_then(Value::as_str)
                    .ok_or_else(|| "Agent Profile Omitted Name".to_string())?
                    .to_owned(),
            })
        })
        .collect()
}

fn input_value(input: &Entity<InputState>, cx: &Context<AleraApp>) -> String {
    input.read(cx).value().trim().to_string()
}

pub(super) fn deferred_setup_command_from_payload(payload: &Value) -> Option<String> {
    payload
        .get("deferredSetupCommand")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|command| !command.is_empty())
        .map(str::to_owned)
}

fn string_array(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect()
}

fn preferred_workspace_branch(branches: &[String]) -> Option<String> {
    ["main", "origin/main", "master", "origin/master"]
        .into_iter()
        .find(|preferred| branches.iter().any(|branch| branch == preferred))
        .map(str::to_owned)
        .or_else(|| branches.first().cloned())
}

#[cfg(test)]
#[path = "workspace_actions_tests.rs"]
mod tests;
