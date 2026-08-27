use gpui::{
    deferred, div, prelude::FluentBuilder as _, px, AnyElement, CursorStyle, InteractiveElement as _,
    IntoElement as _, MouseButton, ParentElement as _, Styled as _,
};

use super::sidebar_view_options::compare_project_selection;
use crate::{
    design_system,
    icons::{icon, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_project_config_settings_pane(
        &self,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        if self.snapshot.projects.is_empty() {
            return project_config_empty_state(
                AleraIcon::FolderOff,
                "No Projects",
                "Add A Project Before Configuring Workspace Setup.",
            )
            .into_any_element();
        }
        let mut projects = self.snapshot.projects.iter().collect::<Vec<_>>();
        projects.sort_by(compare_project_selection);
        let selected_id = self
            .project_config_settings
            .selected_project_id
            .as_deref()
            .or_else(|| projects.first().map(|project| project.id.as_str()));
        let Some(project) = selected_id
            .and_then(|id| projects.iter().find(|project| project.id == id).copied())
        else {
            return project_config_empty_state(
                AleraIcon::Folder,
                "Loading Project",
                "Reading Effective Project Configuration.",
            )
            .into_any_element();
        };
        if self.project_config_settings.loading
            && self.project_config_settings.seed_signature.is_none()
        {
            return project_config_empty_state(
                AleraIcon::Loading,
                "Loading Project",
                "Reading Effective Project Configuration.",
            )
            .into_any_element();
        }
        let source_label = match self.project_config_settings.origin.as_str() {
            "uiOverride" => "UI Override",
            "repoFile" => "Repo File",
            "repoFileError" => "Repo File Error",
            _ => "None",
        };
        div()
            .relative()
            .flex()
            .flex_1()
            .min_h_0()
            // The Flutter resource panes keep an additional 8 px inset inside
            // the shared SettingsContent padding.
            .ml(px(8.0))
            .child(self.render_project_config_master(project.id.as_str(), &projects, cx))
            .child(
                div()
                    .mx_4()
                    .w(px(1.0))
                    .h_full()
                    .bg(theme::border_subtle()),
            )
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .flex()
                    .flex_col()
                    .gap_4()
                    .child(project_config_group(
                        project.name.clone(),
                        "UI Overrides Take Precedence Over Repo Files.",
                        vec![project_config_row_width(
                            "Config Source",
                            project.repo_path.clone(),
                            150.0,
                            project_config_source_badge(source_label),
                        )],
                    ))
                    .when_some(
                        self.project_config_settings.source_error.clone(),
                        |detail, error| {
                            detail.child(
                                div()
                                    .text_size(px(12.0))
                                    .text_color(theme::danger())
                                    .child(error),
                            )
                        },
                    )
                    .child(project_config_group(
                        "New Workspace",
                        "Project Instructions Appended To Prompts That Start An Agent.",
                        vec![div().p_4().child(project_prompt_append_input(
                            &self.project_config_settings.prompt_append_input,
                        ))],
                    ))
                    .child(self.render_project_hosting_provider(cx))
                    .child(self.render_project_copy_rules(cx))
                    .child(self.render_project_setup_commands(cx))
                    .when_some(
                        self.project_config_settings.error.clone(),
                        |detail, error| {
                            detail.child(
                                div()
                                    .text_size(px(12.0))
                                    .text_color(theme::danger())
                                    .child(error),
                            )
                        },
                    )
                    .child(self.render_project_config_actions(cx)),
            )
            .into_any_element()
    }

    fn render_project_config_master(
        &self,
        selected_id: &str,
        projects: &[&crate::model::Project],
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        div()
            .w(px(244.0))
            .flex_shrink_0()
            .child(
                div()
                    .mb_2()
                    .ml_1()
                    .text_size(px(13.0))
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Projects"),
            )
            .child(
                div()
                    .overflow_hidden()
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface_selected())
                    .children(
                        projects
                            .iter()
                            .enumerate()
                            .map(|(index, project)| {
                                let id = project.id.clone();
                                let selected = project.id == selected_id;
                                let source = if self
                                    .project_config_settings
                                    .override_project_ids
                                    .contains(&project.id)
                                {
                                    "UI Override"
                                } else {
                                    "Repo File"
                                };
                                div()
                                    .id(("project-config-project", index))
                                    .flex()
                                    .items_center()
                                    .p_3()
                                    .gap_2()
                                    .border_b_1()
                                    .border_color(theme::border_subtle())
                                    .when(selected, |row| row.bg(theme::accent_subtle()))
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(move |this, _, window, cx| {
                                            this.select_project_config(id.clone(), window, cx);
                                        }),
                                    )
                                    .child(icon(
                                        AleraIcon::FolderSpecial,
                                        16.0,
                                        if selected {
                                            theme::accent()
                                        } else {
                                            theme::text_muted()
                                        },
                                    ))
                                    .child(
                                        div()
                                            .min_w_0()
                                            .child(
                                                div()
                                                    .text_size(px(13.0))
                                                    .font_weight(gpui::FontWeight::MEDIUM)
                                                    .child(project.name.clone()),
                                            )
                                            .child(
                                                div()
                                                    .mt(px(2.0))
                                                    .text_size(px(10.0))
                                                    .text_color(theme::text_muted())
                                                    .child(source),
                                            ),
                                    )
                            }),
                    ),
            )
    }

    fn render_project_hosting_provider(&self, cx: &mut Context<Self>) -> gpui::Div {
        let current = provider_label(
            self.project_config_settings
                .git_hosting_provider
                .as_deref(),
        );
        project_config_group(
            "Pull Requests",
            "Git Hosting Provider Used For Pull Requests And Checks.",
            vec![project_config_row(
                "Hosting Provider",
                "Auto-Detect Uses Public Hosts. Select GitHub For GitHub Enterprise Server.",
                div()
                    .relative()
                    .w(px(220.0))
                    .child(
                        design_system::dropdown_trigger(
                            "project-hosting-provider",
                            current,
                            self.project_config_settings.provider_dropdown_open,
                            true,
                        )
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(|this, _, _, cx| {
                                this.project_config_settings.provider_dropdown_open =
                                    !this.project_config_settings.provider_dropdown_open;
                                cx.notify();
                            }),
                        ),
                    )
                    .when(
                        self.project_config_settings.provider_dropdown_open,
                        |control| control.child(self.render_project_provider_dropdown(cx)),
                    ),
            )],
        )
    }

    fn render_project_provider_dropdown(&self, cx: &mut Context<Self>) -> AnyElement {
        deferred(
            div()
                .id("project-provider-dropdown")
                .absolute()
                .top(px(38.0))
                .right_0()
                .w(px(220.0))
                .occlude()
                .rounded_lg()
                .border_1()
                .border_color(theme::border())
                .bg(theme::surface_raised())
                .shadow_lg()
                .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                    this.project_config_settings.provider_dropdown_open = false;
                    cx.notify();
                }))
                .children(
                [
                    (None, "Auto-Detect"),
                    (Some("github"), "GitHub"),
                    (Some("azureDevops"), "Azure DevOps"),
                    (Some("gitlab"), "GitLab"),
                ]
                .into_iter()
                .enumerate()
                    .map(|(index, (provider, label))| {
                        let value = provider.map(str::to_string);
                        let selected = self.project_config_settings.git_hosting_provider == value;
                        design_system::menu_item(
                            label,
                            None,
                            selected,
                            false,
                            true,
                            None,
                        )
                        .id(("project-provider-option", index))
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _, _, cx| {
                                this.set_project_hosting_provider(value.clone(), cx);
                            }),
                        )
                    }),
                ),
        )
        .into_any_element()
    }

    fn render_project_copy_rules(&self, cx: &mut Context<Self>) -> gpui::Div {
        let mut rows = self
            .project_config_settings
            .copy_rules
            .iter()
            .enumerate()
            .map(|(index, rule)| {
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .p_4()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(project_labeled_input("From", &rule.from_input))
                    .child(project_labeled_input("To", &rule.to_input))
                    .child(project_checkbox(
                        ("project-copy-overwrite", index),
                        rule.overwrite,
                    )
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            this.toggle_project_copy_overwrite(index, cx);
                        }),
                    ))
                    .child(
                        project_icon_button(
                            ("project-copy-delete", index),
                            AleraIcon::Delete,
                            theme::text_muted(),
                        )
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _, _, cx| {
                                this.remove_project_copy_rule(index, cx);
                            }),
                        ),
                    )
            })
            .collect::<Vec<_>>();
        if rows.is_empty() {
            rows.push(project_empty_row("No Copy Rules"));
        }
        rows.push(
            div().flex().p_4().child(
                project_outline_button("project-copy-add", AleraIcon::Add, "Add Copy Rule")
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, window, cx| {
                            this.add_project_copy_rule(window, cx);
                        }),
                    ),
            ),
        );
        project_config_group(
            "Copy Rules",
            "Files And Directories Copied From The Main Worktree.",
            rows,
        )
    }

    fn render_project_setup_commands(&self, cx: &mut Context<Self>) -> gpui::Div {
        let mut rows = self
            .project_config_settings
            .setup_commands
            .iter()
            .enumerate()
            .map(|(index, command)| {
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .p_4()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(project_labeled_input("Command", &command.input))
                    .child(
                        project_icon_button(
                            ("project-command-delete", index),
                            AleraIcon::Delete,
                            theme::text_muted(),
                        )
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _, _, cx| {
                                this.remove_project_setup_command(index, cx);
                            }),
                        ),
                    )
            })
            .collect::<Vec<_>>();
        if rows.is_empty() {
            rows.push(project_empty_row("No Setup Commands"));
        }
        rows.push(
            div().flex().p_4().child(
                project_outline_button("project-command-add", AleraIcon::Add, "Add Setup Command")
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, window, cx| {
                            this.add_project_setup_command(window, cx);
                        }),
                    ),
            ),
        );
        project_config_group(
            "Setup Commands",
            "Commands Run From The New Linked Workspace.",
            rows,
        )
    }

    fn render_project_config_actions(&self, cx: &mut Context<Self>) -> gpui::Div {
        let has_override = self
            .project_config_settings
            .selected_project_id
            .as_ref()
            .is_some_and(|id| {
                self.project_config_settings
                    .override_project_ids
                    .contains(id)
            });
        div()
            .flex()
            .justify_end()
            .gap_2()
            .pb_2()
            .when(has_override, |actions| {
                actions.child(
                    project_action_button(
                        "project-use-repo",
                        None,
                        "Use Repo File",
                        false,
                    )
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, window, cx| {
                            this.use_project_repo_file(window, cx);
                        }),
                    ),
                )
            })
            .child(
                project_action_button(
                    "project-save-override",
                    Some(if self.project_config_settings.saving {
                        AleraIcon::Loading
                    } else {
                        AleraIcon::Save
                    }),
                    if self.project_config_settings.saving {
                        "Saving"
                    } else {
                        "Save Override"
                    },
                    true,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(|this, _, window, cx| {
                        this.save_project_config_override(window, cx);
                    }),
                ),
            )
    }
}

include!("project_config_settings_components.rs");
