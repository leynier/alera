use std::path::PathBuf;

use super::{AleraApp, ExplorerClipboard, ExplorerMenuTarget};
use gpui::{ClipboardItem, Context, Pixels, Point, Window};

impl AleraApp {
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
            self.local_message = Some("Name Is Required".into());
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
            let _ = this.update(cx, |this, cx| {
                this.explorer_action_busy = false;
                match result {
                    Ok(entry) => {
                        this.explorer_create_directory = None;
                        this.explorer_selected_path = Some(entry.relative_path);
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

    fn rename_explorer_entry(&mut self, relative_path: String, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        let new_name = self.explorer_name_input.read(cx).value().trim().to_owned();
        if new_name.is_empty() {
            self.local_message = Some("Name Is Required".into());
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
            let _ = this.update(cx, |this, cx| {
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
                        this.local_message = Some("Renamed".into());
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
            let _ = this.update(cx, |this, cx| {
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
                        this.clear_source_control_root_if_deleted(&relative_path, cx);
                        this.local_message = Some("Moved To Trash".into());
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
        cx: &mut Context<Self>,
    ) {
        if let ExplorerMenuTarget::Entry(path) = &target {
            self.explorer_selected_path = Some(path.clone());
        }
        self.explorer_menu = Some(target);
        self.explorer_menu_position = position;
        cx.notify();
    }

    pub(super) fn dismiss_explorer_menu(&mut self, cx: &mut Context<Self>) {
        if self.explorer_menu.take().is_some() {
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
        self.local_message = Some(if cut { "Ready To Move" } else { "Copied" }.into());
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
                "Path Copied"
            } else {
                "Relative Path Copied"
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
            let _ = this.update(cx, |this, cx| {
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
                        this.local_message =
                            Some(if move_entry { "Moved" } else { "Copied" }.into());
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
        let parent = parent_path(&relative_path);
        let directory = self.absolute_explorer_path(parent);
        cx.open_url(&format!("file://{}", directory.replace(' ', "%20")));
        self.explorer_menu = None;
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

    fn absolute_explorer_path(&self, relative_path: &str) -> String {
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
