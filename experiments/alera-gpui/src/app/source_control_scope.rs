use std::path::{Path, PathBuf};

use gpui::{Context, SharedString};
use serde_json::{json, Map, Value};

use super::AleraApp;
use crate::activity::ContextPanel;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct SourceControlScope {
    pub workspace_id: String,
    pub workspace_path: String,
    pub path: String,
    pub relative_root: Option<String>,
}

impl SourceControlScope {
    pub(super) fn to_source_relative_path(&self, workspace_relative_path: &str) -> Option<String> {
        let Some(root) = self.relative_root.as_deref() else {
            return normalize_workspace_relative_path(workspace_relative_path);
        };
        let normalized = normalize_workspace_relative_path(workspace_relative_path)?;
        if normalized == root {
            return Some(String::new());
        }
        normalized
            .strip_prefix(&format!("{root}/"))
            .map(str::to_owned)
    }

    pub(super) fn to_workspace_relative_path(&self, source_relative_path: &str) -> Option<String> {
        let Some(root) = self.relative_root.as_deref() else {
            return normalize_workspace_relative_path(source_relative_path);
        };
        match normalize_workspace_relative_path(source_relative_path) {
            Some(path) => Some(format!("{root}/{path}")),
            None if source_relative_path.is_empty() => Some(root.to_owned()),
            None => None,
        }
    }
}

impl AleraApp {
    pub(super) fn selected_source_control_scope(&self) -> Option<SourceControlScope> {
        let workspace_id = self.selected_workspace_id.as_deref()?;
        let workspace = self.snapshot.workspace(workspace_id)?;
        let project = self.snapshot.project_for_workspace(workspace_id)?;
        let relative_root = if project.kind == "gitRepository" {
            None
        } else if project.kind == "folder" {
            self.source_control_root_for_workspace(workspace_id)
        } else {
            return None;
        };
        if project.kind == "folder" && relative_root.is_none() {
            return None;
        }
        let path = relative_root.as_deref().map_or_else(
            || workspace.path.clone(),
            |root| {
                PathBuf::from(&workspace.path)
                    .join(root)
                    .to_string_lossy()
                    .into_owned()
            },
        );
        Some(SourceControlScope {
            workspace_id: workspace.id.clone(),
            workspace_path: workspace.path.clone(),
            path,
            relative_root,
        })
    }

    pub(super) fn selected_source_control_path(&self) -> Option<String> {
        self.selected_source_control_scope().map(|scope| scope.path)
    }

    pub(super) fn source_control_scope_for_root(
        &self,
        relative_root: Option<&str>,
    ) -> Option<SourceControlScope> {
        let workspace_id = self.selected_workspace_id.as_deref()?;
        let workspace = self.snapshot.workspace(workspace_id)?;
        let relative_root = relative_root.and_then(normalize_source_control_root_relative_path);
        let path = relative_root.as_deref().map_or_else(
            || workspace.path.clone(),
            |root| {
                PathBuf::from(&workspace.path)
                    .join(root)
                    .to_string_lossy()
                    .into_owned()
            },
        );
        Some(SourceControlScope {
            workspace_id: workspace.id.clone(),
            workspace_path: workspace.path.clone(),
            path,
            relative_root,
        })
    }

    pub(super) fn selected_source_control_root(&self) -> Option<String> {
        self.selected_source_control_scope()?.relative_root
    }

    pub(super) fn can_focus_source_control_folders(&self) -> bool {
        self.selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.project_for_workspace(id))
            .is_some_and(|project| project.kind == "folder")
    }

    pub(super) fn is_focused_source_control_root(&self, relative_path: &str) -> bool {
        self.selected_source_control_root().as_deref() == Some(relative_path)
    }

    pub(super) fn focus_source_control_root(
        &mut self,
        relative_path: String,
        cx: &mut Context<Self>,
    ) {
        if !self.can_focus_source_control_folders() {
            return;
        }
        let Some(normalized) = normalize_source_control_root_relative_path(&relative_path) else {
            self.local_message = Some("Folder Is Not A Git Repository".into());
            self.explorer_menu = None;
            cx.notify();
            return;
        };
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        let candidate = PathBuf::from(&workspace_path).join(&normalized);
        if !has_direct_git_entry(&candidate) {
            self.local_message = Some("Folder Is Not A Git Repository".into());
            self.explorer_menu = None;
            cx.notify();
            return;
        }

        self.explorer_menu = None;
        self.local_busy = true;
        self.local_message = None;
        let service = self.workspace_service.clone();
        let candidate_path = candidate.to_string_lossy().into_owned();
        cx.spawn(async move |this, cx| {
            let result = service.git_snapshot(candidate_path).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.local_busy = false;
                match result {
                    Ok(snapshot) => {
                        this.set_source_control_root_for_workspace(
                            &workspace_id,
                            Some(normalized.clone()),
                        );
                        this.git_snapshot = snapshot;
                        this.context_panel = ContextPanel::SourceControl;
                        this.context_sidebar_collapsed = false;
                        this.local_message = None;
                        this.persist_sidebar_view_prefs(cx);
                        this.refresh_forge(cx);
                    }
                    Err(_) => {
                        this.local_message = Some("Folder Is Not A Git Repository".into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn clear_source_control_root(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        if self
            .source_control_root_for_workspace(&workspace_id)
            .is_none()
        {
            return;
        }
        self.set_source_control_root_for_workspace(&workspace_id, None);
        self.explorer_menu = None;
        self.git_snapshot = Default::default();
        self.forge_snapshot = Default::default();
        if matches!(
            self.context_panel,
            ContextPanel::SourceControl | ContextPanel::PullRequest
        ) {
            self.context_panel = ContextPanel::Explorer;
            self.load_root_directory(cx);
        }
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn sync_source_control_root_after_path_move(
        &mut self,
        old_relative_path: &str,
        new_relative_path: &str,
        cx: &mut Context<Self>,
    ) {
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let Some(current) = self.source_control_root_for_workspace(&workspace_id) else {
            return;
        };
        let Some(next) = replace_path_prefix(&current, old_relative_path, new_relative_path) else {
            return;
        };
        if next == current {
            return;
        }
        self.set_source_control_root_for_workspace(&workspace_id, Some(next));
        self.persist_sidebar_view_prefs(cx);
    }

    pub(super) fn clear_source_control_root_if_deleted(
        &mut self,
        deleted_relative_path: &str,
        cx: &mut Context<Self>,
    ) {
        let Some(root) = self.selected_source_control_root() else {
            return;
        };
        if path_is_same_or_child(&root, deleted_relative_path) {
            self.clear_source_control_root(cx);
        }
    }

    fn source_control_root_for_workspace(&self, workspace_id: &str) -> Option<String> {
        self.workbench_view_prefs_raw
            .get("sourceControlRootByWorkspaceId")
            .and_then(Value::as_object)
            .and_then(|roots| roots.get(workspace_id))
            .and_then(Value::as_str)
            .and_then(normalize_source_control_root_relative_path)
    }

    fn set_source_control_root_for_workspace(
        &mut self,
        workspace_id: &str,
        relative_root: Option<String>,
    ) {
        if !self.workbench_view_prefs_raw.is_object() {
            self.workbench_view_prefs_raw = json!({});
        }
        let prefs = self
            .workbench_view_prefs_raw
            .as_object_mut()
            .expect("view prefs must be an object");
        let roots = prefs
            .entry("sourceControlRootByWorkspaceId")
            .or_insert_with(|| Value::Object(Map::new()));
        if !roots.is_object() {
            *roots = Value::Object(Map::new());
        }
        let roots = roots
            .as_object_mut()
            .expect("source roots must be an object");
        if let Some(relative_root) = relative_root {
            roots.insert(workspace_id.to_owned(), Value::String(relative_root));
        } else {
            roots.remove(workspace_id);
        }
    }

    pub(super) fn ensure_context_panel_has_source_control(&mut self) {
        if self.selected_source_control_scope().is_none()
            && matches!(
                self.context_panel,
                ContextPanel::SourceControl | ContextPanel::PullRequest
            )
        {
            self.context_panel = ContextPanel::Explorer;
        }
    }

    pub(super) fn source_control_unavailable_message(&mut self, cx: &mut Context<Self>) {
        self.local_message = Some(SharedString::from(
            "Choose A Git Folder In Explorer To Use Source Control",
        ));
        cx.notify();
    }
}

pub(super) fn normalize_source_control_root_relative_path(value: &str) -> Option<String> {
    let normalized = normalize_workspace_relative_path(value)?;
    (!normalized.is_empty()).then_some(normalized)
}

pub(super) fn normalize_workspace_relative_path(value: &str) -> Option<String> {
    if value.is_empty() {
        return None;
    }
    let value = value.replace('\\', "/");
    if value.starts_with('/') || has_windows_drive_prefix(&value) {
        return None;
    }
    let mut parts = Vec::new();
    for part in value.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            part => parts.push(part),
        }
    }
    (!parts.is_empty()).then(|| parts.join("/"))
}

fn has_windows_drive_prefix(value: &str) -> bool {
    value.as_bytes().get(1).copied() == Some(b':')
}

fn has_direct_git_entry(path: &Path) -> bool {
    path.join(".git").exists()
}

fn replace_path_prefix(path: &str, old_path: &str, new_path: &str) -> Option<String> {
    let path = normalize_source_control_root_relative_path(path)?;
    let old_path = normalize_source_control_root_relative_path(old_path)?;
    let new_path = normalize_source_control_root_relative_path(new_path)?;
    if path == old_path {
        return Some(new_path);
    }
    path.strip_prefix(&format!("{old_path}/"))
        .map(|suffix| format!("{new_path}/{suffix}"))
}

fn path_is_same_or_child(path: &str, parent: &str) -> bool {
    path == parent
        || path
            .strip_prefix(parent)
            .is_some_and(|suffix| suffix.starts_with('/'))
}

#[cfg(test)]
mod tests {
    use super::{
        normalize_source_control_root_relative_path, replace_path_prefix, SourceControlScope,
    };

    #[test]
    fn normalizes_safe_source_control_roots() {
        assert_eq!(
            normalize_source_control_root_relative_path("apps\\desktop/./native"),
            Some("apps/desktop/native".to_owned())
        );
        assert_eq!(
            normalize_source_control_root_relative_path("../outside"),
            None
        );
        assert_eq!(
            normalize_source_control_root_relative_path("/outside"),
            None
        );
        assert_eq!(
            normalize_source_control_root_relative_path("C:\\outside"),
            None
        );
    }

    #[test]
    fn maps_paths_between_workspace_and_source_scope() {
        let scope = SourceControlScope {
            workspace_id: "workspace".to_owned(),
            workspace_path: "/repo".to_owned(),
            path: "/repo/apps/desktop".to_owned(),
            relative_root: Some("apps/desktop".to_owned()),
        };
        assert_eq!(
            scope.to_source_relative_path("apps/desktop/src/main.rs"),
            Some("src/main.rs".to_owned())
        );
        assert_eq!(
            scope.to_workspace_relative_path("src/main.rs"),
            Some("apps/desktop/src/main.rs".to_owned())
        );
        assert_eq!(scope.to_source_relative_path("other/file.rs"), None);
    }

    #[test]
    fn moves_nested_roots_with_their_parent() {
        assert_eq!(
            replace_path_prefix("apps/client/repo", "apps", "packages"),
            Some("packages/client/repo".to_owned())
        );
        assert_eq!(replace_path_prefix("apps/client", "server", "api"), None);
    }
}
