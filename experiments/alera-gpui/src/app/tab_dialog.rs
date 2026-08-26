use gpui::{
    div, px, Context, CursorStyle, InteractiveElement as _, IntoElement, MouseButton,
    ParentElement as _, Styled as _,
};

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::theme;

impl AleraApp {
    pub(super) fn render_editor_conflict_dialog(&self, cx: &mut Context<Self>) -> impl IntoElement {
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
            .child(
                design_system::dialog_shell(420.0)
                    .child(
                        div()
                            .text_size(px(14.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child("File changed on disk"),
                    )
                    .child(
                        div()
                            .mt_3()
                            .text_size(px(13.0))
                            .text_color(theme::text_muted())
                            .child("Overwrite the file with the editor contents?"),
                    )
                    .child(
                        div()
                            .mt_5()
                            .flex()
                            .w_full()
                            .gap_2()
                            .child(
                                design_system::button(
                                    "cancel-editor-conflict",
                                    "Cancel",
                                    ButtonKind::Text,
                                    false,
                                )
                                    .flex_1()
                                    .on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.cancel_editor_conflict(cx);
                                        }),
                                    ),
                            )
                            .child(
                                design_system::button(
                                    "overwrite-editor-conflict",
                                    "Overwrite",
                                    ButtonKind::Destructive,
                                    false,
                                )
                                    .flex_1()
                                    .on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.confirm_editor_overwrite(cx);
                                        }),
                                    ),
                            ),
                    ),
            )
    }

    pub(super) fn render_dirty_tab_close_dialog(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let dirty_titles = self
            .tab_close_armed
            .as_deref()
            .into_iter()
            .flatten()
            .filter_map(|tab_id| self.snapshot.tabs.iter().find(|tab| &tab.id == tab_id))
            .filter(|tab| {
                self.editor_dirty
                    && matches!(tab.kind.as_str(), "editor" | "markdownViewer")
                    && tab.payload.get("filePath").and_then(|value| value.as_str())
                        == self.opened_file_path.as_deref()
            })
            .map(|tab| tab.title.as_str())
            .collect::<Vec<_>>();
        let plural = dirty_titles.len() > 1;
        let message = if plural {
            format!("{} editor tabs have unsaved changes.", dirty_titles.len())
        } else {
            format!(
                "{} has unsaved changes.",
                dirty_titles.first().copied().unwrap_or("This Editor")
            )
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
            .child(
                div()
                    .w(px(420.0))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .p_4()
                    .child(
                        div()
                            .text_lg()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(if plural {
                                "Close Unsaved Editors?"
                            } else {
                                "Close Unsaved Editor?"
                            }),
                    )
                    .child(
                        div()
                            .mt_2()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(message),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt_4()
                            .child(
                                dialog_action("cancel-dirty-tab-close", "Cancel", false)
                                    .on_mouse_down(
                                        gpui::MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.cancel_close_dirty_tab(cx);
                                        }),
                                    ),
                            )
                            .child(
                                dialog_action("confirm-dirty-tab-close", "Close", true)
                                    .on_mouse_down(
                                        gpui::MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.confirm_close_dirty_tab(cx);
                                        }),
                                    ),
                            ),
                    ),
            )
    }

    pub(super) fn render_tab_rename_dialog(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let field_error = self
            .local_message
            .as_ref()
            .is_some_and(|message| message.as_ref() == "Terminal Title Is Required")
            .then_some("Terminal Title Is Required");
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
            .child(
                design_system::dialog_shell(420.0)
                    .child(
                        div()
                            .text_lg()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Change Terminal Title"),
                    )
                    .child(
                        div().mt_4().child(
                            design_system::text_field(&self.tab_rename_input)
                                .label("Terminal Title")
                                .disabled(self.tab_mutation_busy)
                                .error(field_error),
                        ),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt_5()
                            .child(
                                design_system::button(
                                    "cancel-tab-rename",
                                    "Cancel",
                                    ButtonKind::Text,
                                    self.tab_mutation_busy,
                                )
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        this.close_tab_rename_dialog(cx);
                                    }),
                                ),
                            )
                            .child(
                                design_system::button_with_loading(
                                    "save-tab-rename",
                                    if self.tab_mutation_busy {
                                        "Saving"
                                    } else {
                                        "Change Title"
                                    },
                                    ButtonKind::Filled,
                                    self.tab_mutation_busy,
                                    self.tab_mutation_busy,
                                )
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        this.rename_selected_tab(cx);
                                    }),
                                ),
                            ),
                    ),
            )
    }
}

fn dialog_action(
    id: &'static str,
    label: &'static str,
    destructive: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .h(px(32.0))
        .px_3()
        .rounded_md()
        .border_1()
        .border_color(if destructive {
            theme::danger()
        } else {
            theme::border()
        })
        .bg(if destructive {
            theme::danger()
        } else {
            theme::surface()
        })
        .text_color(if destructive {
            theme::on_danger()
        } else {
            theme::text()
        })
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .cursor(CursorStyle::PointingHand)
        .child(label)
}
