use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::input::Textarea;

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::theme;
use crate::workspace_git::GitAction;

#[derive(Clone)]
pub(super) enum SourceControlDialog {
    DiscardAll,
    DiscardPath { path: String },
    DiscardPaths { paths: Vec<String>, target: String },
    StashPicker,
    Amend,
}

impl AleraApp {
    pub(super) fn render_source_control_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(dialog) = self.source_control_dialog.as_ref() else {
            return div().into_any_element();
        };
        match dialog {
            SourceControlDialog::StashPicker => self.render_stash_picker_dialog(cx),
            SourceControlDialog::Amend => self.render_amend_dialog(cx),
            SourceControlDialog::DiscardAll
            | SourceControlDialog::DiscardPath { .. }
            | SourceControlDialog::DiscardPaths { .. } => {
                self.render_discard_confirmation(dialog, cx)
            }
        }
    }

    fn render_discard_confirmation(
        &self,
        dialog: &SourceControlDialog,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let (title, message) = match dialog {
            SourceControlDialog::DiscardAll => (
                "Discard All Changes?",
                "This permanently discards unstaged and untracked changes in this workspace."
                    .to_owned(),
            ),
            SourceControlDialog::DiscardPath { path } => (
                "Discard Changes?",
                format!("This permanently discards unstaged and untracked changes in \"{path}\"."),
            ),
            SourceControlDialog::DiscardPaths { target, .. } => (
                "Discard Changes?",
                format!("This permanently discards changes in \"{target}\"."),
            ),
            SourceControlDialog::StashPicker => unreachable!(),
            SourceControlDialog::Amend => unreachable!(),
        };
        modal_shell(
            design_system::dialog_shell("source-control-dialog", title, 420.0)
                .child(
                    div()
                        .text_size(px(14.0))
                        .font_weight(gpui::FontWeight::MEDIUM)
                        .child(title),
                )
                .child(
                    div()
                        .mt_3()
                        .text_size(px(13.0))
                        .text_color(theme::text_muted())
                        .child(message),
                )
                .child(
                    div()
                        .flex()
                        .w_full()
                        .mt_5()
                        .gap_2()
                        .child(
                            design_system::button(
                                "cancel-source-discard",
                                "Cancel",
                                ButtonKind::Text,
                                false,
                            )
                            .flex_1()
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.source_control_dialog = None;
                                cx.notify();
                            })),
                        )
                        .child(
                            design_system::button(
                                "confirm-source-discard",
                                "Discard",
                                ButtonKind::Destructive,
                                false,
                            )
                            .flex_1()
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.confirm_source_control_dialog(cx);
                            })),
                        ),
                ),
        )
    }

    fn render_stash_picker_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let rows = self
            .git_snapshot
            .stashes
            .iter()
            .enumerate()
            .map(|(row_index, stash)| {
                let stash_index = stash.index;
                div()
                    .id(("source-stash-row", row_index))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::ListBoxOption)
                    .aria_label(format!("{} {}", stash.reference, stash.message))
                    .flex()
                    .flex_col()
                    .px_3()
                    .py_2()
                    .rounded_md()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.source_control_dialog = None;
                        this.run_git_action(GitAction::StashPop(stash_index), cx);
                    }))
                    .child(
                        div()
                            .text_size(px(14.0))
                            .text_color(theme::text())
                            .child(stash.reference.clone()),
                    )
                    .child(
                        div()
                            .mt_1()
                            .text_size(px(12.0))
                            .text_color(theme::text_muted())
                            .line_clamp(2)
                            .child(stash.message.clone()),
                    )
            })
            .collect::<Vec<_>>();
        modal_shell(
            div()
                .w(px(460.0))
                .max_h(px(560.0))
                .rounded_lg()
                .border_1()
                .border_color(theme::border())
                .bg(theme::surface_raised())
                .shadow_lg()
                .p(px(20.0))
                .child(
                    div()
                        .text_size(px(16.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child("Stash Pop"),
                )
                .child(
                    div()
                        .id("source-stash-list")
                        .flex()
                        .flex_col()
                        .mt(px(12.0))
                        .max_h(px(430.0))
                        .overflow_y_scroll()
                        .children(rows),
                )
                .child(
                    div().flex().justify_end().mt(px(12.0)).child(
                        div()
                            .id("cancel-stash-picker")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("Cancel")
                            .px_4()
                            .h(px(32.0))
                            .flex()
                            .items_center()
                            .justify_center()
                            .rounded_md()
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_selected()))
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.source_control_dialog = None;
                                cx.notify();
                            }))
                            .child("Cancel"),
                    ),
                ),
        )
    }

    fn render_amend_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let empty = self.source_amend_input.read(cx).value().trim().is_empty();
        modal_shell(
            div()
                .w(px(460.0))
                .rounded_lg()
                .border_1()
                .border_color(theme::border())
                .bg(theme::surface_raised())
                .shadow_lg()
                .p(px(20.0))
                .child(
                    div()
                        .text_size(px(16.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child("Amend Commit"),
                )
                .child(
                    div()
                        .mt(px(16.0))
                        .h(px(112.0))
                        .rounded_md()
                        .border_1()
                        .border_color(if empty {
                            theme::danger()
                        } else {
                            theme::border()
                        })
                        .bg(theme::surface())
                        .child(Textarea::new(&self.source_amend_input).h_full()),
                )
                .when(empty, |dialog| {
                    dialog.child(
                        div()
                            .mt_1()
                            .text_size(px(11.0))
                            .text_color(theme::danger())
                            .child("Message Is Required"),
                    )
                })
                .child(
                    div()
                        .flex()
                        .justify_end()
                        .mt(px(20.0))
                        .gap_2()
                        .child(
                            div()
                                .id("cancel-source-amend")
                                .focusable()
                                .tab_stop(true)
                                .role(Role::Button)
                                .aria_label("Cancel")
                                .px_4()
                                .h(px(36.0))
                                .flex()
                                .items_center()
                                .justify_center()
                                .rounded_md()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_selected()))
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.source_control_dialog = None;
                                    cx.notify();
                                }))
                                .child("Cancel"),
                        )
                        .child(
                            div()
                                .id("confirm-source-amend")
                                .focusable()
                                .tab_stop(!empty)
                                .role(Role::Button)
                                .aria_label("Amend")
                                .px_4()
                                .h(px(36.0))
                                .flex()
                                .items_center()
                                .justify_center()
                                .rounded_md()
                                .bg(if empty {
                                    theme::surface_selected()
                                } else {
                                    theme::text()
                                })
                                .text_color(if empty {
                                    theme::text_faint()
                                } else {
                                    theme::app_background()
                                })
                                .when(!empty, |button| {
                                    button
                                        .cursor(CursorStyle::PointingHand)
                                        .on_click(cx.listener(|this, _, _, cx| {
                                            this.confirm_source_control_dialog(cx);
                                        }))
                                })
                                .child("Amend"),
                        ),
                ),
        )
    }

    fn confirm_source_control_dialog(&mut self, cx: &mut Context<Self>) {
        let Some(dialog) = self.source_control_dialog.take() else {
            return;
        };
        match dialog {
            SourceControlDialog::DiscardAll => self.run_git_action(GitAction::DiscardAll, cx),
            SourceControlDialog::DiscardPath { path } => {
                self.run_git_action(GitAction::DiscardPath(path), cx);
            }
            SourceControlDialog::DiscardPaths { paths, .. } => self
                .run_git_path_actions(paths.into_iter().map(GitAction::DiscardPath).collect(), cx),
            SourceControlDialog::StashPicker => {}
            SourceControlDialog::Amend => {
                let message = self.source_amend_input.read(cx).value().trim().to_owned();
                if !message.is_empty() {
                    self.run_git_action(GitAction::Amend(message), cx);
                }
            }
        }
    }
}

fn modal_shell(content: impl gpui::IntoElement) -> AnyElement {
    div()
        .absolute()
        .inset_0()
        .occlude()
        .flex()
        .items_center()
        .justify_center()
        .bg(theme::overlay_scrim())
        .child(content)
        .into_any_element()
}
