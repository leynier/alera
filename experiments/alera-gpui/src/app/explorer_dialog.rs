use std::path::Path;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};

use super::AleraApp;
use crate::{design_system, icons::loading_indicator, theme};

impl AleraApp {
    pub(super) fn render_explorer_create_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        if self.explorer_delete_path.is_some() {
            return self.render_explorer_delete_dialog(cx);
        }
        let directory = self.explorer_create_directory.unwrap_or(false);
        let is_rename = self.explorer_rename_path.is_some();
        let title = if is_rename {
            "Rename"
        } else if directory {
            "New folder"
        } else {
            "New file"
        };

        explorer_dialog_overlay()
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.close_explorer_dialog(cx);
                }),
            )
            .child(
                div()
                    .id("explorer-action-dialog")
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .role(Role::Dialog)
                    .aria_label(title)
                    .w(px(290.0))
                    .min_h(px(192.0))
                    .rounded(px(12.0))
                    .bg(theme::surface())
                    .shadow_lg()
                    .child(
                        div()
                            .pt(px(24.0))
                            .px(px(24.0))
                            .text_size(px(16.0))
                            .line_height(px(19.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(title),
                    )
                    .child(div().mt(px(16.0)).px(px(24.0)).child(
                        design_system::text_field(&self.explorer_name_input).label(if is_rename {
                            "Name"
                        } else if directory {
                            "Folder name"
                        } else {
                            "File name"
                        }),
                    ))
                    .when_some(self.local_message.clone(), |dialog, message| {
                        dialog.child(
                            div()
                                .mt_2()
                                .px(px(24.0))
                                .text_size(crate::theme::caption_size())
                                .text_color(theme::danger())
                                .child(message),
                        )
                    })
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_end()
                            .gap(px(8.0))
                            .mt(px(24.0))
                            .px(px(24.0))
                            .pb(px(24.0))
                            .child(
                                dialog_button("cancel-explorer-action", "Cancel", false).on_click(
                                    cx.listener(|this, _, _, cx| {
                                        this.close_explorer_dialog(cx);
                                    }),
                                ),
                            )
                            .child(
                                dialog_button_with_loading(
                                    "confirm-explorer-action",
                                    if self.explorer_action_busy {
                                        "Working"
                                    } else {
                                        "Create"
                                    },
                                    false,
                                    self.explorer_action_busy,
                                )
                                .when(
                                    !self.explorer_action_busy,
                                    |button| {
                                        button.on_click(cx.listener(|this, _, _, cx| {
                                            this.submit_explorer_dialog(cx);
                                        }))
                                    },
                                ),
                            ),
                    ),
            )
            .into_any_element()
    }

    fn render_explorer_delete_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let name = self
            .explorer_delete_path
            .as_deref()
            .and_then(|path| Path::new(path).file_name())
            .and_then(|name| name.to_str())
            .unwrap_or("Item");

        explorer_dialog_overlay()
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.close_explorer_dialog(cx);
                }),
            )
            .child(
                div()
                    .id("explorer-delete-dialog")
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .role(Role::Dialog)
                    .aria_label(format!("Delete {name}"))
                    .w(px(420.0))
                    .rounded(px(12.0))
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface())
                    .shadow_lg()
                    .p(px(20.0))
                    .child(
                        div()
                            .text_size(px(14.0))
                            .line_height(px(17.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child(format!("Delete {name}")),
                    )
                    .child(
                        div()
                            .mt(px(12.0))
                            .text_size(px(13.0))
                            .line_height(px(19.0))
                            .text_color(theme::text_muted())
                            .child("Move This Item To The Trash?"),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .mt(px(20.0))
                            .child(
                                dialog_button("cancel-explorer-action", "Cancel", false)
                                    .flex_1()
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.close_explorer_dialog(cx);
                                    })),
                            )
                            .child(
                                dialog_button_with_loading(
                                    "confirm-explorer-action",
                                    if self.explorer_action_busy {
                                        "Working"
                                    } else {
                                        "Delete"
                                    },
                                    true,
                                    self.explorer_action_busy,
                                )
                                .flex_1()
                                .when(
                                    !self.explorer_action_busy,
                                    |button| {
                                        button.on_click(cx.listener(|this, _, _, cx| {
                                            this.submit_explorer_dialog(cx);
                                        }))
                                    },
                                ),
                            ),
                    ),
            )
            .into_any_element()
    }
}

fn explorer_dialog_overlay() -> gpui::Div {
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
}

fn dialog_button(
    id: &'static str,
    label: &'static str,
    destructive: bool,
) -> gpui::Stateful<gpui::Div> {
    dialog_button_with_loading(id, label, destructive, false)
}

fn dialog_button_with_loading(
    id: &'static str,
    label: &'static str,
    destructive: bool,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(!loading)
        .role(Role::Button)
        .aria_label(label)
        .h(px(if label == "Cancel" { 40.0 } else { 34.0 }))
        .min_w(px(if label == "Cancel" { 64.0 } else { 0.0 }))
        .px(px(if label == "Cancel" { 12.0 } else { 14.0 }))
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(8.0))
        .cursor(if loading {
            CursorStyle::Arrow
        } else {
            CursorStyle::PointingHand
        })
        .when(destructive, |button| {
            button.bg(theme::danger()).text_color(theme::on_danger())
        })
        .when(!destructive && label != "Cancel", |button| {
            button
                .bg(theme::accent())
                .text_color(theme::app_background())
        })
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .when(loading, |button| {
            button.child(loading_indicator(14.0, theme::text_faint()))
        })
        .child(label)
}
