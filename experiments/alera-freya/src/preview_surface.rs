use alera_desktop_core::RuntimeBridge;
use base64::prelude::{BASE64_STANDARD, Engine as _};
use bytes::Bytes;
use freya::prelude::*;
use serde_json::{Value, json};

use crate::alera_scroll_view::AleraScrollView as ScrollView;
use crate::{BACKGROUND, BORDER, MUTED, SURFACE, file_icons};

pub(crate) fn is_image_path(path: &str) -> bool {
    extension(path).is_some_and(|extension| {
        ["png", "jpg", "jpeg", "gif", "webp", "bmp", "ico"]
            .iter()
            .any(|candidate| extension.eq_ignore_ascii_case(candidate))
    })
}

pub(crate) fn is_markdown_path(path: &str) -> bool {
    extension(path).is_some_and(|extension| {
        extension.eq_ignore_ascii_case("md") || extension.eq_ignore_ascii_case("mdx")
    })
}

pub(crate) fn is_merman_path(path: &str) -> bool {
    extension(path).is_some_and(|extension| {
        extension.eq_ignore_ascii_case("mermain") || extension.eq_ignore_ascii_case("mmd")
    })
}

fn extension(path: &str) -> Option<&str> {
    path.rsplit_once('.').map(|(_, extension)| extension)
}

fn preview_header(path: String) -> Element {
    rect()
        .height(Size::px(34.))
        .width(Size::fill())
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .padding(Gaps::new(10., 0., 10., 0.))
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(8.)
        .child(file_icons::file_icon(&path, false, false, false, 16.))
        .child(
            label()
                .font_size(12.)
                .font_family("JetBrains Mono")
                .color(MUTED)
                .text(path),
        )
        .into_element()
}

fn preview_message(message: impl Into<String>, error: bool) -> Element {
    rect()
        .expanded()
        .center()
        .child(
            label()
                .font_size(12.)
                .color(if error { (248, 113, 113) } else { MUTED })
                .text(message.into()),
        )
        .into_element()
}

#[derive(Clone)]
pub(crate) struct MarkdownPreviewSurface {
    pub bridge: RuntimeBridge,
    pub workspace_path: String,
    pub relative_path: String,
}

impl PartialEq for MarkdownPreviewSurface {
    fn eq(&self, other: &Self) -> bool {
        self.workspace_path == other.workspace_path && self.relative_path == other.relative_path
    }
}

impl Component for MarkdownPreviewSurface {
    fn render(&self) -> impl IntoElement {
        let bridge = self.bridge.clone();
        let workspace_path = self.workspace_path.clone();
        let relative_path = self.relative_path.clone();
        let document = use_future(move || {
            let bridge = bridge.clone();
            let workspace_path = workspace_path.clone();
            let relative_path = relative_path.clone();
            async move {
                bridge
                    .request(
                        "workspaceFiles.readEditor",
                        json!({
                            "workspacePath": workspace_path,
                            "relativePath": relative_path,
                            "tabSize": 4,
                        }),
                    )
                    .await
                    .and_then(|value| {
                        value
                            .get("displayContent")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                            .ok_or_else(|| "Markdown response omitted displayContent".to_string())
                    })
            }
        });
        let body = match &*document.state() {
            FutureState::Pending | FutureState::Loading => rect()
                .expanded()
                .center()
                .child(CircularLoader::new())
                .into_element(),
            FutureState::Fulfilled(Err(error)) => preview_message(error.clone(), true),
            FutureState::Fulfilled(Ok(content)) => ScrollView::new()
                .width(Size::fill())
                .height(Size::fill())
                .child(
                    rect()
                        .width(Size::fill())
                        .padding(Gaps::new_all(24.))
                        .child(
                            MarkdownViewer::new(content.clone())
                                .width(Size::fill())
                                .code_editor_font_family("JetBrains Mono"),
                        ),
                )
                .into_element(),
        };
        rect()
            .expanded()
            .vertical()
            .background(BACKGROUND)
            .child(preview_header(self.relative_path.clone()))
            .child(body)
    }
}

#[derive(Clone)]
pub(crate) struct ImagePreviewSurface {
    pub bridge: RuntimeBridge,
    pub workspace_path: String,
    pub relative_path: String,
}

impl PartialEq for ImagePreviewSurface {
    fn eq(&self, other: &Self) -> bool {
        self.workspace_path == other.workspace_path && self.relative_path == other.relative_path
    }
}

impl Component for ImagePreviewSurface {
    fn render(&self) -> impl IntoElement {
        let bridge = self.bridge.clone();
        let workspace_path = self.workspace_path.clone();
        let relative_path = self.relative_path.clone();
        let image = use_future(move || {
            let bridge = bridge.clone();
            let workspace_path = workspace_path.clone();
            let relative_path = relative_path.clone();
            async move {
                bridge
                    .request(
                        "workspacePreview.image",
                        json!({
                            "workspacePath": workspace_path,
                            "relativePath": relative_path,
                        }),
                    )
                    .await
                    .and_then(|value| {
                        let encoded = value
                            .get("bytesBase64")
                            .and_then(Value::as_str)
                            .ok_or_else(|| "Image response omitted bytesBase64".to_string())?;
                        BASE64_STANDARD
                            .decode(encoded)
                            .map(Bytes::from)
                            .map_err(|error| format!("Image response is invalid: {error}"))
                    })
            }
        });
        let body = match &*image.state() {
            FutureState::Pending | FutureState::Loading => rect()
                .expanded()
                .center()
                .child(CircularLoader::new())
                .into_element(),
            FutureState::Fulfilled(Err(error)) => preview_message(error.clone(), true),
            FutureState::Fulfilled(Ok(bytes)) => rect()
                .expanded()
                .center()
                .padding(Gaps::new_all(24.))
                .child(
                    ImageViewer::new(bytes.clone())
                        .width(Size::fill())
                        .height(Size::fill())
                        .a11y_alt(format!("Preview of {}", self.relative_path)),
                )
                .into_element(),
        };
        rect()
            .expanded()
            .vertical()
            .background(BACKGROUND)
            .child(preview_header(self.relative_path.clone()))
            .child(body)
    }
}

#[derive(Clone)]
pub(crate) struct MermanPreviewSurface {
    pub bridge: RuntimeBridge,
    pub workspace_path: String,
    pub relative_path: String,
}

impl PartialEq for MermanPreviewSurface {
    fn eq(&self, other: &Self) -> bool {
        self.workspace_path == other.workspace_path && self.relative_path == other.relative_path
    }
}

impl Component for MermanPreviewSurface {
    fn render(&self) -> impl IntoElement {
        let bridge = self.bridge.clone();
        let workspace_path = self.workspace_path.clone();
        let relative_path = self.relative_path.clone();
        let diagram = use_future(move || {
            let bridge = bridge.clone();
            let workspace_path = workspace_path.clone();
            let relative_path = relative_path.clone();
            async move {
                bridge
                    .request(
                        "workspacePreview.mermaid",
                        json!({
                            "workspacePath": workspace_path,
                            "relativePath": relative_path,
                        }),
                    )
                    .await
                    .and_then(|value| {
                        value
                            .get("svg")
                            .and_then(Value::as_str)
                            .map(|svg| Bytes::from(svg.to_string()))
                            .ok_or_else(|| "Diagram response omitted svg".to_string())
                    })
            }
        });
        let body = match &*diagram.state() {
            FutureState::Pending | FutureState::Loading => rect()
                .expanded()
                .center()
                .child(CircularLoader::new())
                .into_element(),
            FutureState::Fulfilled(Err(error)) => preview_message(error.clone(), true),
            FutureState::Fulfilled(Ok(svg)) => rect()
                .expanded()
                .center()
                .padding(Gaps::new_all(24.))
                .child(
                    SvgViewer::new(svg.clone())
                        .width(Size::fill())
                        .height(Size::fill())
                        .parallel(true)
                        .a11y_alt(format!("Diagram preview of {}", self.relative_path)),
                )
                .into_element(),
        };
        rect()
            .expanded()
            .vertical()
            .background(BACKGROUND)
            .child(preview_header(self.relative_path.clone()))
            .child(body)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_flutter_preview_extensions_case_insensitively() {
        assert!(is_image_path("assets/LOGO.PNG"));
        assert!(is_markdown_path("README.MD"));
        assert!(is_merman_path("docs/flow.MMD"));
        assert!(!is_image_path("src/main.rs"));
    }
}
