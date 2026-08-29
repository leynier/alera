use gpui::{Context, SharedString};
use serde_json::{json, Value};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::Row as _;

use super::{AleraApp, SidebarGroupBy, SidebarSortBy, SidebarWorkspaceKind};

impl AleraApp {
    pub(super) fn load_sidebar_view_prefs(&mut self, cx: &mut Context<Self>) {
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let (result, local_prefs) = tokio::join!(
                bridge.request("workbenchViewPrefs.get", json!({})),
                load_local_workbench_prefs(),
            );
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| match result {
                Ok(record) => {
                    let shared = record.get("prefs").unwrap_or(&record);
                    let prefs = merge_local_and_shared_prefs(local_prefs, shared);
                    this.workbench_view_prefs_raw = prefs.clone();
                    let prefs = &prefs;
                    this.sidebar_group_by = match string_field(prefs, "groupBy") {
                        "none" => SidebarGroupBy::None,
                        _ => SidebarGroupBy::Project,
                    };
                    this.sidebar_project_sort = parse_sort(string_field(prefs, "projectSort"));
                    this.sidebar_workspace_sort = parse_sort(string_field(prefs, "workspaceSort"));
                    this.sidebar_workspace_kind = match string_field(prefs, "workspaceKindFilter") {
                        "defaultOnly" => SidebarWorkspaceKind::DefaultOnly,
                        "nonDefaultOnly" => SidebarWorkspaceKind::NonDefaultOnly,
                        _ => SidebarWorkspaceKind::All,
                    };
                    this.sidebar_selected_project_ids = string_set(prefs.get("selectedProjectIds"));
                    this.sidebar_view_selected_tag_ids = string_set(prefs.get("selectedTagIds"));
                    this.collapsed_project_ids = string_set(prefs.get("collapsedProjectIds"));
                    this.sidebar_collapsed_parent_workspace_ids =
                        string_set(prefs.get("collapsedParentWorkspaceIds"));
                    this.sidebar_expanded_workspace_ids =
                        string_set(prefs.get("expandedWorkspaceIds"));
                    this.sidebar_pinned_collapsed = prefs
                        .get("pinnedSectionCollapsed")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    this.sidebar_all_collapsed = prefs
                        .get("allSectionCollapsed")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    this.sidebar_repeat_pinned = prefs
                        .get("showPinnedWorkspacesBelow")
                        .and_then(Value::as_bool)
                        .unwrap_or(true);
                    this.sidebar_width = number_field(prefs, "sidebarWidth", 300.0);
                    this.context_sidebar_width = number_field(prefs, "rightSidebarWidth", 280.0);
                    this.context_sidebar_collapsed = !prefs
                        .get("rightSidebarVisible")
                        .and_then(Value::as_bool)
                        .unwrap_or(true);
                    this.context_panel = match string_field(prefs, "activeContextPanelTab") {
                        "search" => crate::activity::ContextPanel::Search,
                        "gitDiff" => crate::activity::ContextPanel::SourceControl,
                        "pullRequests" => crate::activity::ContextPanel::PullRequest,
                        "agentCanvas" => crate::activity::ContextPanel::AgentCanvas,
                        _ => crate::activity::ContextPanel::Explorer,
                    };
                    this.explorer_hide_ignored = string_field(prefs, "explorerMode") != "showAll";
                    this.source_control_group_mode =
                        string_field(prefs, "gitDiffGroupMode") == "unified";
                    this.forge_create_draft =
                        string_field(prefs, "pullRequestCreateAction") == "draft";
                    this.refresh_local_activity(cx);
                }
                Err(error) => {
                    this.error = Some(SharedString::from(format!(
                        "Could Not Load View Options: {error}"
                    )));
                    cx.notify();
                }
            });
        })
        .detach();
    }

    pub(super) fn persist_sidebar_view_prefs(&self, cx: &mut Context<Self>) {
        let bridge = self.bridge.clone();
        let mut prefs = self.workbench_view_prefs_raw.clone();
        if !prefs.is_object() {
            prefs = json!({});
        }
        let object = prefs.as_object_mut().expect("prefs object");
        object.insert(
            "groupBy".into(),
            json!(match self.sidebar_group_by {
                SidebarGroupBy::None => "none",
                SidebarGroupBy::Project => "project",
            }),
        );
        object.insert(
            "projectSort".into(),
            json!(sort_key(self.sidebar_project_sort)),
        );
        object.insert(
            "workspaceSort".into(),
            json!(sort_key(self.sidebar_workspace_sort)),
        );
        object.insert(
            "selectedProjectIds".into(),
            json!(self
                .sidebar_selected_project_ids
                .iter()
                .cloned()
                .collect::<Vec<_>>()),
        );
        object.insert(
            "selectedTagIds".into(),
            json!(self
                .sidebar_view_selected_tag_ids
                .iter()
                .cloned()
                .collect::<Vec<_>>()),
        );
        object.insert(
            "collapsedProjectIds".into(),
            json!(self
                .collapsed_project_ids
                .iter()
                .cloned()
                .collect::<Vec<_>>()),
        );
        object.insert(
            "collapsedParentWorkspaceIds".into(),
            json!(self
                .sidebar_collapsed_parent_workspace_ids
                .iter()
                .cloned()
                .collect::<Vec<_>>()),
        );
        object.insert(
            "expandedWorkspaceIds".into(),
            json!(self
                .sidebar_expanded_workspace_ids
                .iter()
                .cloned()
                .collect::<Vec<_>>()),
        );
        object.insert(
            "pinnedSectionCollapsed".into(),
            json!(self.sidebar_pinned_collapsed),
        );
        object.insert(
            "allSectionCollapsed".into(),
            json!(self.sidebar_all_collapsed),
        );
        object.insert(
            "showPinnedWorkspacesBelow".into(),
            json!(self.sidebar_repeat_pinned),
        );
        object.insert(
            "workspaceKindFilter".into(),
            json!(match self.sidebar_workspace_kind {
                SidebarWorkspaceKind::All => "all",
                SidebarWorkspaceKind::DefaultOnly => "defaultOnly",
                SidebarWorkspaceKind::NonDefaultOnly => "nonDefaultOnly",
            }),
        );
        object.insert("sidebarWidth".into(), json!(self.sidebar_width));
        object.insert(
            "rightSidebarVisible".into(),
            json!(!self.context_sidebar_collapsed),
        );
        object.insert(
            "rightSidebarWidth".into(),
            json!(self.context_sidebar_width),
        );
        object.insert(
            "activeContextPanelTab".into(),
            json!(match self.context_panel {
                crate::activity::ContextPanel::Explorer => "explorer",
                crate::activity::ContextPanel::Search => "search",
                crate::activity::ContextPanel::SourceControl => "gitDiff",
                crate::activity::ContextPanel::PullRequest => "pullRequests",
                crate::activity::ContextPanel::AgentCanvas => "agentCanvas",
            }),
        );
        object.insert(
            "explorerMode".into(),
            json!(if self.explorer_hide_ignored {
                "hideIgnored"
            } else {
                "showAll"
            }),
        );
        object.insert(
            "gitDiffGroupMode".into(),
            json!(if self.source_control_group_mode {
                "unified"
            } else {
                "byArea"
            }),
        );
        object.insert(
            "pullRequestCreateAction".into(),
            json!(if self.forge_create_draft {
                "draft"
            } else {
                "publish"
            }),
        );
        cx.spawn(async move |_, _| {
            let shared_prefs = prefs.clone();
            let _ = tokio::join!(
                save_local_workbench_prefs(&prefs),
                bridge.request(
                    "workbenchViewPrefs.update",
                    json!({"expectedRevision": null, "prefs": shared_prefs}),
                ),
            );
        })
        .detach();
    }
}

fn merge_local_and_shared_prefs(local: Option<Value>, shared: &Value) -> Value {
    let mut merged = local.filter(Value::is_object).unwrap_or_else(|| json!({}));
    let Some(merged) = merged.as_object_mut() else {
        return shared.clone();
    };
    if let Some(shared) = shared.as_object() {
        for (key, value) in shared {
            merged.insert(key.clone(), value.clone());
        }
    }
    Value::Object(merged.clone())
}

async fn load_local_workbench_prefs() -> Option<Value> {
    let path = crate::local_database_path()?;
    let (sender, receiver) = async_channel::bounded(1);
    std::thread::spawn(move || {
        let value = local_database_runtime()
            .and_then(|runtime| runtime.block_on(load_local_workbench_prefs_from(path)));
        let _ = sender.send_blocking(value);
    });
    receiver.recv().await.ok().flatten()
}

async fn load_local_workbench_prefs_from(path: std::path::PathBuf) -> Option<Value> {
    let pool = open_local_database(path).await?;
    let row = sqlx::query("SELECT data_json FROM workbench_view_prefs_table WHERE id = 1")
        .fetch_optional(&pool)
        .await
        .ok()??;
    serde_json::from_str(row.get::<&str, _>("data_json")).ok()
}

async fn save_local_workbench_prefs(prefs: &Value) -> Option<()> {
    let path = crate::local_database_path()?;
    let encoded = serde_json::to_string(prefs).ok()?;
    let (sender, receiver) = async_channel::bounded(1);
    std::thread::spawn(move || {
        let value = local_database_runtime()
            .and_then(|runtime| runtime.block_on(save_local_workbench_prefs_to(path, encoded)));
        let _ = sender.send_blocking(value);
    });
    receiver.recv().await.ok().flatten()
}

async fn save_local_workbench_prefs_to(path: std::path::PathBuf, encoded: String) -> Option<()> {
    let pool = open_local_database(path).await?;
    sqlx::query(
        "INSERT INTO workbench_view_prefs_table (id, data_json) VALUES (1, ?) \
         ON CONFLICT(id) DO UPDATE SET data_json = excluded.data_json",
    )
    .bind(encoded)
    .execute(&pool)
    .await
    .ok()?;
    Some(())
}

async fn open_local_database(path: std::path::PathBuf) -> Option<sqlx::SqlitePool> {
    if !path.is_file() {
        return None;
    }
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(false);
    SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .ok()
}

fn local_database_runtime() -> Option<tokio::runtime::Runtime> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .ok()
}

fn parse_sort(value: &str) -> SidebarSortBy {
    match value {
        "recent" => SidebarSortBy::Recent,
        "activity" => SidebarSortBy::Activity,
        _ => SidebarSortBy::Name,
    }
}

fn sort_key(value: SidebarSortBy) -> &'static str {
    match value {
        SidebarSortBy::Name => "name",
        SidebarSortBy::Recent => "recent",
        SidebarSortBy::Activity => "activity",
    }
}

fn string_field<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or("")
}

fn string_set(value: Option<&Value>) -> std::collections::BTreeSet<String> {
    value
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect()
}

fn number_field(value: &Value, key: &str, fallback: f32) -> f32 {
    value
        .get(key)
        .and_then(Value::as_f64)
        .map(|value| value as f32)
        .unwrap_or(fallback)
        .clamp(220.0, 460.0)
}
