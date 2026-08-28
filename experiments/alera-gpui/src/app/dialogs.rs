use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _, Toggled,
};
use gpui_component::input::Textarea;

use super::workspace_prompt_dropdown::WorkspacePromptDropdown;
use super::{AleraApp, NewWorkspaceMode, NewWorkspaceStep};
use crate::design_system;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_new_workspace_dialog(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let dialog = match self.new_workspace_step {
            NewWorkspaceStep::Entry => self.render_workspace_entry(cx),
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

    fn render_workspace_entry(&self, cx: &mut Context<Self>) -> AnyElement {
        let prompt_mode = self.new_workspace_mode == NewWorkspaceMode::FromPrompt;
        let project_label = self
            .selected_workspace_project()
            .map(|project| project.name.clone())
            .unwrap_or_else(|| "Select Project".to_string());
        let source_branch = self
            .workspace_branches_loading
            .then(|| "Loading Branches".to_owned())
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
            .w(px(630.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .px_4()
            .py_8()
            .child(self.workspace_dialog_header("New Workspace", None, false, cx))
            .child(
                div()
                    .flex()
                    .mt_4()
                    .w(px(202.0))
                    .h(px(30.0))
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
                dialog
                    .child(form_label("Initial Prompt"))
                    .child(
                        div()
                            .h(px(94.0))
                            .capture_action(cx.listener(Self::on_prompt_paste))
                            .child(
                                Textarea::new(&self.workspace_prompt_input)
                                    .disabled(
                                        self.workspace_creation_busy
                                            || self.workspace_prompt_created.is_some(),
                                    )
                                    .h_full(),
                            ),
                    )
                    .child(form_label("Project"))
                    .child(self.workspace_prompt_select_field(
                        "prompt-workspace-project",
                        project_label,
                        WorkspacePromptDropdown::Project,
                        cx,
                    ))
                    .child(form_label("Source Branch"))
                    .child(self.workspace_prompt_select_field(
                        "prompt-workspace-source-branch",
                        source_branch,
                        WorkspacePromptDropdown::SourceBranch,
                        cx,
                    ))
                    .child(form_label("Parent Workspace"))
                    .child(self.workspace_prompt_select_field(
                        "prompt-workspace-parent",
                        parent_workspace,
                        WorkspacePromptDropdown::ParentWorkspace,
                        cx,
                    ))
                    .child(form_label("Agent Profile"))
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
                                .text_sm()
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
                            .mt_4()
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
                                None,
                            ))
                            .child(
                                div()
                                    .child("Create Another"),
                            ),
                    )
                    .child(self.render_workspace_prompt_actions(prompt_is_empty, cx))
            })
            .when(!prompt_mode, |dialog| {
                dialog
                    .child(
                        div()
                            .mt_5()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(
                                "Choose Every Workspace Setting Yourself, Including The Branch Name And Optional Parent Workspace.",
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .mt_5()
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
                            .text_sm()
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
            .h(px(28.0))
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
                    .text_lg()
                    .text_color(theme::accent())
                    .child(icon(AleraIcon::GitFork, 18.0, theme::accent())),
            )
            .child(
                div()
                    .text_lg()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child(title),
            )
            .child(div().flex_1())
            .when_some(step, |header, step| {
                header.child(div().text_xs().text_color(theme::text_faint()).child(step))
            })
            .child(
                div()
                    .id("close-workspace-dialog")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Close New Workspace")
                    .ml_3()
                    .text_lg()
                    .text_color(theme::text_muted())
                    .cursor(CursorStyle::PointingHand)
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.close_new_workspace_dialog(cx);
                    }))
                    .child(icon(AleraIcon::Close, 16.0, theme::text_muted())),
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
            .when(selected, |button| button.bg(theme::surface()))
            .on_click(cx.listener(move |this, _, _, cx| {
                if !this.workspace_creation_busy {
                    this.select_new_workspace_mode(mode, cx);
                }
            }))
            .gap_1()
            .child(icon(icon_kind, 14.0, theme::text_muted()))
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
        .text_xs()
        .text_color(theme::text_muted())
        .child(label)
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
    div()
        .id(id)
        .focusable()
        .tab_stop(!disabled)
        .role(Role::Button)
        .aria_label(label)
        .flex()
        .items_center()
        .justify_center()
        .h(px(32.0))
        .px_4()
        .rounded_lg()
        .bg(if disabled {
            theme::surface_selected()
        } else {
            theme::accent()
        })
        .text_color(if disabled {
            theme::text_faint()
        } else {
            theme::app_background()
        })
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .when(!disabled, |button| button.cursor(CursorStyle::PointingHand))
        .when(loading, |button| {
            button.child(loading_indicator(14.0, theme::text_faint()))
        })
        .child(label)
}

pub(super) fn primary_icon_button(
    id: &'static str,
    icon_kind: AleraIcon,
    label: &'static str,
    disabled: bool,
) -> gpui::Stateful<gpui::Div> {
    let foreground = if disabled {
        theme::text_faint()
    } else {
        theme::app_background()
    };
    div()
        .id(id)
        .focusable()
        .tab_stop(!disabled)
        .role(Role::Button)
        .aria_label(label)
        .flex()
        .items_center()
        .justify_center()
        .gap_2()
        .h(px(32.0))
        .px_4()
        .rounded_lg()
        .bg(if disabled {
            theme::surface_selected()
        } else {
            theme::accent()
        })
        .text_color(foreground)
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .when(!disabled, |button| button.cursor(CursorStyle::PointingHand))
        .child(icon(icon_kind, 14.0, foreground))
        .child(label)
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
