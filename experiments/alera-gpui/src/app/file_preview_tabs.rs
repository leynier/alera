use std::path::Path;

use gpui::Context;
use serde_json::{json, Map, Value};

use super::tab_actions::persist_layout;
use super::AleraApp;
use crate::model::{WorkbenchPaneGroup, WorkspaceTab};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum FileTabKind {
    Editor,
    MarkdownViewer,
    Pdf,
}

impl FileTabKind {
    fn key(self) -> &'static str {
        match self {
            Self::Editor => "editor",
            Self::MarkdownViewer => "markdownViewer",
            Self::Pdf => "pdf",
        }
    }

    fn fallback_title(self) -> &'static str {
        match self {
            Self::Editor => "Editor",
            Self::MarkdownViewer => "Markdown Preview",
            Self::Pdf => "PDF",
        }
    }

    fn can_retarget(self, existing: &str) -> bool {
        matches!(
            (existing, self),
            ("editor", Self::Pdf) | ("pdf", Self::Editor)
        )
    }
}

impl AleraApp {
    pub(super) fn open_file_tab(&mut self, relative_path: String, cx: &mut Context<Self>) {
        self.open_file_backed_tab(relative_path, false, cx);
    }

    pub(super) fn open_file_preview_tab(
        &mut self,
        relative_path: String,
        cx: &mut Context<Self>,
    ) {
        self.open_file_backed_tab(relative_path, true, cx);
    }

    pub(super) fn open_editor_tab(&mut self, relative_path: String, cx: &mut Context<Self>) {
        self.open_file_tab_with_kind(relative_path, FileTabKind::Editor, false, cx);
    }

    pub(super) fn open_markdown_viewer_tab(
        &mut self,
        relative_path: String,
        cx: &mut Context<Self>,
    ) {
        if file_tab_kind(&relative_path) != FileTabKind::MarkdownViewer {
            return;
        }
        self.open_file_tab_with_kind(relative_path, FileTabKind::MarkdownViewer, false, cx);
    }

    pub(super) fn keep_preview_tab(&mut self, tab_id: String, cx: &mut Context<Self>) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(tab) = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id && tab.is_preview())
            .cloned()
        else {
            return;
        };
        self.persist_kept_preview_tab(tab, cx);
    }

    pub(super) fn keep_preview_tab_for_path(&mut self, path: &str, cx: &mut Context<Self>) {
        if self.tab_mutation_busy {
            return;
        }
        let tab = self.snapshot.tabs.iter().find(|tab| {
            tab.is_preview()
                && tab.payload.get("filePath").and_then(Value::as_str) == Some(path)
        });
        if let Some(tab) = tab.cloned() {
            self.persist_kept_preview_tab(tab, cx);
        }
    }

    fn open_file_backed_tab(
        &mut self,
        relative_path: String,
        preview: bool,
        cx: &mut Context<Self>,
    ) {
        let kind = file_tab_kind(&relative_path);
        self.open_file_tab_with_kind(relative_path, kind, preview, cx);
    }

    fn open_file_tab_with_kind(
        &mut self,
        relative_path: String,
        kind: FileTabKind,
        preview: bool,
        cx: &mut Context<Self>,
    ) {
        if self.tab_mutation_busy {
            if !preview && self.file_preview_open_path.as_deref() == Some(relative_path.as_str()) {
                self.file_preview_keep_after_open = true;
            }
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let existing_for_path = self.snapshot.tabs.iter().find(|tab| {
            tab.workspace_id == workspace_id
                && tab.payload.get("filePath").and_then(Value::as_str)
                    == Some(relative_path.as_str())
                && tab.payload.get("fileRole").and_then(Value::as_str)
                    != Some("mermanPreview")
                && (tab.kind == kind.key() || kind.can_retarget(&tab.kind))
        });
        if let Some(existing) = existing_for_path {
            let requires_update = existing.kind != kind.key() || (!preview && existing.is_preview());
            if !requires_update || (preview && !existing.is_preview()) {
                self.activate_workspace_tab(existing.id.clone(), cx);
                return;
            }
        }

        let timestamp = chrono::Utc::now().to_rfc3339();
        let active_group_id = self
            .snapshot
            .layout
            .as_ref()
            .map(|layout| layout.active_group_id.clone());
        let preview_slot = if preview && existing_for_path.is_none() {
            active_group_id
                .as_deref()
                .and_then(|group_id| self.file_preview_tab_in_group(group_id))
                .cloned()
        } else {
            None
        };
        let pin_before_replace = preview_slot
            .as_ref()
            .filter(|tab| self.file_tab_is_dirty(tab))
            .cloned();
        let replacement = preview_slot.filter(|_| pin_before_replace.is_none());
        let existing = existing_for_path.cloned().or(replacement);
        let replacing_preview = existing_for_path.is_none() && existing.is_some();
        let tab_id = existing
            .as_ref()
            .map(|tab| tab.id.clone())
            .unwrap_or_else(|| format!("gpui-file-{}", uuid::Uuid::new_v4()));
        let title = if replacing_preview {
            file_title(&relative_path, kind)
        } else {
            existing
                .as_ref()
                .map(|tab| tab.title.clone())
                .unwrap_or_else(|| file_title(&relative_path, kind))
        };
        let payload = if replacing_preview || existing.is_none() {
            file_tab_payload(&relative_path, preview)
        } else {
            let mut payload = existing
                .as_ref()
                .and_then(|tab| tab.payload.as_object())
                .cloned()
                .unwrap_or_default();
            payload.insert("filePath".to_owned(), Value::String(relative_path.clone()));
            set_preview_payload(&mut payload, preview);
            Value::Object(payload)
        };
        let created_at = existing
            .as_ref()
            .map(|tab| tab.created_at.as_str())
            .filter(|value| !value.is_empty())
            .unwrap_or(timestamp.as_str())
            .to_owned();
        let tab_payload = json!({
            "id": tab_id,
            "workspaceId": workspace_id,
            "kind": kind.key(),
            "title": title,
            "createdAt": created_at,
            "updatedAt": timestamp,
            "payload": payload,
        });
        let mut layout = self.snapshot.layout.clone();
        if let Some(layout) = layout.as_mut() {
            if existing.is_some() {
                layout.activate_tab(&tab_id);
            } else {
                layout.add_tab_to_active_group(tab_id.clone());
            }
        }
        let bridge = self.bridge.clone();
        self.tab_mutation_busy = true;
        self.file_preview_open_path = preview.then(|| relative_path.clone());
        self.file_preview_keep_after_open = false;
        cx.spawn(async move |this, cx| {
            let result = async {
                if let Some(tab) = pin_before_replace {
                    bridge.request("tab.upsert", kept_tab_payload(&tab)).await?;
                }
                let tab = bridge.request("tab.upsert", tab_payload).await?;
                persist_layout(&bridge, layout).await?;
                Ok::<_, String>(tab)
            }
            .await;
            let _ = this.update(cx, |this, cx| {
                let keep_after_open = this.file_preview_keep_after_open
                    && this.file_preview_open_path.as_deref() == Some(relative_path.as_str());
                this.file_preview_open_path = None;
                this.file_preview_keep_after_open = false;
                match result {
                    Ok(mut tab) => {
                        this.selected_tab_id = tab
                            .get("id")
                            .and_then(Value::as_str)
                            .map(str::to_owned);
                        if keep_after_open && remove_preview_from_tab_value(&mut tab) {
                            this.persist_returned_preview_tab(tab, cx);
                        } else {
                            this.tab_mutation_busy = false;
                            this.refresh(cx);
                        }
                    }
                    Err(error) => {
                        this.tab_mutation_busy = false;
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    fn persist_kept_preview_tab(&mut self, tab: WorkspaceTab, cx: &mut Context<Self>) {
        self.tab_mutation_busy = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("tab.upsert", kept_tab_payload(&tab)).await;
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(_) => this.refresh(cx),
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    fn persist_returned_preview_tab(&mut self, tab: Value, cx: &mut Context<Self>) {
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge.request("tab.upsert", tab).await;
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(_) => this.refresh(cx),
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    fn file_preview_tab_in_group(&self, group_id: &str) -> Option<&WorkspaceTab> {
        let group = self.snapshot.layout.as_ref()?.groups.get(group_id)?;
        preview_tab_in_group(&self.snapshot.tabs, group)
    }

    fn file_tab_is_dirty(&self, tab: &WorkspaceTab) -> bool {
        let Some(path) = tab.payload.get("filePath").and_then(Value::as_str) else {
            return false;
        };
        self.editor_dirty_paths.contains(path)
            || (self.opened_file_path.as_deref() == Some(path) && self.editor_dirty)
    }
}

fn file_tab_kind(path: &str) -> FileTabKind {
    match Path::new(path)
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("md" | "mdx") => FileTabKind::MarkdownViewer,
        Some("pdf") => FileTabKind::Pdf,
        _ => FileTabKind::Editor,
    }
}

fn file_title(path: &str, kind: FileTabKind) -> String {
    Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(kind.fallback_title())
        .to_owned()
}

fn file_tab_payload(path: &str, preview: bool) -> Value {
    let mut payload = Map::new();
    payload.insert("filePath".to_owned(), Value::String(path.to_owned()));
    set_preview_payload(&mut payload, preview);
    Value::Object(payload)
}

fn set_preview_payload(payload: &mut Map<String, Value>, preview: bool) {
    if preview {
        payload.insert("preview".to_owned(), Value::Bool(true));
    } else {
        payload.remove("preview");
    }
}

fn kept_tab_payload(tab: &WorkspaceTab) -> Value {
    let mut payload = tab.payload.as_object().cloned().unwrap_or_default();
    payload.remove("preview");
    let updated_at = chrono::Utc::now().to_rfc3339();
    json!({
        "id": tab.id,
        "workspaceId": tab.workspace_id,
        "kind": tab.kind,
        "title": tab.title,
        "createdAt": if tab.created_at.is_empty() { updated_at.as_str() } else { tab.created_at.as_str() },
        "updatedAt": updated_at,
        "payload": payload,
    })
}

fn remove_preview_from_tab_value(tab: &mut Value) -> bool {
    let Some(payload) = tab.get_mut("payload").and_then(Value::as_object_mut) else {
        return false;
    };
    let removed = payload.remove("preview").is_some();
    if removed {
        tab["updatedAt"] = Value::String(chrono::Utc::now().to_rfc3339());
    }
    removed
}

fn preview_tab_in_group<'a>(
    tabs: &'a [WorkspaceTab],
    group: &WorkbenchPaneGroup,
) -> Option<&'a WorkspaceTab> {
    let tab_for_id = |tab_id: &str| {
        tabs.iter()
            .find(|tab| tab.id == tab_id && tab.is_file_preview_slot())
    };
    group
        .active_tab_id
        .as_deref()
        .and_then(tab_for_id)
        .or_else(|| group.tab_ids.iter().find_map(|tab_id| tab_for_id(tab_id)))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{file_tab_kind, preview_tab_in_group, FileTabKind};
    use crate::model::{WorkbenchPaneGroup, WorkspaceTab};

    #[test]
    fn routes_file_preview_kinds_like_flutter() {
        assert_eq!(file_tab_kind("README.md"), FileTabKind::MarkdownViewer);
        assert_eq!(file_tab_kind("docs/guide.MDX"), FileTabKind::MarkdownViewer);
        assert_eq!(file_tab_kind("docs/spec.pdf"), FileTabKind::Pdf);
        assert_eq!(file_tab_kind("src/main.rs"), FileTabKind::Editor);
    }

    #[test]
    fn active_preview_slot_is_replaced_before_an_earlier_slot() {
        let tabs = [tab("preview-a", true), tab("preview-b", true)];
        let group = WorkbenchPaneGroup {
            id: "group-a".to_owned(),
            tab_ids: vec!["preview-a".to_owned(), "preview-b".to_owned()],
            active_tab_id: Some("preview-b".to_owned()),
        };

        assert_eq!(
            preview_tab_in_group(&tabs, &group).map(|tab| tab.id.as_str()),
            Some("preview-b")
        );
    }

    #[test]
    fn permanent_tabs_are_not_preview_slots() {
        let tabs = [tab("permanent", false)];
        let group = WorkbenchPaneGroup {
            id: "group-a".to_owned(),
            tab_ids: vec!["permanent".to_owned()],
            active_tab_id: Some("permanent".to_owned()),
        };

        assert!(preview_tab_in_group(&tabs, &group).is_none());
    }

    fn tab(id: &str, preview: bool) -> WorkspaceTab {
        WorkspaceTab {
            id: id.to_owned(),
            workspace_id: "workspace-a".to_owned(),
            title: "main.rs".to_owned(),
            kind: "editor".to_owned(),
            payload: json!({"filePath": "src/main.rs", "preview": preview}),
            created_at: "2026-08-25T00:00:00Z".to_owned(),
            updated_at: "2026-08-25T00:00:00Z".to_owned(),
        }
    }
}
