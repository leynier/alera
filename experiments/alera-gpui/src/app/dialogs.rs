use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _, Toggled,
};

use super::workspace_prompt_dropdown::WorkspacePromptDropdown;
use super::{AleraApp, NewWorkspaceMode, NewWorkspaceStep};
use crate::design_system;
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_new_workspace_dialog(&self, window: &gpui::Window, cx: &mut Context<Self>) -> impl IntoElement {
        let dialog = match self.new_workspace_step {
            NewWorkspaceStep::Entry => self.render_workspace_entry(window, cx),
            NewWorkspaceStep::ManualSelection => self.render_workspace_selection(cx),
            NewWorkspaceStep::ManualSettings => self.render_workspace_settings(cx),
        };
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(dialog)
    }

    fn render_workspace_entry(&self, window: &gpui::Window, cx: &mut Context<Self>) -> AnyElement {
        let prompt_mode = self.new_workspace_mode == NewWorkspaceMode::FromPrompt;
        let project_label = self
            .selected_workspace_project()
            .map(|project| project.name.clone())
            .unwrap_or_else(|| "Select Project".to_string());
        let source_branch = self
            .workspace_branches_loading
            .then(|| "Loading branches".to_owned())
            .or_else(|| self.selected_workspace_source_branch.clone())
            .unwrap_or_else(|| "Select Branch".to_string());
        let parent_workspace = self.workspace_parent_label();
        let agent_profile = self.workspace_agent_profile_label();
        let prompt_is_empty = self
            .workspace_prompt_input
            .read(cx)
            .value()
            .trim()
            .is_empty();

        div()
            .id("new-workspace-dialog")
            .role(Role::Dialog)
            .aria_label("New Workspace")
            .w(px(620.0).min((window.viewport_size().width - px(64.0)).max(px(100.0))))
            .max_h(px(720.0).min((window.viewport_size().height - px(64.0)).max(px(100.0))))
            .flex()
            .flex_col()
            .rounded(px(12.0))
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface())
            .shadow_lg()
            // Flutter's shape border paints inside its padding box.
            .p(px(19.0))
            .child(self.workspace_dialog_header("New Workspace", None, false, cx))
            .child(
                div()
                    .flex()
                    .mt_4()
                    .w(px(266.0))
                    .h(px(30.0))
                    .flex_shrink_0()
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border())
                    .child(self.workspace_mode_button(
                        "workspace-from-prompt",
                        AleraIcon::Agent,
                        "From Prompt",
                        NewWorkspaceMode::FromPrompt,
                        cx,
                    ))
                    .child(self.workspace_mode_button(
                        "workspace-manual",
                        AleraIcon::GitBranch,
                        "Manual",
                        NewWorkspaceMode::Manual,
                        cx,
                    )),
            )
            .when(prompt_mode, |dialog| {
                dialog.child(super::workspace_prompt_layout::prompt_form(div().flex_shrink_0()
                    .child(
                        div()
                            .capture_action(cx.listener(Self::on_prompt_paste))
                            .child(
                                design_system::AleraTextArea::new(&self.workspace_prompt_input, "Initial Prompt")
                                    .disabled(
                                        self.workspace_creation_busy
                                            || self.workspace_prompt_created.is_some(),
                                    ),
                            ),
                    )
                    .child(prompt_form_label("Project").mt(px(16.0)))
                    .child(self.workspace_prompt_select_field(
                        "prompt-workspace-project",
                        project_label,
                        WorkspacePromptDropdown::Project,
                        cx,
                    ))
                    .child(prompt_form_label("Source Branch"))
                    .child(self.workspace_prompt_select_field(
                        "prompt-workspace-source-branch",
                        source_branch,
                        WorkspacePromptDropdown::SourceBranch,
                        cx,
                    ))
                    .child(prompt_form_label("Parent Workspace"))
                    .child(self.workspace_prompt_select_field(
                        "prompt-workspace-parent",
                        parent_workspace,
                        WorkspacePromptDropdown::ParentWorkspace,
                        cx,
                    ))
                    .child(prompt_form_label("Agent Profile"))
                    .child(self.workspace_prompt_select_field(
                        "prompt-workspace-agent-profile",
                        agent_profile,
                        WorkspacePromptDropdown::AgentProfile,
                        cx,
                    ))
                    .when_some(self.error.clone(), |dialog, error| {
                        let alert_label = error.clone();
                        dialog.child(
                            div()
                                .id("prompt-workspace-error")
                                .role(Role::Alert)
                                .aria_label(alert_label)
                                .mt_4()
                                .text_size(crate::theme::body_size())
                                .text_color(theme::danger())
                                .child(error),
                        )
                    })
                    .child(
                        div()
                            .id("create-another-prompt-workspace")
                            .focusable()
                            .tab_stop(
                                !self.workspace_creation_busy
                                    && self.workspace_prompt_created.is_none(),
                            )
                            .role(Role::CheckBox)
                            .aria_label("Create Another")
                            .aria_toggled(if self.create_another_workspace {
                                Toggled::True
                            } else {
                                Toggled::False
                            })
                            .flex()
                            .items_center()
                            .gap_2()
                            .mt(px(12.0))
                            .when(
                                !self.workspace_creation_busy
                                    && self.workspace_prompt_created.is_none(),
                                |row| {
                                    row.cursor(CursorStyle::PointingHand).on_click(
                                        cx.listener(|this, _, _, cx| {
                                            this.toggle_create_another_workspace(cx);
                                        }),
                                    )
                                },
                            )
                            .child(design_system::checkbox(
                                self.create_another_workspace,
                                !self.workspace_creation_busy
                                    && self.workspace_prompt_created.is_none(),
                                Some("Create Another".into()),
                            )),
                    )
                    .child(self.render_workspace_prompt_actions(prompt_is_empty, cx)), &self.workspace_prompt_scroll_handle))
            })
            .when(!prompt_mode, |dialog| {
                dialog
                    .child(
                        div()
                            .mt_5()
                            .text_size(crate::theme::body_size())
                            .text_color(theme::text_muted())
                            .child(
                                "Choose every workspace setting yourself, including the branch name and optional parent workspace.",
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .mt(px(24.0))
                            .child(
                                primary_button(
                                    "continue-manual-workspace",
                                    "Continue Manually",
                                    false,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.continue_manual_workspace(cx);
                                })),
                            ),
                    )
            })
            .when(!prompt_mode, |dialog| {
                dialog.when_some(self.error.clone(), |dialog, error| {
                    let alert_label = error.clone();
                    dialog.child(
                        div()
                            .id("manual-workspace-error")
                            .role(Role::Alert)
                            .aria_label(alert_label)
                            .mt_3()
                            .text_size(crate::theme::body_size())
                            .text_color(theme::danger())
                            .child(error),
                    )
                })
            })
            .into_any_element()
    }

    pub(super) fn workspace_dialog_header(
        &self,
        title: &'static str,
        step: Option<&'static str>,
        back: bool,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        div()
            .flex()
            .items_center()
            .h(px(40.0))
            .flex_shrink_0()
            .when(back, |header| {
                header.child(
                    div()
                        .id("workspace-header-back")
                        .focusable()
                        .tab_stop(true)
                        .role(Role::Button)
                        .aria_label("Back")
                        .mr_2()
                        .cursor(CursorStyle::PointingHand)
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.back_new_workspace(cx);
                        }))
                        .child(icon(AleraIcon::Back, 16.0, theme::text_muted())),
                )
            })
            .child(
                div()
                    .mr_2()
                    .text_size(crate::theme::title_size())
                    .text_color(theme::accent())
                    .child(icon(AleraIcon::GitFork, 24.0, theme::accent())),
            )
            .child(
                div()
                    .text_size(px(14.0))
                    .font_weight(gpui::FontWeight::BOLD)
                    .child(title),
            )
            .child(div().flex_1())
            .when_some(step, |header, step| {
                header.child(div().text_size(crate::theme::caption_size()).text_color(theme::text_faint()).child(step))
            })
            .child(
                div()
                    .id("close-workspace-dialog")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Close New Workspace")
                    .size(px(40.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .ml_3()
                    .text_size(crate::theme::title_size())
                    .text_color(theme::text_muted())
                    .cursor(CursorStyle::PointingHand)
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.close_new_workspace_dialog(cx);
                    }))
                    .child(icon(AleraIcon::Close, 24.0, theme::text_muted())),
            )
    }

    fn workspace_mode_button(
        &self,
        id: &'static str,
        icon_kind: AleraIcon,
        label: &'static str,
        mode: NewWorkspaceMode,
        cx: &mut Context<Self>,
    ) -> gpui::Stateful<gpui::Div> {
        let selected = self.new_workspace_mode == mode;
        div()
            .id(id)
            .focusable()
            .tab_stop(!self.workspace_creation_busy)
            .role(Role::RadioButton)
            .aria_label(label)
            .aria_selected(selected)
            .aria_toggled(if selected {
                Toggled::True
            } else {
                Toggled::False
            })
            .flex()
            .items_center()
            .justify_center()
            .flex_1()
            .rounded_md()
            .when(!self.workspace_creation_busy, |button| {
                button.cursor(CursorStyle::PointingHand)
            })
            .when(selected, |button| button.bg(theme::surface_raised()))
            .font_weight(gpui::FontWeight::MEDIUM)
            .text_color(if selected { theme::text() } else { theme::text_muted() })
            .on_click(cx.listener(move |this, _, _, cx| {
                if !this.workspace_creation_busy {
                    this.select_new_workspace_mode(mode, cx);
                }
            }))
            .gap(px(8.0))
            .child(icon(icon_kind, 16.0, if selected { theme::text() } else { theme::text_muted() }))
            .child(label)
    }

    pub(super) fn selected_workspace_project(&self) -> Option<&crate::model::Project> {
        self.selected_workspace_project_id
            .as_deref()
            .and_then(|id| {
                self.snapshot
                    .projects
                    .iter()
                    .find(|project| project.id == id)
            })
    }
}

pub(super) fn form_label(label: &'static str) -> gpui::Div {
    div()
        .mt_4()
        .mb_1()
        .text_size(crate::theme::caption_size())
        .text_color(theme::text_muted())
        .child(label)
}

fn prompt_form_label(label: &'static str) -> gpui::Div {
    form_label(label).mt(px(12.0)).text_size(px(10.0)).line_height(px(15.0)).font_weight(gpui::FontWeight::MEDIUM)
}

pub(super) fn radio(selected: bool) -> gpui::Div {
    design_system::radio(selected, true)
}

pub(super) fn check_box(checked: bool) -> gpui::Div {
    design_system::checkbox(checked, true, None)
}

pub(super) fn primary_button(
    id: &'static str,
    label: &'static str,
    disabled: bool,
) -> gpui::Stateful<gpui::Div> {
    primary_button_with_loading(id, label, disabled, false)
}

pub(super) fn primary_button_with_loading(
    id: &'static str,
    label: &'static str,
    disabled: bool,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    design_system::button_with_loading(id, label, design_system::ButtonKind::Filled, disabled, loading)
}

pub(super) fn primary_icon_button(
    id: &'static str,
    icon_kind: AleraIcon,
    label: &'static str,
    disabled: bool,
) -> gpui::Stateful<gpui::Div> {
    let foreground = if disabled {
        theme::disabled_control_foreground()
    } else {
        theme::app_background()
    };
    design_system::button_with_leading_icon(id, label, design_system::ButtonKind::Filled,
        disabled, icon(icon_kind, 16.0, foreground).into_any_element())
}

pub(super) fn secondary_button(id: &'static str, label: &'static str) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(label)
        .flex()
        .items_center()
        .justify_center()
        .h(px(32.0))
        .px_4()
        .rounded_lg()
        .cursor(CursorStyle::PointingHand)
        .child(label)
}
