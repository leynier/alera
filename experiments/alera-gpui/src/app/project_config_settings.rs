use std::collections::BTreeSet;
use std::time::Duration;

use chrono::Utc;
use gpui::{AppContext as _, Context, Entity, SharedString, Window};
use gpui_component::input::{InputState, TextareaState};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use super::project_config_request_scope::ProjectConfigRequestScope;
use super::AleraApp;

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct ProjectConfig {
    pub worktree: WorktreeSetupConfig,
    pub new_workspace: NewWorkspaceConfig,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub git_hosting_provider: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct WorktreeSetupConfig {
    pub copy: Vec<WorktreeCopyRule>,
    pub setup: Vec<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct NewWorkspaceConfig {
    pub prompt_append: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct WorktreeCopyRule {
    pub from: String,
    pub to: Option<String>,
    #[serde(default)]
    pub overwrite: bool,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EffectiveProjectConfig {
    config: ProjectConfig,
    origin: String,
    error: Option<String>,
}

pub(super) struct ProjectCopyRuleDraft {
    pub from_input: Entity<InputState>,
    pub to_input: Entity<InputState>,
    pub overwrite: bool,
}

pub(super) struct ProjectSetupCommandDraft {
    pub input: Entity<InputState>,
}

pub(super) struct ProjectConfigSettingsState {
    pub selected_project_id: Option<String>,
    pub override_project_ids: BTreeSet<String>,
    pub origin: String,
    pub source_error: Option<SharedString>,
    pub prompt_append_input: Entity<TextareaState>,
    pub copy_rules: Vec<ProjectCopyRuleDraft>,
    pub setup_commands: Vec<ProjectSetupCommandDraft>,
    pub git_hosting_provider: Option<String>,
    pub provider_dropdown_open: bool,
    pub loading: bool,
    pub saving: bool,
    pub error: Option<SharedString>,
    generation: u64,
    seed_signature: Option<String>,
    selection_epoch: u64,
    seeded_draft: Option<String>,
}

impl ProjectConfigSettingsState {
    pub fn new(window: &mut Window, cx: &mut gpui::App) -> Self {
        Self {
            selected_project_id: None,
            override_project_ids: BTreeSet::new(),
            origin: "none".into(),
            source_error: None,
            prompt_append_input: cx.new(|cx| {
                TextareaState::new(window, cx)
                    .placeholder("")
                    .soft_wrap(true)
            }),
            copy_rules: Vec::new(),
            setup_commands: Vec::new(),
            git_hosting_provider: None,
            provider_dropdown_open: false,
            loading: false,
            saving: false,
            error: None,
            generation: 0,
            seed_signature: None,
            selection_epoch: 0,
            seeded_draft: None,
        }
    }

    fn seed(
        &mut self,
        effective: EffectiveProjectConfig,
        project_id: &str,
        replace_draft: bool,
        window: &mut Window,
        cx: &mut gpui::App,
    ) {
        let signature = serde_json::to_string(&effective.config).unwrap_or_default();
        let should_seed = self.selected_project_id.as_deref() != Some(project_id)
            || self.seed_signature.as_deref() != Some(&signature);
        self.selected_project_id = Some(project_id.to_string());
        self.origin = effective.origin;
        self.source_error = effective.error.map(Into::into);
        if !should_seed || !replace_draft {
            return;
        }
        let prompt = effective.config.new_workspace.prompt_append;
        self.prompt_append_input.update(cx, |input, cx| {
            input.set_value(prompt, window, cx);
        });
        self.copy_rules = effective
            .config
            .worktree
            .copy
            .into_iter()
            .map(|rule| project_copy_rule_draft(rule, window, cx))
            .collect();
        self.setup_commands = effective
            .config
            .worktree
            .setup
            .into_iter()
            .map(|command| project_setup_command_draft(command, window, cx))
            .collect();
        self.git_hosting_provider = effective.config.git_hosting_provider;
        self.seed_signature = Some(signature);
        self.seeded_draft = Some(self.draft_signature(cx));
    }

    fn draft_signature(&self, cx: &gpui::App) -> String {
        json!({
            "prompt": self.prompt_append_input.read(cx).value().to_string(),
            "copy": self.copy_rules.iter().map(|rule| (
                rule.from_input.read(cx).value().to_string(),
                rule.to_input.read(cx).value().to_string(), rule.overwrite,
            )).collect::<Vec<_>>(),
            "setup": self.setup_commands.iter().map(|command| command.input.read(cx).value().to_string()).collect::<Vec<_>>(),
            "hosting": self.git_hosting_provider,
        }).to_string()
    }

    pub(super) fn select_project(&mut self, project_id: String) {
        if self.selected_project_id.as_deref() != Some(project_id.as_str()) {
            self.reset_selection();
            self.selected_project_id = Some(project_id);
        }
    }

    pub(super) fn reset_selection(&mut self) {
        self.selected_project_id = None;
        self.seed_signature = None;
        self.seeded_draft = None;
        self.selection_epoch = self.selection_epoch.wrapping_add(1);
        self.generation = self.generation.wrapping_add(1);
    }
}

impl AleraApp {
    pub(super) fn select_project_config(
        &mut self,
        project_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.project_config_settings.selected_project_id.as_deref() == Some(&project_id) {
            return;
        }
        self.project_config_settings.select_project(project_id);
        let selected_project_id = self.project_config_settings.selected_project_id.clone();
        self.load_automation_project_policy(selected_project_id.as_deref(), cx);
        self.project_config_settings.provider_dropdown_open = false;
        self.refresh_project_config_settings(window, cx);
    }

    pub(super) fn add_project_copy_rule(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.project_config_settings
            .copy_rules
            .push(project_copy_rule_draft(
                WorktreeCopyRule {
                    from: String::new(),
                    to: None,
                    overwrite: false,
                },
                window,
                cx,
            ));
        cx.notify();
    }

    pub(super) fn remove_project_copy_rule(&mut self, index: usize, cx: &mut Context<Self>) {
        if index < self.project_config_settings.copy_rules.len() {
            self.project_config_settings.copy_rules.remove(index);
            cx.notify();
        }
    }

    pub(super) fn toggle_project_copy_overwrite(&mut self, index: usize, cx: &mut Context<Self>) {
        if let Some(rule) = self.project_config_settings.copy_rules.get_mut(index) {
            rule.overwrite = !rule.overwrite;
            cx.notify();
        }
    }

    pub(super) fn add_project_setup_command(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.project_config_settings
            .setup_commands
            .push(project_setup_command_draft(String::new(), window, cx));
        cx.notify();
    }

    pub(super) fn remove_project_setup_command(&mut self, index: usize, cx: &mut Context<Self>) {
        if index < self.project_config_settings.setup_commands.len() {
            self.project_config_settings.setup_commands.remove(index);
            cx.notify();
        }
    }

    pub(super) fn set_project_hosting_provider(
        &mut self,
        provider: Option<String>,
        cx: &mut Context<Self>,
    ) {
        self.project_config_settings.git_hosting_provider = provider;
        self.project_config_settings.provider_dropdown_open = false;
        cx.notify();
    }

    pub(super) fn save_project_config_override(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.project_config_settings.saving {
            return;
        }
        let Some(project_id) = self.project_config_settings.selected_project_id.clone() else {
            return;
        };
        let mut copy = Vec::new();
        for rule in &self.project_config_settings.copy_rules {
            let from = rule.from_input.read(cx).value().trim().to_string();
            let to = rule.to_input.read(cx).value().trim().to_string();
            if from.is_empty() && to.is_empty() {
                continue;
            }
            if from.is_empty() {
                self.project_config_settings.error = Some("Copy Source Is Required".into());
                cx.notify();
                return;
            }
            if let Some(error) = validate_project_config_path(&from, "Copy Source") {
                self.project_config_settings.error = Some(error.into());
                cx.notify();
                return;
            }
            if !to.is_empty() {
                if let Some(error) = validate_project_config_path(&to, "Copy Destination") {
                    self.project_config_settings.error = Some(error.into());
                    cx.notify();
                    return;
                }
            }
            copy.push(WorktreeCopyRule {
                from,
                to: (!to.is_empty()).then_some(to),
                overwrite: rule.overwrite,
            });
        }
        let setup = self
            .project_config_settings
            .setup_commands
            .iter()
            .filter_map(|command| {
                let value = command.input.read(cx).value().trim().to_string();
                (!value.is_empty()).then_some(value)
            })
            .collect();
        let config = ProjectConfig {
            worktree: WorktreeSetupConfig { copy, setup },
            new_workspace: NewWorkspaceConfig {
                prompt_append: self
                    .project_config_settings
                    .prompt_append_input
                    .read(cx)
                    .value()
                    .trim()
                    .to_string(),
            },
            git_hosting_provider: self.project_config_settings.git_hosting_provider.clone(),
        };
        let payload = json!({
            "projectId": project_id,
            "config": config,
            "updatedAt": Utc::now().to_rfc3339(),
        });
        self.run_project_config_request("projectConfig.upsert", payload, window, cx);
    }

    pub(super) fn use_project_repo_file(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(project_id) = self.project_config_settings.selected_project_id.clone() else {
            return;
        };
        self.run_project_config_request(
            "projectConfig.remove",
            json!({"projectId": project_id}),
            window,
            cx,
        );
    }
}

fn project_copy_rule_draft(
    rule: WorktreeCopyRule,
    window: &mut Window,
    cx: &mut gpui::App,
) -> ProjectCopyRuleDraft {
    let from = rule.from;
    let to = rule.to.unwrap_or_default();
    let from_input = cx.new(|cx| {
        let mut input = InputState::new(window, cx).placeholder(".env");
        input.set_value(from, window, cx);
        input
    });
    let to_input = cx.new(|cx| {
        let mut input = InputState::new(window, cx).placeholder("Defaults To From");
        input.set_value(to, window, cx);
        input
    });
    ProjectCopyRuleDraft {
        from_input,
        to_input,
        overwrite: rule.overwrite,
    }
}

fn project_setup_command_draft(
    command: String,
    window: &mut Window,
    cx: &mut gpui::App,
) -> ProjectSetupCommandDraft {
    let input = cx.new(|cx| {
        let mut input = InputState::new(window, cx).placeholder("make bootstrap");
        input.set_value(command, window, cx);
        input
    });
    ProjectSetupCommandDraft { input }
}

fn validate_project_config_path(value: &str, label: &str) -> Option<String> {
    let path = std::path::Path::new(value);
    if path.is_absolute() || value.split(['/', '\\']).any(|component| component == "..") {
        Some(format!("{label} Must Stay Inside The Project"))
    } else {
        None
    }
}

include!("project_config_settings_render.rs");
include!("project_config_requests.rs");

#[cfg(all(test, feature = "gpui-tests"))]
#[path = "project_config_settings_tests.rs"]
mod tests;
