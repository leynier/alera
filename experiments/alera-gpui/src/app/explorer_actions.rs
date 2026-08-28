use std::path::PathBuf;

use super::workspace_surface::PreviewAsset;
use super::{AleraApp, ExplorerClipboard, ExplorerDragData, ExplorerMenuTarget};
use alera_core::child_process::windowless_command;
use gpui::{ClipboardItem, Context, Pixels, Point, Window};

impl AleraApp {
    pub(super) fn can_drop_explorer_entry(&self, source: &str, target: &str) -> bool {
        if source.is_empty() || source == target || target.starts_with(&format!("{source}/")) {
            return false;
        }
        self.explorer_rows
            .iter()
            .any(|row| row.entry.relative_path == target && row.entry.is_directory)
    }

    pub(super) fn drop_explorer_entry(
        &mut self,
        drag: &ExplorerDragData,
        target: String,
        cx: &mut Context<Self>,
    ) {
        let source = drag.relative_path.clone();
        self.explorer_drop_target = None;
        if !self.can_drop_explorer_entry(&source, &target) {
            cx.notify();
            return;
        }
        self.transfer_explorer_entry(source, target, true, cx);
    }

    pub(super) fn clear_explorer_drop_target(&mut self, cx: &mut Context<Self>) {
        if self.explorer_drop_target.take().is_some() {
            cx.notify();
        }
    }

    pub(super) fn begin_create_explorer_entry(
        &mut self,
        directory: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.begin_create_explorer_entry_at(String::new(), directory, window, cx);
    }

    pub(super) fn begin_create_explorer_entry_at(
        &mut self,
        parent_relative_path: String,
        directory: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.explorer_create_parent = parent_relative_path;
        self.explorer_create_directory = Some(directory);
        self.explorer_rename_path = None;
        self.explorer_delete_path = None;
        self.explorer_menu = None;
        self.explorer_action_busy = false;
        self.local_message = None;
        self.explorer_name_input.update(cx, |input, cx| {
            input.set_value("", window, cx);
            input.focus(window, cx);
        });
        cx.notify();
    }

    pub(super) fn begin_rename_explorer_entry(
        &mut self,
        relative_path: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(name) = self
            .explorer_rows
            .iter()
            .find(|row| row.entry.relative_path == relative_path)
            .map(|row| row.entry.name.clone())
        else {
            return;
        };
        self.explorer_create_directory = None;
        self.explorer_delete_path = None;
        self.explorer_rename_path = Some(relative_path);
        self.explorer_menu = None;
        self.explorer_action_busy = false;
        self.local_message = None;
        self.explorer_name_input.update(cx, |input, cx| {
            input.set_value(name, window, cx);
            input.focus(window, cx);
        });
        cx.notify();
    }

    pub(super) fn begin_delete_explorer_entry(
        &mut self,
        relative_path: String,
        cx: &mut Context<Self>,
    ) {
        self.explorer_create_directory = None;
        self.explorer_rename_path = None;
        self.explorer_delete_path = Some(relative_path);
        self.explorer_menu = None;
        self.explorer_action_busy = false;
        self.local_message = None;
        cx.notify();
    }

    pub(super) fn close_explorer_dialog(&mut self, cx: &mut Context<Self>) {
        if self.explorer_action_busy {
            return;
        }
        self.explorer_create_directory = None;
        self.explorer_rename_path = None;
        self.explorer_delete_path = None;
        self.local_message = None;
        cx.notify();
    }

    pub(super) fn submit_explorer_dialog(&mut self, cx: &mut Context<Self>) {
        if self.explorer_action_busy {
            return;
        }
        if let Some(directory) = self.explorer_create_directory {
            self.create_explorer_entry(directory, cx);
        } else if let Some(relative_path) = self.explorer_rename_path.clone() {
            self.rename_explorer_entry(relative_path, cx);
        } else if let Some(relative_path) = self.explorer_delete_path.clone() {
            self.delete_explorer_entry(relative_path, cx);
        }
    }

    fn create_explorer_entry(&mut self, directory: bool, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        let name = self.explorer_name_input.read(cx).value().trim().to_owned();
        if name.is_empty() {
            // Flutter closes the name prompt when the submitted value is empty.
            // Do not turn an empty dismissal into an inline validation error.
            self.explorer_create_directory = None;
            self.local_message = None;
            cx.notify();
            return;
        }
        self.explorer_action_busy = true;
        self.local_message = None;
        let service = self.workspace_service.clone();
        let parent = self.explorer_create_parent.clone();
        cx.spawn(async move |this, cx| {
            let result = service
                .create(workspace_path, parent, name, directory)
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.explorer_action_busy = false;
                match result {
                    Ok(entry) => {
                        this.explorer_create_directory = None;
                        this.explorer_selected_path = Some(entry.relative_path);
                        this.load_root_directory(cx);
                    }
                    Err(error) => {
                        // The Flutter prompt has already been dismissed when the
                        // filesystem request returns. Keep only the global toast;
                        // rendering the error inside the dialog duplicates it.
                        this.explorer_create_directory = None;
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    fn rename_explorer_entry(&mut self, relative_path: String, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        let new_name = self.explorer_name_input.read(cx).value().trim().to_owned();
        if new_name.is_empty() {
            self.explorer_rename_path = None;
            self.local_message = None;
            cx.notify();
            return;
        }
        self.explorer_action_busy = true;
        self.local_message = None;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service
                .rename(workspace_path, relative_path.clone(), new_name)
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.explorer_action_busy = false;
                match result {
                    Ok(entry) => {
                        let next_path = entry.relative_path;
                        this.rewrite_opened_explorer_path(&relative_path, &next_path, cx);
                        this.sync_source_control_root_after_path_move(
                            &relative_path,
                            &next_path,
                            cx,
                        );
                        this.explorer_selected_path = Some(next_path);
                        this.explorer_rename_path = None;
                        this.load_root_directory(cx);
                    }
                    Err(error) => {
                        this.explorer_rename_path = None;
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    fn delete_explorer_entry(&mut self, relative_path: String, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.explorer_action_busy = true;
        self.local_message = None;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.delete(workspace_path, relative_path.clone()).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.explorer_action_busy = false;
                match result {
                    Ok(()) => {
                        this.explorer_delete_path = None;
                        this.explorer_selected_path = None;
                        if this
                            .opened_file_path
                            .as_deref()
                            .is_some_and(|path| path_is_same_or_child(path, &relative_path))
                        {
                            this.editor_document = None;
                            this.opened_file_path = None;
                            this.preview_asset = None;
                            this.editor_dirty = false;
                        }
                        this.editor_documents
                            .retain(|path, _| !path_is_same_or_child(path, &relative_path));
                        this.editor_error_messages
                            .retain(|path, _| !path_is_same_or_child(path, &relative_path));
                        this.editor_preview_assets
                            .retain(|path, _| !path_is_same_or_child(path, &relative_path));
                        this.markdown_preview_content
                            .retain(|path, _| !path_is_same_or_child(path, &relative_path));
                        this.editor_buffer_text
                            .retain(|path, _| !path_is_same_or_child(path, &relative_path));
                        this.editor_dirty_paths
                            .retain(|path| !path_is_same_or_child(path, &relative_path));
                        this.editor_cursor_positions
                            .retain(|path, _| !path_is_same_or_child(path, &relative_path));
                        this.clear_source_control_root_if_deleted(&relative_path, cx);
                        this.load_root_directory(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn show_explorer_menu(
        &mut self,
        target: ExplorerMenuTarget,
        position: Point<Pixels>,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        if let ExplorerMenuTarget::Entry(path) = &target {
            self.explorer_selected_path = Some(path.clone());
        }
        self.explorer_menu = Some(target);
        self.explorer_menu_position = position;
        self.explorer_menu_previous_focus = window.focused(cx);
        self.explorer_menu_focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn dismiss_explorer_menu(
        &mut self,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        if self.explorer_menu.take().is_some() {
            if let Some(focus) = self.explorer_menu_previous_focus.take() {
                focus.focus(window, cx);
            }
            cx.notify();
        }
    }

    pub(super) fn select_explorer_entry(&mut self, relative_path: String) {
        self.explorer_selected_path = Some(relative_path);
    }

    pub(super) fn copy_explorer_entry(
        &mut self,
        relative_path: String,
        cut: bool,
        cx: &mut Context<Self>,
    ) {
        self.explorer_clipboard = Some(ExplorerClipboard { relative_path, cut });
        self.explorer_menu = None;
        self.local_message = None;
        cx.notify();
    }

    pub(super) fn copy_explorer_path(
        &mut self,
        relative_path: String,
        absolute: bool,
        cx: &mut Context<Self>,
    ) {
        let value = if absolute {
            self.absolute_explorer_path(&relative_path)
        } else {
            relative_path
        };
        cx.write_to_clipboard(ClipboardItem::new_string(value));
        self.explorer_menu = None;
        self.local_message = Some(
            if absolute {
                "Path copied"
            } else {
                "Relative path copied"
            }
            .into(),
        );
        cx.notify();
    }

    pub(super) fn paste_explorer_entry(
        &mut self,
        target_relative_path: Option<String>,
        cx: &mut Context<Self>,
    ) {
        let Some(clipboard) = self.explorer_clipboard.clone() else {
            self.explorer_menu = None;
            cx.notify();
            return;
        };
        let target_parent = self.explorer_target_directory(target_relative_path.as_deref());
        self.transfer_explorer_entry(clipboard.relative_path, target_parent, clipboard.cut, cx);
    }

    pub(super) fn duplicate_explorer_entry(
        &mut self,
        relative_path: String,
        cx: &mut Context<Self>,
    ) {
        let target_parent = parent_path(&relative_path).to_owned();
        self.transfer_explorer_entry(relative_path, target_parent, false, cx);
    }

    fn transfer_explorer_entry(
        &mut self,
        relative_path: String,
        target_parent: String,
        move_entry: bool,
        cx: &mut Context<Self>,
    ) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.explorer_action_busy = true;
        self.explorer_menu = None;
        self.local_message = None;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = if move_entry {
                service
                    .move_entry(workspace_path, relative_path.clone(), target_parent)
                    .await
            } else {
                service
                    .copy(workspace_path, relative_path.clone(), target_parent)
                    .await
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.explorer_action_busy = false;
                match result {
                    Ok(entry) => {
                        let next_path = entry.relative_path;
                        if move_entry {
                            this.rewrite_opened_explorer_path(&relative_path, &next_path, cx);
                            this.sync_source_control_root_after_path_move(
                                &relative_path,
                                &next_path,
                                cx,
                            );
                            this.explorer_clipboard = None;
                        }
                        this.explorer_selected_path = Some(next_path);
                        this.load_root_directory(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn reveal_explorer_entry(&mut self, relative_path: String, cx: &mut Context<Self>) {
        let path = self.absolute_explorer_path(&relative_path);
        self.explorer_menu = None;
        cx.spawn(async move |this, cx| {
            let result = reveal_in_file_manager(PathBuf::from(path));
            if let Err(message) = result {
                let _ = this.update(cx, |this, cx| {
                    this.local_message = Some(message.into());
                    cx.notify();
                });
            }
        })
        .detach();
        cx.notify();
    }

    pub(super) fn collapse_explorer_entry(
        &mut self,
        relative_path: String,
        cx: &mut Context<Self>,
    ) {
        let Some(row) = self
            .explorer_rows
            .iter()
            .find(|row| row.entry.relative_path == relative_path)
        else {
            self.explorer_menu = None;
            cx.notify();
            return;
        };
        if row.entry.is_directory && row.expanded {
            self.toggle_directory(relative_path, cx);
        }
        self.explorer_menu = None;
        cx.notify();
    }

    pub(super) fn refresh_explorer_entry(&mut self, cx: &mut Context<Self>) {
        self.explorer_menu = None;
        self.load_root_directory(cx);
    }

    pub(super) fn explorer_target_directory(&self, relative_path: Option<&str>) -> String {
        let Some(relative_path) = relative_path else {
            return String::new();
        };
        self.explorer_rows
            .iter()
            .find(|row| row.entry.relative_path == relative_path)
            .filter(|row| row.entry.is_directory)
            .map_or_else(
                || parent_path(relative_path).to_owned(),
                |_| relative_path.to_owned(),
            )
    }

    pub(super) fn absolute_explorer_path(&self, relative_path: &str) -> String {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return relative_path.to_owned();
        };
        PathBuf::from(workspace_path)
            .join(relative_path)
            .to_string_lossy()
            .into_owned()
    }

    fn rewrite_opened_explorer_path(&mut self, previous: &str, next: &str, cx: &mut Context<Self>) {
        let Some(opened) = self.opened_file_path.clone() else {
            return;
        };
        if !path_is_same_or_child(&opened, previous) {
            return;
        }
        let suffix = opened.strip_prefix(previous).unwrap_or_default();
        let next_path = format!("{next}{suffix}");
        self.opened_file_path = Some(next_path.clone());
        if let Some(document) = &mut self.editor_document {
            document.relative_path = next_path;
        }
        rewrite_cached_editor_paths(&mut self.editor_documents, previous, next);
        rewrite_cached_preview_paths(&mut self.editor_preview_assets, previous, next);
        rewrite_cached_text_paths(&mut self.markdown_preview_content, previous, next);
        rewrite_cached_text_paths(&mut self.editor_buffer_text, previous, next);
        rewrite_dirty_paths(&mut self.editor_dirty_paths, previous, next);
        rewrite_cursor_paths(&mut self.editor_cursor_positions, previous, next);
        cx.notify();
    }
}

fn parent_path(relative_path: &str) -> &str {
    relative_path
        .rsplit_once('/')
        .map_or("", |(parent, _)| parent)
}

fn path_is_same_or_child(path: &str, parent: &str) -> bool {
    path == parent
        || path
            .strip_prefix(parent)
            .is_some_and(|suffix| suffix.starts_with('/'))
}

fn reveal_in_file_manager(path: PathBuf) -> Result<(), String> {
    if !path.exists() {
        return Err("Path was not found.".to_owned());
    }

    #[cfg(target_os = "macos")]
    let mut command = {
        let mut command = windowless_command("open");
        command.arg("-R").arg(path.as_os_str());
        command
    };

    #[cfg(target_os = "windows")]
    let mut command = {
        let mut command = windowless_command("explorer.exe");
        command.arg(format!("/select,{}", path.to_string_lossy()));
        command
    };

    #[cfg(target_os = "linux")]
    let mut command = {
        let target = if path.is_dir() {
            path.clone()
        } else {
            path.parent().unwrap_or(path.as_path()).to_path_buf()
        };
        let mut command = windowless_command("xdg-open");
        command.arg(target);
        command
    };

    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    let mut command = {
        let mut command = windowless_command("xdg-open");
        command.arg(path);
        command
    };

    let status = command.status().map_err(|_| file_manager_reveal_error())?;
    status
        .success()
        .then_some(())
        .ok_or_else(file_manager_reveal_error)
}

fn file_manager_reveal_error() -> String {
    if cfg!(target_os = "macos") {
        "Could not reveal item in Finder.".to_owned()
    } else if cfg!(target_os = "windows") {
        "Could not reveal item in Explorer.".to_owned()
    } else {
        "Could not reveal item in File Manager.".to_owned()
    }
}

fn rewrite_cached_editor_paths(
    documents: &mut std::collections::BTreeMap<String, crate::workspace_service::EditorDocument>,
    previous: &str,
    next: &str,
) {
    let paths = documents
        .keys()
        .filter(|path| path_is_same_or_child(path, previous))
        .cloned()
        .collect::<Vec<_>>();
    for path in paths {
        let Some(mut document) = documents.remove(&path) else {
            continue;
        };
        let suffix = path.strip_prefix(previous).unwrap_or_default();
        let updated = format!("{next}{suffix}");
        document.relative_path = updated.clone();
        documents.insert(updated, document);
    }
}

fn rewrite_cached_preview_paths(
    previews: &mut std::collections::BTreeMap<String, PreviewAsset>,
    previous: &str,
    next: &str,
) {
    let paths = previews
        .keys()
        .filter(|path| path_is_same_or_child(path, previous))
        .cloned()
        .collect::<Vec<_>>();
    for path in paths {
        let Some(asset) = previews.remove(&path) else {
            continue;
        };
        let suffix = path.strip_prefix(previous).unwrap_or_default();
        previews.insert(format!("{next}{suffix}"), asset);
    }
}

fn rewrite_cached_text_paths(
    buffers: &mut std::collections::BTreeMap<String, String>,
    previous: &str,
    next: &str,
) {
    let paths = buffers
        .keys()
        .filter(|path| path_is_same_or_child(path, previous))
        .cloned()
        .collect::<Vec<_>>();
    for path in paths {
        let Some(text) = buffers.remove(&path) else {
            continue;
        };
        let suffix = path.strip_prefix(previous).unwrap_or_default();
        buffers.insert(format!("{next}{suffix}"), text);
    }
}

fn rewrite_dirty_paths(paths: &mut std::collections::BTreeSet<String>, previous: &str, next: &str) {
    let matching = paths
        .iter()
        .filter(|path| path_is_same_or_child(path, previous))
        .cloned()
        .collect::<Vec<_>>();
    for path in matching {
        paths.remove(&path);
        let suffix = path.strip_prefix(previous).unwrap_or_default();
        paths.insert(format!("{next}{suffix}"));
    }
}

fn rewrite_cursor_paths(
    positions: &mut std::collections::BTreeMap<String, (u32, u32)>,
    previous: &str,
    next: &str,
) {
    let matching = positions
        .keys()
        .filter(|path| path_is_same_or_child(path, previous))
        .cloned()
        .collect::<Vec<_>>();
    for path in matching {
        let Some(position) = positions.remove(&path) else {
            continue;
        };
        let suffix = path.strip_prefix(previous).unwrap_or_default();
        positions.insert(format!("{next}{suffix}"), position);
    }
}
