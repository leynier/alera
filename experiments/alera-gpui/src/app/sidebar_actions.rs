use std::collections::BTreeSet;
use std::time::Instant;

use gpui::{ClipboardItem, Context, Pixels, Point, Window};
use serde_json::{json, Value};

use super::app_helpers::flutter_state_error;
use super::{
    AleraApp, SidebarDialog, SidebarDialogKind, SidebarGroupBy, SidebarMenu, SidebarSortBy,
    SidebarSortTarget, SidebarWorkspaceKind,
};

impl AleraApp {
    pub(super) fn toggle_pinned_section(&mut self, cx: &mut Context<Self>) {
        self.sidebar_pinned_collapsed = !self.sidebar_pinned_collapsed;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn all_project_sections_collapsed(&self) -> bool {
        if self.sidebar_group_by == SidebarGroupBy::None {
            return self.sidebar_all_collapsed;
        }
        !self.snapshot.projects.is_empty()
            && self
                .snapshot
                .projects
                .iter()
                .all(|project| self.collapsed_project_ids.contains(&project.id))
    }

    pub(super) fn toggle_all_project_sections(&mut self, cx: &mut Context<Self>) {
        if self.sidebar_group_by == SidebarGroupBy::None {
            self.sidebar_all_collapsed = !self.sidebar_all_collapsed;
            if self.sidebar_all_collapsed {
                self.sidebar_collapsed_parent_workspace_ids = self
                    .snapshot
                    .relations
                    .iter()
                    .map(|relation| relation.parent_workspace_id.clone())
                    .collect();
                self.sidebar_expanded_workspace_ids.clear();
            } else {
                self.sidebar_collapsed_parent_workspace_ids.clear();
                self.sidebar_expanded_workspace_ids.clear();
            }
            self.persist_sidebar_view_prefs(cx);
            cx.notify();
            return;
        }
        if self.all_project_sections_collapsed() {
            self.collapsed_project_ids.clear();
            self.sidebar_collapsed_parent_workspace_ids.clear();
            self.sidebar_expanded_workspace_ids.clear();
        } else {
            self.collapsed_project_ids = self
                .snapshot
                .projects
                .iter()
                .map(|project| project.id.clone())
                .collect();
            self.sidebar_collapsed_parent_workspace_ids = self
                .snapshot
                .relations
                .iter()
                .map(|relation| relation.parent_workspace_id.clone())
                .collect();
            self.sidebar_expanded_workspace_ids.clear();
        }
        self.sidebar_menu = None;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn open_sidebar_view_options(&mut self, cx: &mut Context<Self>) {
        self.show_sidebar_view_options = true;
        self.sidebar_menu = None;
        cx.notify();
    }

    pub(super) fn close_sidebar_view_options(&mut self, cx: &mut Context<Self>) {
        self.show_sidebar_view_options = false;
        self.sidebar_sort_dropdown = None;
        cx.notify();
    }

    pub(super) fn toggle_sidebar_sort_dropdown(
        &mut self,
        target: SidebarSortTarget,
        cx: &mut Context<Self>,
    ) {
        self.sidebar_sort_dropdown = if self.sidebar_sort_dropdown == Some(target) {
            None
        } else {
            Some(target)
        };
        cx.notify();
    }

    pub(super) fn set_sidebar_group_by(
        &mut self,
        group_by: SidebarGroupBy,
        cx: &mut Context<Self>,
    ) {
        self.sidebar_group_by = group_by;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn set_sidebar_project_sort(&mut self, sort: SidebarSortBy, cx: &mut Context<Self>) {
        self.sidebar_project_sort = sort;
        self.sidebar_sort_dropdown = None;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn set_sidebar_workspace_sort(
        &mut self,
        sort: SidebarSortBy,
        cx: &mut Context<Self>,
    ) {
        self.sidebar_workspace_sort = sort;
        self.sidebar_sort_dropdown = None;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn set_sidebar_workspace_kind(
        &mut self,
        kind: SidebarWorkspaceKind,
        cx: &mut Context<Self>,
    ) {
        self.sidebar_workspace_kind = kind;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn toggle_sidebar_repeat_pinned(&mut self, cx: &mut Context<Self>) {
        self.sidebar_repeat_pinned = !self.sidebar_repeat_pinned;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn toggle_sidebar_active_only(&mut self, cx: &mut Context<Self>) {
        self.sidebar_active_only = !self.sidebar_active_only;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn toggle_sidebar_project_filter(
        &mut self,
        project_id: String,
        cx: &mut Context<Self>,
    ) {
        if !self.sidebar_selected_project_ids.remove(&project_id) {
            self.sidebar_selected_project_ids.insert(project_id);
        }
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn clear_sidebar_project_filters(&mut self, cx: &mut Context<Self>) {
        self.sidebar_selected_project_ids.clear();
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn add_first_sidebar_project_filter(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let query = self
            .sidebar_project_filter_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let candidate = self
            .snapshot
            .projects
            .iter()
            .find(|project| {
                !self.sidebar_selected_project_ids.contains(&project.id)
                    && (query.is_empty() || project.name.to_lowercase().contains(&query))
            })
            .map(|project| project.id.clone());
        if let Some(project_id) = candidate {
            self.sidebar_selected_project_ids.insert(project_id);
            self.sidebar_project_filter_input
                .update(cx, |input, cx| input.set_value("", window, cx));
            self.persist_sidebar_view_prefs(cx);
            cx.notify();
        }
    }

    pub(super) fn toggle_sidebar_view_tag_filter(
        &mut self,
        tag_id: String,
        cx: &mut Context<Self>,
    ) {
        if !self.sidebar_view_selected_tag_ids.remove(&tag_id) {
            self.sidebar_view_selected_tag_ids.insert(tag_id);
        }
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn clear_sidebar_view_tag_filters(&mut self, cx: &mut Context<Self>) {
        self.sidebar_view_selected_tag_ids.clear();
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn add_first_sidebar_view_tag_filter(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let query = self
            .sidebar_view_tag_filter_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let candidate = self
            .snapshot
            .tags
            .iter()
            .find(|tag| {
                !self.sidebar_view_selected_tag_ids.contains(&tag.id)
                    && (query.is_empty() || tag.name.to_lowercase().contains(&query))
            })
            .map(|tag| tag.id.clone());
        if let Some(tag_id) = candidate {
            self.sidebar_view_selected_tag_ids.insert(tag_id);
            self.sidebar_view_tag_filter_input
                .update(cx, |input, cx| input.set_value("", window, cx));
            self.persist_sidebar_view_prefs(cx);
            cx.notify();
        }
    }

    pub(super) fn toggle_project_section(&mut self, project_id: String, cx: &mut Context<Self>) {
        if !self.collapsed_project_ids.remove(&project_id) {
            self.collapsed_project_ids.insert(project_id);
        }
        self.sidebar_menu = None;
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn toggle_parent_workspace_section(
        &mut self,
        workspace_id: String,
        cx: &mut Context<Self>,
    ) {
        if !self
            .sidebar_collapsed_parent_workspace_ids
            .remove(&workspace_id)
        {
            self.sidebar_collapsed_parent_workspace_ids
                .insert(workspace_id);
        }
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn toggle_workspace_agents(&mut self, workspace_id: String, cx: &mut Context<Self>) {
        if !self.sidebar_expanded_workspace_ids.remove(&workspace_id) {
            self.sidebar_expanded_workspace_ids.insert(workspace_id);
        }
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
    }

    pub(super) fn show_project_menu(
        &mut self,
        project_id: String,
        position: Point<Pixels>,
        cx: &mut Context<Self>,
    ) {
        self.sidebar_menu = Some(SidebarMenu::Project(project_id));
        self.sidebar_menu_position = position;
        cx.notify();
    }

    pub(super) fn show_workspace_menu(
        &mut self,
        workspace_id: String,
        position: Point<Pixels>,
        cx: &mut Context<Self>,
    ) {
        self.sidebar_menu = Some(SidebarMenu::Workspace(workspace_id));
        self.sidebar_menu_position = position;
        cx.notify();
    }

    pub(super) fn dismiss_sidebar_menu(&mut self, cx: &mut Context<Self>) {
        if self.sidebar_menu.take().is_some() {
            cx.notify();
        }
    }

    fn enqueue_sidebar_error_toasts(
        &mut self,
        primary: String,
        secondary: Option<String>,
        cx: &mut Context<Self>,
    ) {
        // Flutter exposes the controller error through its global listener and
        // the sidebar action also posts its own toast. Preserve both entries,
        // including identical messages and their order.
        self.local_message = None;
        self.local_message_started_at = None;
        self.local_message_timer_message = None;
        let shown_at = Instant::now();
        self.toast_entries.push_back((primary.into(), shown_at));
        if let Some(secondary) = secondary {
            self.toast_entries.push_back((secondary.into(), shown_at));
        }
        while self.toast_entries.len() > 3 {
            self.toast_entries.pop_front();
        }
        cx.notify();
    }

    pub(super) fn open_sidebar_dialog(
        &mut self,
        kind: SidebarDialogKind,
        target_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let initial_name = match kind {
            SidebarDialogKind::RenameProject => self
                .snapshot
                .projects
                .iter()
                .find(|project| project.id == target_id)
                .map(|project| project.name.clone()),
            SidebarDialogKind::RenameWorkspace => self
                .snapshot
                .workspace(&target_id)
                .map(|workspace| workspace.name.clone()),
            _ => None,
        }
        .unwrap_or_default();
        self.sidebar_selected_tag_ids = self
            .snapshot
            .workspace(&target_id)
            .map(|workspace| workspace.tag_ids.iter().cloned().collect())
            .unwrap_or_default();
        self.sidebar_selected_parent_id = self
            .snapshot
            .relations
            .iter()
            .find(|relation| relation.child_workspace_id == target_id)
            .map(|relation| relation.parent_workspace_id.clone());
        self.sidebar_action_input.update(cx, |input, cx| {
            input.set_value(initial_name, window, cx);
        });
        self.sidebar_tag_input.update(cx, |input, cx| {
            input.set_value("", window, cx);
        });
        self.sidebar_parent_filter_input.update(cx, |input, cx| {
            input.set_value("", window, cx);
        });
        self.sidebar_tag_delete_armed = None;
        self.sidebar_parent_dropdown_open = false;
        self.sidebar_dialog = Some(SidebarDialog { kind, target_id });
        self.sidebar_menu = None;
        self.error = None;
        cx.notify();
    }

    pub(super) fn close_sidebar_dialog(&mut self, cx: &mut Context<Self>) {
        if self.sidebar_action_busy {
            return;
        }
        self.sidebar_dialog = None;
        self.sidebar_tag_delete_armed = None;
        self.sidebar_parent_dropdown_open = false;
        self.error = None;
        cx.notify();
    }

    pub(super) fn submit_sidebar_dialog(&mut self, cx: &mut Context<Self>) {
        if self.sidebar_action_busy {
            return;
        }
        let Some(dialog) = self.sidebar_dialog.clone() else {
            return;
        };
        let name = self
            .sidebar_action_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        let operation = match dialog.kind {
            SidebarDialogKind::RenameProject => {
                if name.is_empty() {
                    self.error = Some("Project Name Is Required".into());
                    cx.notify();
                    return;
                }
                SidebarOperation::Request(
                    "project.rename",
                    json!({"id": dialog.target_id, "name": name}),
                )
            }
            SidebarDialogKind::RemoveProject => {
                SidebarOperation::Request("project.remove", json!({"id": dialog.target_id}))
            }
            SidebarDialogKind::RenameWorkspace => {
                if name.is_empty() {
                    self.error = Some("Workspace Name Is Required".into());
                    cx.notify();
                    return;
                }
                SidebarOperation::Request(
                    "workspace.rename",
                    json!({"workspaceId": dialog.target_id, "name": name}),
                )
            }
            SidebarDialogKind::ManageWorkspaceTags => SidebarOperation::SetTags {
                workspace_id: dialog.target_id.clone(),
                current_tag_ids: self
                    .snapshot
                    .workspace(&dialog.target_id)
                    .map(|workspace| workspace.tag_ids.iter().cloned().collect())
                    .unwrap_or_default(),
                next_tag_ids: self.sidebar_selected_tag_ids.clone(),
            },
            SidebarDialogKind::SetWorkspaceParent => SidebarOperation::SetParent {
                child_id: dialog.target_id.clone(),
                previous_parent_id: self
                    .snapshot
                    .relations
                    .iter()
                    .find(|relation| relation.child_workspace_id == dialog.target_id)
                    .map(|relation| relation.parent_workspace_id.clone()),
                next_parent_id: self.sidebar_selected_parent_id.clone(),
            },
            SidebarDialogKind::SleepWorkspace => SidebarOperation::Request(
                "workspace.sleep",
                json!({"workspaceId": dialog.target_id}),
            ),
            SidebarDialogKind::RemoveWorkspace => {
                let delete_branch = self
                    .snapshot
                    .workspace(&dialog.target_id)
                    .is_some_and(|workspace| !workspace.reuses_existing_branch);
                SidebarOperation::Request(
                    "workspace.removeManaged",
                    json!({"id": dialog.target_id, "deleteBranch": delete_branch}),
                )
            }
        };
        let bridge = self.bridge.clone();
        self.sidebar_action_busy = true;
        // Flutter closes rename, confirmation and save dialogs before the
        // mutation starts, then reports failures through the global toast.
        self.sidebar_dialog = None;
        self.error = None;
        cx.notify();
        cx.spawn(async move |this, cx| {
            let result = run_sidebar_operation(&bridge, operation).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.sidebar_action_busy = false;
                match result {
                    Ok(_) => {
                        let success_message = match dialog.kind {
                            SidebarDialogKind::RenameProject => "Project Renamed",
                            SidebarDialogKind::RemoveProject => "Project Removed",
                            SidebarDialogKind::RenameWorkspace => "Workspace Renamed",
                            SidebarDialogKind::ManageWorkspaceTags => "Workspace Tags Updated",
                            SidebarDialogKind::SetWorkspaceParent => "Workspace Parent Updated",
                            SidebarDialogKind::SleepWorkspace => "Workspace Slept",
                            SidebarDialogKind::RemoveWorkspace => "Workspace Removed",
                        };
                        if matches!(
                            dialog.kind,
                            SidebarDialogKind::SleepWorkspace | SidebarDialogKind::RemoveWorkspace
                        ) && this.selected_workspace_id.as_deref()
                            == Some(dialog.target_id.as_str())
                        {
                            this.selected_workspace_id = None;
                            this.selected_tab_id = None;
                        }
                        this.sidebar_dialog = None;
                        this.error = None;
                        this.local_message = Some(success_message.into());
                        this.refresh(cx);
                    }
                    Err(error) => {
                        let mut error = error.user_facing();
                        // Flutter rename goes through WorkspaceService and
                        // ProjectService, whose domain exceptions render
                        // without the RuntimeHostClient `Bad state:` prefix.
                        if matches!(
                            dialog.kind,
                            SidebarDialogKind::RenameProject | SidebarDialogKind::RenameWorkspace
                        ) {
                            error = error
                                .strip_prefix("Bad state: ")
                                .unwrap_or(error.as_str())
                                .to_owned();
                        }
                        let secondary = error.clone();
                        let message = if dialog.kind == SidebarDialogKind::SleepWorkspace {
                            format!("Could Not Sleep Workspace: {error}")
                        } else {
                            error
                        };
                        this.error = None;
                        this.enqueue_sidebar_error_toasts(message, Some(secondary), cx);
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn toggle_sidebar_tag(&mut self, tag_id: String, cx: &mut Context<Self>) {
        if !self.sidebar_selected_tag_ids.remove(&tag_id) {
            self.sidebar_selected_tag_ids.insert(tag_id);
        }
        cx.notify();
    }

    pub(super) fn create_sidebar_tag(&mut self, cx: &mut Context<Self>) {
        if self.sidebar_action_busy {
            return;
        }
        let name = self.sidebar_tag_input.read(cx).value().trim().to_string();
        if name.is_empty() {
            self.error = Some("Tag Name Is Required".into());
            cx.notify();
            return;
        }
        if self
            .snapshot
            .tags
            .iter()
            .any(|tag| tag.name.eq_ignore_ascii_case(&name))
        {
            self.error = Some("Tag Already Exists".into());
            cx.notify();
            return;
        }
        let bridge = self.bridge.clone();
        self.sidebar_action_busy = true;
        self.error = None;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("workspaceTag.create", json!({"name": name}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.sidebar_action_busy = false;
                match result {
                    Ok(value) => {
                        if let Some(id) = value.get("id").and_then(Value::as_str) {
                            this.sidebar_selected_tag_ids.insert(id.to_string());
                        }
                        this.refresh(cx);
                    }
                    Err(error) => {
                        let error = flutter_state_error(error);
                        this.error = Some(error.clone().into());
                        this.enqueue_sidebar_error_toasts(error, None, cx);
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn arm_sidebar_tag_delete(&mut self, tag_id: String, cx: &mut Context<Self>) {
        self.sidebar_tag_delete_armed = Some(tag_id);
        cx.notify();
    }

    pub(super) fn cancel_sidebar_tag_delete(&mut self, cx: &mut Context<Self>) {
        self.sidebar_tag_delete_armed = None;
        cx.notify();
    }

    pub(super) fn delete_sidebar_tag(&mut self, cx: &mut Context<Self>) {
        if self.sidebar_action_busy {
            return;
        }
        let Some(tag_id) = self.sidebar_tag_delete_armed.clone() else {
            return;
        };
        let bridge = self.bridge.clone();
        self.sidebar_action_busy = true;
        self.error = None;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("workspaceTag.remove", json!({"id": tag_id.clone()}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.sidebar_action_busy = false;
                match result {
                    Ok(_) => {
                        this.sidebar_selected_tag_ids.remove(&tag_id);
                        this.sidebar_tag_delete_armed = None;
                        this.refresh(cx);
                    }
                    Err(error) => {
                        let error = flutter_state_error(error);
                        this.error = Some(error.clone().into());
                        this.enqueue_sidebar_error_toasts(error, None, cx);
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn select_sidebar_parent(
        &mut self,
        parent_id: Option<String>,
        cx: &mut Context<Self>,
    ) {
        self.sidebar_selected_parent_id = parent_id;
        self.sidebar_parent_dropdown_open = false;
        cx.notify();
    }

    pub(super) fn toggle_sidebar_parent_dropdown(&mut self, cx: &mut Context<Self>) {
        self.sidebar_parent_dropdown_open = !self.sidebar_parent_dropdown_open;
        cx.notify();
    }

    pub(super) fn toggle_workspace_pinned(
        &mut self,
        workspace_id: String,
        pinned: bool,
        cx: &mut Context<Self>,
    ) {
        let bridge = self.bridge.clone();
        self.sidebar_menu = None;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "workspace.setPinned",
                    json!({"id": workspace_id, "isPinned": pinned}),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| match result {
                Ok(_) => {
                    this.local_message = Some(
                        if pinned {
                            "Workspace Pinned"
                        } else {
                            "Workspace Unpinned"
                        }
                        .into(),
                    );
                    this.refresh(cx);
                }
                Err(error) => {
                    let error = flutter_state_error(error);
                    this.enqueue_sidebar_error_toasts(error.clone(), Some(error), cx);
                }
            });
        })
        .detach();
    }

    pub(super) fn clear_workspace_parent(&mut self, workspace_id: String, cx: &mut Context<Self>) {
        let parent_id = self
            .snapshot
            .relations
            .iter()
            .find(|relation| relation.child_workspace_id == workspace_id)
            .map(|relation| relation.parent_workspace_id.clone());
        self.sidebar_menu = None;
        let Some(parent_id) = parent_id else {
            cx.notify();
            return;
        };
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "workspaceRelation.unlink",
                    json!({
                        "parentWorkspaceId": parent_id,
                        "childWorkspaceId": workspace_id,
                    }),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| match result {
                Ok(_) => {
                    this.local_message = Some("Workspace Parent Cleared".into());
                    this.refresh(cx);
                }
                Err(error) => {
                    let error = flutter_state_error(error);
                    this.enqueue_sidebar_error_toasts(error.clone(), Some(error), cx);
                }
            });
        })
        .detach();
    }

    pub(super) fn copy_workspace_path(&mut self, workspace_id: String, cx: &mut Context<Self>) {
        if let Some(workspace) = self.snapshot.workspace(&workspace_id) {
            cx.write_to_clipboard(ClipboardItem::new_string(workspace.path.clone()));
            self.local_message = Some("Workspace path copied".into());
        }
        self.sidebar_menu = None;
        cx.notify();
    }

    pub(super) fn open_workspace_folder(&mut self, workspace_id: String, cx: &mut Context<Self>) {
        if let Some(workspace) = self.snapshot.workspace(&workspace_id) {
            let url = format!("file://{}", workspace.path.replace(' ', "%20"));
            cx.open_url(&url);
        }
        self.sidebar_menu = None;
        cx.notify();
    }

    pub(super) fn open_workspace_repository(
        &mut self,
        workspace_id: String,
        cx: &mut Context<Self>,
    ) {
        let bridge = self.bridge.clone();
        self.sidebar_menu = None;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "workspace.repositoryWebUrl",
                    json!({"workspaceId": workspace_id}),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| match result {
                Ok(value) => {
                    if let Some(url) = repository_url(&value) {
                        cx.open_url(url);
                    } else {
                        this.local_message =
                            Some("No Git Remote Configured For This Workspace".into());
                    }
                    cx.notify();
                }
                Err(error) => {
                    this.local_message = Some(error.into());
                    cx.notify();
                }
            });
        })
        .detach();
    }
}

fn repository_url(value: &Value) -> Option<&str> {
    value
        .get("remoteUrl")
        .and_then(Value::as_str)
        .filter(|url| !url.trim().is_empty())
}

enum SidebarOperation {
    Request(&'static str, Value),
    SetTags {
        workspace_id: String,
        current_tag_ids: BTreeSet<String>,
        next_tag_ids: BTreeSet<String>,
    },
    SetParent {
        child_id: String,
        previous_parent_id: Option<String>,
        next_parent_id: Option<String>,
    },
}

enum SidebarOperationError {
    Runtime(String),
    Display(String),
}

impl SidebarOperationError {
    fn user_facing(self) -> String {
        match self {
            Self::Runtime(error) => flutter_state_error(error),
            Self::Display(error) => error,
        }
    }
}

async fn run_sidebar_operation(
    bridge: &crate::runtime_bridge::RuntimeBridge,
    operation: SidebarOperation,
) -> Result<(), SidebarOperationError> {
    match operation {
        SidebarOperation::Request(verb, payload) => {
            bridge
                .request(verb, payload)
                .await
                .map_err(SidebarOperationError::Runtime)?;
        }
        SidebarOperation::SetTags {
            workspace_id,
            current_tag_ids,
            next_tag_ids,
        } => {
            for tag_id in current_tag_ids.difference(&next_tag_ids) {
                bridge
                    .request(
                        "workspaceTag.unassign",
                        json!({
                            "workspaceId": workspace_id.clone(),
                            "tagId": tag_id,
                        }),
                    )
                    .await
                    .map_err(SidebarOperationError::Runtime)?;
            }
            for tag_id in next_tag_ids.difference(&current_tag_ids) {
                bridge
                    .request(
                        "workspaceTag.assign",
                        json!({
                            "workspaceId": workspace_id.clone(),
                            "tagId": tag_id,
                        }),
                    )
                    .await
                    .map_err(SidebarOperationError::Runtime)?;
            }
        }
        SidebarOperation::SetParent {
            child_id,
            previous_parent_id,
            next_parent_id,
        } => {
            if previous_parent_id == next_parent_id {
                return Ok(());
            }
            if let Some(next_parent_id) = next_parent_id.as_ref() {
                if next_parent_id == &child_id {
                    return Err(SidebarOperationError::Display(
                        "A Workspace Cannot Be Its Own Parent".to_owned(),
                    ));
                }
                let relations = bridge
                    .request("workspaceRelation.list", json!({}))
                    .await
                    .map_err(SidebarOperationError::Runtime)?;
                let descendants = workspace_descendant_ids(&relations, &child_id)
                    .map_err(SidebarOperationError::Display)?;
                if descendants.contains(next_parent_id) {
                    return Err(SidebarOperationError::Display(
                        "Cannot Set A Descendant Workspace As Parent".to_owned(),
                    ));
                }
            }
            let mut removed_previous_parent = false;
            if let Some(parent_id) = previous_parent_id.as_ref() {
                bridge
                    .request(
                        "workspaceRelation.unlink",
                        json!({
                            "parentWorkspaceId": parent_id,
                            "childWorkspaceId": child_id.clone(),
                        }),
                    )
                    .await
                    .map_err(SidebarOperationError::Runtime)?;
                removed_previous_parent = true;
            }
            if let Some(parent_id) = next_parent_id {
                if let Err(error) = bridge
                    .request(
                        "workspaceRelation.link",
                        json!({
                            "parentWorkspaceId": parent_id,
                            "childWorkspaceId": child_id.clone(),
                        }),
                    )
                    .await
                {
                    if removed_previous_parent {
                        if let Some(previous_parent_id) = previous_parent_id {
                            if let Err(restore_error) = bridge
                                .request(
                                    "workspaceRelation.link",
                                    json!({
                                        "parentWorkspaceId": previous_parent_id,
                                        "childWorkspaceId": child_id,
                                    }),
                                )
                                .await
                            {
                                return Err(SidebarOperationError::Display(format!(
                                    "Workspace Parent Update Failed: {}. Previous Parent Restore Failed: {}",
                                    flutter_state_error(error),
                                    flutter_state_error(restore_error),
                                )));
                            }
                        }
                    }
                    return Err(SidebarOperationError::Runtime(error));
                }
            }
        }
    }
    Ok(())
}

fn workspace_descendant_ids(
    relations: &Value,
    workspace_id: &str,
) -> Result<BTreeSet<String>, String> {
    let relations = relations.as_array().ok_or_else(|| {
        "FormatException: Workspace graph payload must be a JSON array.".to_owned()
    })?;
    let mut children = std::collections::BTreeMap::<String, Vec<String>>::new();
    for relation in relations {
        let Some(parent_id) = relation.get("parentWorkspaceId").and_then(Value::as_str) else {
            continue;
        };
        let Some(child_id) = relation.get("childWorkspaceId").and_then(Value::as_str) else {
            continue;
        };
        children
            .entry(parent_id.to_owned())
            .or_default()
            .push(child_id.to_owned());
    }
    let mut descendants = BTreeSet::new();
    let mut pending = children.get(workspace_id).cloned().unwrap_or_default();
    while let Some(child_id) = pending.pop() {
        if descendants.insert(child_id.clone()) {
            pending.extend(children.get(&child_id).into_iter().flatten().cloned());
        }
    }
    Ok(descendants)
}
