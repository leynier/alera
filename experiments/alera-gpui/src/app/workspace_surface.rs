use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, Image, ImageFormat,
    InteractiveElement as _, IntoElement as _, MouseButton, MouseDownEvent, ParentElement as _,
    SharedString, StatefulInteractiveElement as _, Styled as _, Timer, Window,
};

use super::{AleraApp, ExplorerMenuTarget};
use crate::activity::ContextPanel;
use crate::file_icons::file_icon;
use crate::icons::{icon, loading_indicator, AleraIcon};
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
    Image(Arc<Image>),
}

enum OpenFileResult {
    Text {
        document: crate::workspace_service::EditorDocument,
        preview: Option<PreviewAsset>,
    },
    Image {
        relative_path: String,
        image: Arc<Image>,
    },
}

impl AleraApp {
    pub(super) fn refresh_local_activity(&mut self, cx: &mut Context<Self>) {
        match self.context_panel {
            ContextPanel::Explorer => self.load_root_directory(cx),
            ContextPanel::SourceControl => self.refresh_git(cx),
            ContextPanel::PullRequest => self.refresh_forge(cx),
            ContextPanel::Search => {}
        }
    }

    pub(super) fn ensure_explorer_watcher(&mut self, cx: &mut Context<Self>) {
        self.explorer_watch_generation = self.explorer_watch_generation.wrapping_add(1);
        let generation = self.explorer_watch_generation;
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        cx.spawn(async move |this, cx| loop {
            Timer::after(Duration::from_secs(2)).await;
            let Some(this) = this.upgrade() else {
                break;
            };
            let should_continue = this
                .update(cx, |this, cx| {
                    if generation != this.explorer_watch_generation
                        || this.context_panel != ContextPanel::Explorer
                        || this.selected_workspace_id.as_deref() != Some(workspace_id.as_str())
                    {
                        return false;
                    }
                    if !this.local_busy {
                        this.load_root_directory(cx);
                    }
                    true
                })
                .unwrap_or(false);
            if !should_continue {
                break;
            }
        })
        .detach();
    }

    pub(super) fn reset_local_workspace(&mut self, cx: &mut Context<Self>) {
        self.local_generation += 1;
        self.explorer_watch_generation = self.explorer_watch_generation.wrapping_add(1);
        self.explorer_rows.clear();
        self.explorer_menu = None;
        self.explorer_selected_path = None;
        self.explorer_clipboard = None;
        self.explorer_create_directory = None;
        self.explorer_rename_path = None;
        self.explorer_delete_path = None;
        self.editor_document = None;
        self.opened_file_path = None;
        self.editor_loading_path = None;
        self.preview_asset = None;
        self.show_preview = false;
        self.editor_dirty = false;
        self.editor_conflict = false;
        self.search_results = Default::default();
        self.replace_confirmation = None;
        self.git_snapshot = Default::default();
        self.git_discard_armed = false;
        self.git_discard_path_armed = None;
        self.forge_snapshot = Default::default();
        self.forge_review_action = None;
        self.forge_review_action_menu_open = false;
        self.forge_review_confirmation = None;
        self.forge_review_editing = false;
        self.forge_review_base_menu_open = false;
        self.forge_expanded_checks.clear();
        self.forge_collapsed_check_groups.clear();
        self.local_message = None;
        self.refresh_local_activity(cx);
    }

    pub(super) fn selected_workspace_path(&self) -> Option<String> {
        self.selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.workspace(id))
            .map(|workspace| workspace.path.clone())
    }

    pub(super) fn load_root_directory(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        self.local_message = None;
        let service = self.workspace_service.clone();
        let hide_ignored = self.explorer_hide_ignored;
        cx.spawn(async move |this, cx| {
            let result = service
                .list(workspace_path, String::new(), hide_ignored)
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

    pub(super) fn toggle_directory(&mut self, relative_path: String, cx: &mut Context<Self>) {
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
        let hide_ignored = self.explorer_hide_ignored;
        cx.spawn(async move |this, cx| {
            let result = service
                .list(workspace_path, relative_path.clone(), hide_ignored)
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

    pub(super) fn collapse_all_explorer_directories(&mut self, cx: &mut Context<Self>) {
        self.explorer_rows.retain(|row| row.depth == 0);
        for row in &mut self.explorer_rows {
            row.expanded = false;
        }
        cx.notify();
    }

    pub(super) fn toggle_explorer_ignored_files(&mut self, cx: &mut Context<Self>) {
        self.explorer_hide_ignored = !self.explorer_hide_ignored;
        self.persist_sidebar_view_prefs(cx);
        self.load_root_directory(cx);
    }

    pub(super) fn open_workspace_file(
        &mut self,
        relative_path: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.open_editor_tab(relative_path.clone(), cx);
        self.load_workspace_file(relative_path, window, cx);
    }

    pub(super) fn ensure_selected_editor_loaded(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(tab) = self
            .selected_tab_id
            .as_ref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| &tab.id == selected))
        else {
            return;
        };
        if tab.kind != "editor" && tab.kind != "markdownViewer" {
            return;
        }
        let Some(relative_path) = tab
            .payload
            .get("filePath")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned)
        else {
            return;
        };
        if self.opened_file_path.as_deref() == Some(relative_path.as_str())
            || self.editor_loading_path.as_deref() == Some(relative_path.as_str())
        {
            return;
        }
        self.load_workspace_file(relative_path, window, cx);
    }

    fn load_workspace_file(
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
        self.editor_loading_path = Some(relative_path.clone());
        self.local_message = Some(format!("Opening {relative_path}").into());
        let service = self.workspace_service.clone();
        let requested_path = relative_path.clone();
        cx.spawn_in(window, async move |this, cx| {
            let extension = extension_for_path(&relative_path);
            let result = if is_image_extension(extension) {
                service
                    .image(workspace_path, relative_path.clone())
                    .await
                    .and_then(|image| {
                        image_format(&image.format).map(|format| OpenFileResult::Image {
                            relative_path,
                            image: Arc::new(Image::from_bytes(format, image.bytes)),
                        })
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
                        this.editor_loading_path = None;
                        let language = language_for_path(&document.relative_path);
                        let display_content = document.display_content.clone();
                        this.editor_input.update(cx, |input, cx| {
                            input.set_highlighter(language, cx);
                            input.set_value(display_content, window, cx);
                            if let Some((_, line, column, _)) = this
                                .pending_editor_cursor
                                .as_ref()
                                .filter(|(path, _, _, _)| path == &document.relative_path)
                            {
                                input.set_cursor_position(
                                    gpui_component::input::Position::new(
                                        *line as u32,
                                        *column as u32,
                                    ),
                                    window,
                                    cx,
                                );
                            }
                        });
                        if this
                            .pending_editor_cursor
                            .as_ref()
                            .is_some_and(|(path, _, _, _)| path == &document.relative_path)
                        {
                            let selection_length = this
                                .pending_editor_cursor
                                .take()
                                .map_or(0, |(_, _, _, length)| length);
                            let select_right = gpui::Keystroke::parse("shift-right")
                                .expect("shift-right must be a valid GPUI keystroke");
                            let editor_input = this.editor_input.clone();
                            window.on_next_frame(move |window, cx| {
                                editor_input.update(cx, |input, cx| input.focus(window, cx));
                                for _ in 0..selection_length {
                                    window.dispatch_keystroke(select_right.clone(), cx);
                                }
                            });
                        }
                        this.opened_file_path = Some(document.relative_path.clone());
                        this.editor_document = Some(document);
                        this.show_preview = false;
                        this.preview_asset = preview;
                        this.editor_dirty = false;
                        this.editor_conflict = false;
                        this.local_message = None;
                    }
                    Ok(OpenFileResult::Image {
                        relative_path,
                        image,
                    }) => {
                        this.editor_loading_path = None;
                        this.opened_file_path = Some(relative_path);
                        this.editor_document = None;
                        this.preview_asset = Some(PreviewAsset::Image(image));
                        this.show_preview = true;
                        this.editor_dirty = false;
                        this.editor_conflict = false;
                        this.local_message = None;
                    }
                    Err(error) => {
                        this.editor_loading_path = Some(requested_path);
                        this.local_message = Some(error.into());
                    }
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
                        this.editor_conflict = false;
                        this.local_message = Some("Saved".into());
                    }
                    Err(error) if super::editor_actions::is_editor_conflict(&error) => {
                        this.editor_conflict = true;
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_explorer_panel(
        &self,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let rows = self
            .explorer_rows
            .iter()
            .enumerate()
            .map(|(index, row)| {
                let path = row.entry.relative_path.clone();
                let is_directory = row.entry.is_directory;
                let name = row.entry.name.clone();
                let expanded = row.expanded;
                let is_symlink = row.entry.is_symlink;
                let is_faint = row.entry.is_hidden || row.entry.is_protected;
                let status = row.entry.git_status.clone();
                let selected = self.explorer_selected_path.as_deref() == Some(path.as_str());
                let source_control_root = self.is_focused_source_control_root(&path);
                let click_path = path.clone();
                let menu_path = path;
                div()
                    .id(("explorer-row", index))
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(gpui::px(32.0))
                    .pl(gpui::px(row.depth as f32 * 16.0))
                    .pr_2()
                    .text_size(gpui::px(12.0))
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface()))
                    .when(selected, |item| item.bg(theme::surface_raised()))
                    .on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(move |this, _, window, cx| {
                            this.select_explorer_entry(click_path.clone());
                            if is_directory {
                                this.toggle_directory(click_path.clone(), cx);
                            } else {
                                this.open_workspace_file(click_path.clone(), window, cx);
                            }
                        }),
                    )
                    .on_mouse_down(
                        MouseButton::Right,
                        cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                            this.show_explorer_menu(
                                ExplorerMenuTarget::Entry(menu_path.clone()),
                                event.position,
                                cx,
                            );
                            cx.stop_propagation();
                        }),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .flex_1()
                            .overflow_hidden()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(gpui::px(24.0))
                                    .h(gpui::px(24.0))
                                    .when(is_directory, |expander| {
                                        expander.child(icon(
                                            if expanded {
                                                AleraIcon::ChevronDown
                                            } else {
                                                AleraIcon::ChevronRight
                                            },
                                            16.0,
                                            theme::text_muted(),
                                        ))
                                    }),
                            )
                            .child(file_icon(
                                &name,
                                is_directory,
                                expanded,
                                is_symlink,
                                15.0,
                                theme::text_muted(),
                            ))
                            .child(
                                div()
                                    .ml(gpui::px(6.0))
                                    .flex_1()
                                    .overflow_hidden()
                                    .text_ellipsis()
                                    .when(is_faint, |label| label.text_color(theme::text_faint()))
                                    .child(name),
                            ),
                    )
                    .when_some(status, |item, status| {
                        let color = if matches!(status.as_str(), "U" | "A") {
                            theme::success()
                        } else {
                            theme::warning()
                        };
                        item.child(div().ml_2().text_xs().text_color(color).child(status))
                    })
                    .when(source_control_root, |item| {
                        item.child(div().ml_2().child(icon(
                            AleraIcon::GitBranch,
                            14.0,
                            theme::text_muted(),
                        )))
                    })
            })
            .collect::<Vec<_>>();
        let empty_state = if self.local_busy && rows.is_empty() {
            Some(
                div()
                    .flex()
                    .items_center()
                    .justify_center()
                    .flex_1()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .child(loading_indicator(15.0, theme::text_muted()))
                            .child("Loading..."),
                    )
                    .into_any_element(),
            )
        } else if rows.is_empty() {
            self.local_message.as_ref().map(|message| {
                div()
                    .flex()
                    .flex_col()
                    .items_center()
                    .justify_center()
                    .flex_1()
                    .gap_2()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child(icon(AleraIcon::Error, 24.0, theme::danger()))
                    .child(message.clone())
                    .into_any_element()
            })
        } else {
            None
        };

        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .min_h_0()
            .child(
                div()
                    .id("explorer-tree")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .bg(theme::surface())
                    .py_1()
                    .on_mouse_down(
                        MouseButton::Right,
                        cx.listener(|this, event: &MouseDownEvent, _, cx| {
                            this.show_explorer_menu(
                                ExplorerMenuTarget::Background,
                                event.position,
                                cx,
                            );
                            cx.stop_propagation();
                        }),
                    )
                    .children(rows),
            )
            .when_some(empty_state, |panel, state| panel.child(state))
            .into_any_element()
    }
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

fn image_format(format: &str) -> Result<ImageFormat, String> {
    match format {
        "png" => Ok(ImageFormat::Png),
        "jpeg" => Ok(ImageFormat::Jpeg),
        "webp" => Ok(ImageFormat::Webp),
        "gif" => Ok(ImageFormat::Gif),
        "svg" => Ok(ImageFormat::Svg),
        "bmp" => Ok(ImageFormat::Bmp),
        "tiff" => Ok(ImageFormat::Tiff),
        _ => Err(format!("Unsupported Workspace Image Format: {format}")),
    }
}
