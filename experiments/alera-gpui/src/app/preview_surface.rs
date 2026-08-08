use gpui::{
    div, img, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Styled as _, Window,
};
use gpui_component::input::Input;
use gpui_component::text::TextView;

use super::workspace_surface::PreviewAsset;
use super::AleraApp;
use crate::{
    file_icons::file_icon,
    icons::{icon, loading_indicator, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_editor(&self, window: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        let Some(opened_path) = &self.opened_file_path else {
            return div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(theme::text_muted())
                .child("Select A File")
                .into_any_element();
        };
        let preview_available = self.preview_asset.is_some();
        let source_available = self.editor_document.is_some();
        let file_color = if self.editor_dirty {
            theme::text()
        } else {
            theme::text_muted()
        };
        let content = if self.show_preview {
            self.render_preview(window, cx)
        } else {
            div()
                .flex_1()
                .overflow_hidden()
                .font_family("JetBrains Mono")
                .child(
                    Input::new(&self.editor_input)
                        .h_full()
                        .bordered(false)
                        .focus_bordered(false),
                )
                .into_any_element()
        };
        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(gpui::px(38.0))
                    .px_3()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .min_w_0()
                            .flex_1()
                            .child(file_icon(
                                opened_path,
                                false,
                                false,
                                false,
                                16.0,
                                file_color,
                            ))
                            .child(
                                div()
                                    .ml_2()
                                    .flex_1()
                                    .min_w_0()
                                    .overflow_hidden()
                                    .text_ellipsis()
                                    .font_family("JetBrains Mono")
                                    .text_size(px(12.0))
                                    .text_color(file_color)
                                    .child(opened_path.clone()),
                            )
                            .when_some(self.editor_document.as_ref(), |label, document| {
                                label.child(
                                    div()
                                        .ml_2()
                                        .text_xs()
                                        .text_color(theme::text_muted())
                                        .child(format_modified_time(document.modified_millis)),
                                )
                            }),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .when(source_available && preview_available, |toolbar| {
                                toolbar
                                    .child(
                                        div()
                                            .id("show-source")
                                            .px_3()
                                            .py_1()
                                            .rounded_md()
                                            .cursor(CursorStyle::PointingHand)
                                            .when(!self.show_preview, |item| {
                                                item.bg(theme::surface_selected())
                                            })
                                            .on_mouse_down(
                                                gpui::MouseButton::Left,
                                                cx.listener(|this, _, _, cx| {
                                                    this.show_preview = false;
                                                    cx.notify();
                                                }),
                                            )
                                            .child("Source"),
                                    )
                                    .child(
                                        div()
                                            .id("show-preview")
                                            .px_3()
                                            .py_1()
                                            .rounded_md()
                                            .cursor(CursorStyle::PointingHand)
                                            .when(self.show_preview, |item| {
                                                item.bg(theme::surface_selected())
                                            })
                                            .on_mouse_down(
                                                gpui::MouseButton::Left,
                                                cx.listener(|this, _, _, cx| {
                                                    this.show_preview = true;
                                                    cx.notify();
                                                }),
                                            )
                                            .child("Preview"),
                                    )
                            })
                            .when(source_available, |toolbar| {
                                toolbar
                                    .child(
                                        editor_toolbar_button(
                                            "editor-view-diff",
                                            AleraIcon::Diff,
                                            true,
                                        )
                                        .on_mouse_down(
                                            gpui::MouseButton::Left,
                                            cx.listener(|this, _, _, cx| this.open_editor_diff(cx)),
                                        ),
                                    )
                                    .child(
                                        editor_toolbar_button(
                                            "save-editor",
                                            if self.local_busy {
                                                AleraIcon::Loading
                                            } else {
                                                AleraIcon::Save
                                            },
                                            !self.local_busy && self.editor_dirty,
                                        )
                                        .on_mouse_down(
                                            gpui::MouseButton::Left,
                                            cx.listener(|this, _, _, cx| {
                                                if this.editor_dirty && !this.local_busy {
                                                    this.save_editor(false, cx);
                                                }
                                            }),
                                        )
                                        .when(
                                            self.local_busy,
                                            |button| {
                                                button.child(loading_indicator(
                                                    14.0,
                                                    theme::text_muted(),
                                                ))
                                            },
                                        ),
                                    )
                                    .child(
                                        editor_toolbar_button(
                                            "discard-editor",
                                            AleraIcon::Restore,
                                            !self.local_busy && self.editor_dirty,
                                        )
                                        .on_mouse_down(
                                            gpui::MouseButton::Left,
                                            cx.listener(|this, _, window, cx| {
                                                if this.editor_dirty && !this.local_busy {
                                                    this.discard_editor_changes(window, cx);
                                                }
                                            }),
                                        ),
                                    )
                                    .when(preview_available, |toolbar| {
                                        toolbar.child(
                                            editor_toolbar_button(
                                                "open-editor-preview",
                                                AleraIcon::Preview,
                                                true,
                                            )
                                            .on_mouse_down(
                                                gpui::MouseButton::Left,
                                                cx.listener(|this, _, _, cx| {
                                                    this.open_editor_preview(cx)
                                                }),
                                            ),
                                        )
                                    })
                            }),
                    ),
            )
            .child(content)
            .into_any_element()
    }

    fn render_preview(&self, window: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        match (&self.preview_asset, &self.editor_document) {
            (Some(PreviewAsset::Markdown), Some(document)) => div()
                .id("markdown-preview")
                .flex_1()
                .overflow_hidden()
                .p_5()
                .child(
                    TextView::markdown(
                        "markdown-preview-content",
                        document.display_content.clone(),
                        window,
                        cx,
                    )
                    .selectable(true)
                    .scrollable(true),
                )
                .into_any_element(),
            (Some(PreviewAsset::Mermaid(image)), _) => div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .p_5()
                .child(img(image.clone()).size_full())
                .into_any_element(),
            (Some(PreviewAsset::Image(path)), _) => div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .p_5()
                .child(img(path.clone()).size_full())
                .into_any_element(),
            _ => div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(theme::text_muted())
                .child("Preview Unavailable")
                .into_any_element(),
        }
    }
}

fn editor_toolbar_button(
    id: &'static str,
    kind: AleraIcon,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .w(px(28.0))
        .h(px(28.0))
        .rounded_md()
        .cursor(if enabled {
            CursorStyle::PointingHand
        } else {
            CursorStyle::Arrow
        })
        .when(enabled, |button| {
            button.hover(|style| style.bg(theme::surface_selected()))
        })
        .child(icon(
            kind,
            15.0,
            if enabled {
                theme::text_muted()
            } else {
                theme::text_faint()
            },
        ))
}

fn format_modified_time(millis: i64) -> String {
    chrono::DateTime::from_timestamp_millis(millis)
        .map(|time| format!("Modified {}", time.format("%Y-%m-%d %H:%M")))
        .unwrap_or_else(|| "Modified Time Unknown".to_string())
}
