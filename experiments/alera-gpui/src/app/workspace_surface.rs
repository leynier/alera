use std::path::{Path, PathBuf};
use std::sync::Arc;

use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, Image, ImageFormat,
    InteractiveElement as _, IntoElement as _, ParentElement as _, SharedString,
    StatefulInteractiveElement as _, Styled as _, Window,
};

use super::AleraApp;
use crate::activity::Activity;
use crate::theme;
use crate::workspace_service::FileEntry;

#[derive(Clone, Debug)]
pub(super) struct ExplorerRow {
    pub entry: FileEntry,
    pub depth: usize,
    pub expanded: bool,
}

#[derive(Clone, Debug)]
pub(super) enum PreviewAsset {
    Markdown,
    Mermaid(Arc<Image>),
    Image(PathBuf),
}

enum OpenFileResult {
    Text {
        document: crate::workspace_service::EditorDocument,
        preview: Option<PreviewAsset>,
    },
    Image {
        relative_path: String,
        path: PathBuf,
    },
}

impl AleraApp {
    pub(super) fn refresh_local_activity(&mut self, cx: &mut Context<Self>) {
        match self.activity {
            Activity::Explorer => self.load_root_directory(cx),
            Activity::SourceControl => self.refresh_git(cx),
            Activity::PullRequests => self.refresh_forge(cx),
            Activity::AiText => {}
            Activity::Search | Activity::Workbench => {}
            _ => {}
        }
    }

    pub(super) fn reset_local_workspace(&mut self, cx: &mut Context<Self>) {
        self.local_generation += 1;
        self.explorer_rows.clear();
        self.editor_document = None;
        self.opened_file_path = None;
        self.preview_asset = None;
        self.show_preview = false;
        self.editor_dirty = false;
        self.search_results = Default::default();
        self.replace_confirmation = None;
        self.git_snapshot = Default::default();
        self.git_discard_armed = false;
        self.git_discard_path_armed = None;
        self.forge_snapshot = Default::default();
        self.forge_danger_armed = None;
        self.local_message = None;
        self.refresh_local_activity(cx);
    }

    pub(super) fn selected_workspace_path(&self) -> Option<String> {
        self.selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.workspace(id))
            .map(|workspace| workspace.path.clone())
    }

    fn load_root_directory(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.list(workspace_path, String::new()).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(entries) => {
                        this.explorer_rows = entries
                            .into_iter()
                            .map(|entry| ExplorerRow {
                                entry,
                                depth: 0,
                                expanded: false,
                            })
                            .collect();
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn toggle_directory(&mut self, relative_path: String, cx: &mut Context<Self>) {
        let Some(index) = self
            .explorer_rows
            .iter()
            .position(|row| row.entry.relative_path == relative_path)
        else {
            return;
        };
        let depth = self.explorer_rows[index].depth;
        if self.explorer_rows[index].expanded {
            self.explorer_rows[index].expanded = false;
            let end = self.explorer_rows[index + 1..]
                .iter()
                .position(|row| row.depth <= depth)
                .map(|offset| index + 1 + offset)
                .unwrap_or(self.explorer_rows.len());
            self.explorer_rows.drain(index + 1..end);
            cx.notify();
            return;
        }

        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.list(workspace_path, relative_path.clone()).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(entries) => {
                        let Some(index) = this
                            .explorer_rows
                            .iter()
                            .position(|row| row.entry.relative_path == relative_path)
                        else {
                            return;
                        };
                        this.explorer_rows[index].expanded = true;
                        let child_depth = this.explorer_rows[index].depth + 1;
                        this.explorer_rows.splice(
                            index + 1..index + 1,
                            entries.into_iter().map(|entry| ExplorerRow {
                                entry,
                                depth: child_depth,
                                expanded: false,
                            }),
                        );
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn open_workspace_file(
        &mut self,
        relative_path: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        self.local_message = Some(format!("Opening {relative_path}").into());
        let service = self.workspace_service.clone();
        cx.spawn_in(window, async move |this, cx| {
            let extension = extension_for_path(&relative_path);
            let result = if is_image_extension(extension) {
                service
                    .image_path(workspace_path, relative_path.clone())
                    .await
                    .map(|path| OpenFileResult::Image {
                        relative_path,
                        path,
                    })
            } else {
                match service
                    .read(workspace_path.clone(), relative_path.clone())
                    .await
                {
                    Ok(document) if is_mermaid_extension(extension) => service
                        .mermaid(workspace_path, relative_path)
                        .await
                        .map(|svg| OpenFileResult::Text {
                            document,
                            preview: Some(PreviewAsset::Mermaid(Arc::new(Image::from_bytes(
                                ImageFormat::Svg,
                                svg.into_bytes(),
                            )))),
                        }),
                    Ok(document) => Ok(OpenFileResult::Text {
                        preview: (extension == "md" || extension == "mdx")
                            .then_some(PreviewAsset::Markdown),
                        document,
                    }),
                    Err(error) => Err(error),
                }
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(OpenFileResult::Text { document, preview }) => {
                        let language = language_for_path(&document.relative_path);
                        let display_content = document.display_content.clone();
                        this.editor_input.update(cx, |input, cx| {
                            input.set_highlighter(language, cx);
                            input.set_value(display_content, window, cx);
                        });
                        this.opened_file_path = Some(document.relative_path.clone());
                        this.editor_document = Some(document);
                        this.show_preview = preview.is_some();
                        this.preview_asset = preview;
                        this.editor_dirty = false;
                        this.local_message = None;
                    }
                    Ok(OpenFileResult::Image {
                        relative_path,
                        path,
                    }) => {
                        this.opened_file_path = Some(relative_path);
                        this.editor_document = None;
                        this.preview_asset = Some(PreviewAsset::Image(path));
                        this.show_preview = true;
                        this.editor_dirty = false;
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn save_editor(&mut self, overwrite: bool, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        let Some(document) = self.editor_document.clone() else {
            return;
        };
        let display_content = self.editor_input.read(cx).value().to_string();
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service
                .write(workspace_path, document, display_content, overwrite)
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(document) => {
                        this.editor_document = Some(document);
                        this.editor_dirty = false;
                        this.local_message = Some("Saved".into());
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_local_surface(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        match self.activity {
            Activity::Explorer => self.render_explorer_surface(window, cx),
            Activity::Search => self.render_search_surface(cx),
            Activity::SourceControl => self.render_git_surface(cx),
            Activity::PullRequests => self.render_forge_surface(cx),
            Activity::AiText => self.render_ai_text_surface(cx),
            _ => div().into_any_element(),
        }
    }

    fn render_explorer_surface(&self, window: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        let rows = self
            .explorer_rows
            .iter()
            .enumerate()
            .map(|(index, row)| {
                let path = row.entry.relative_path.clone();
                let is_directory = row.entry.is_directory;
                let label = if is_directory {
                    if row.expanded {
                        format!("⌄ {}", row.entry.name)
                    } else {
                        format!("› {}", row.entry.name)
                    }
                } else {
                    row.entry.name.clone()
                };
                let status = row.entry.git_status.clone();
                let size = (!is_directory).then(|| human_file_size(row.entry.size));
                div()
                    .id(("explorer-row", index))
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(gpui::px(28.0))
                    .pl(gpui::px(10.0 + row.depth as f32 * 14.0))
                    .pr_2()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, window, cx| {
                        if is_directory {
                            this.toggle_directory(path.clone(), cx);
                        } else {
                            this.open_workspace_file(path.clone(), window, cx);
                        }
                    }))
                    .child(
                        div()
                            .when(row.entry.is_hidden, |item| {
                                item.text_color(theme::text_muted())
                            })
                            .child(label),
                    )
                    .when_some(size, |item, size| {
                        item.child(
                            div()
                                .ml_auto()
                                .text_xs()
                                .text_color(theme::text_muted())
                                .child(size),
                        )
                    })
                    .when_some(status, |item, status| {
                        item.child(div().text_xs().text_color(theme::warning()).child(status))
                    })
            })
            .collect::<Vec<_>>();

        div()
            .flex()
            .flex_1()
            .overflow_hidden()
            .child(
                div()
                    .id("explorer-tree")
                    .w(gpui::px(280.0))
                    .h_full()
                    .overflow_y_scroll()
                    .border_r_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .py_2()
                    .children(rows),
            )
            .child(self.render_editor(window, cx))
            .into_any_element()
    }
}

fn human_file_size(bytes: u64) -> String {
    if bytes < 1_000 {
        return format!("{bytes} B");
    }
    if bytes < 1_000_000 {
        return format!("{:.1} KB", bytes as f64 / 1_000.0);
    }
    format!("{:.1} MB", bytes as f64 / 1_000_000.0)
}

fn language_for_path(path: &str) -> SharedString {
    let language = match extension_for_path(path) {
        "rs" => "rust",
        "dart" => "dart",
        "js" | "jsx" => "javascript",
        "ts" | "tsx" => "typescript",
        "py" => "python",
        "go" => "go",
        "json" => "json",
        "yaml" | "yml" => "yaml",
        "toml" => "toml",
        "md" | "mdx" => "markdown",
        "html" => "html",
        "css" => "css",
        "sh" | "zsh" | "bash" => "bash",
        "zig" => "zig",
        _ => "text",
    };
    language.into()
}

fn extension_for_path(path: &str) -> &str {
    Path::new(path)
        .extension()
        .and_then(|extension| extension.to_str())
        .unwrap_or_default()
}

fn is_mermaid_extension(extension: &str) -> bool {
    extension == "mmd" || extension == "mermaid"
}

fn is_image_extension(extension: &str) -> bool {
    matches!(
        extension,
        "avif"
            | "jpg"
            | "jpeg"
            | "png"
            | "gif"
            | "webp"
            | "tif"
            | "tiff"
            | "tga"
            | "dds"
            | "bmp"
            | "ico"
            | "hdr"
            | "exr"
            | "pbm"
            | "pam"
            | "ppm"
            | "pgm"
            | "ff"
            | "farbfeld"
            | "qoi"
            | "svg"
    )
}
