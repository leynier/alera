use gpui::{
    div, img, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, StatefulInteractiveElement as _,
    Styled as _, Window,
};
use gpui_component::input::Input;
use gpui_component::text::TextView;

use super::workspace_surface::PreviewAsset;
use super::AleraApp;
use crate::theme;

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
        let save_label = if self.editor_dirty {
            "Save Changes"
        } else {
            "Saved"
        };
        let content = if self.show_preview {
            self.render_preview(window, cx)
        } else {
            div()
                .flex_1()
                .overflow_hidden()
                .font_family("JetBrains Mono")
                .child(Input::new(&self.editor_input).h_full())
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
                    .child(div().child(opened_path.clone()).when_some(
                        self.editor_document.as_ref(),
                        |label, document| {
                            label.child(
                                div()
                                    .ml_2()
                                    .text_xs()
                                    .text_color(theme::text_muted())
                                    .child(format_modified_time(document.modified_millis)),
                            )
                        },
                    ))
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
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.show_preview = false;
                                                cx.notify();
                                            }))
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
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.show_preview = true;
                                                cx.notify();
                                            }))
                                            .child("Preview"),
                                    )
                            })
                            .when(source_available && !self.show_preview, |toolbar| {
                                toolbar.child(
                                    div()
                                        .id("save-editor")
                                        .px_3()
                                        .py_1()
                                        .rounded_md()
                                        .cursor(CursorStyle::PointingHand)
                                        .bg(theme::surface_selected())
                                        .text_color(theme::accent())
                                        .on_click(cx.listener(|this, _, _, cx| {
                                            if this.editor_dirty {
                                                this.save_editor(false, cx);
                                            }
                                        }))
                                        .child(save_label),
                                )
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

fn format_modified_time(millis: i64) -> String {
    chrono::DateTime::from_timestamp_millis(millis)
        .map(|time| format!("Modified {}", time.format("%Y-%m-%d %H:%M")))
        .unwrap_or_else(|| "Modified Time Unknown".to_string())
}
