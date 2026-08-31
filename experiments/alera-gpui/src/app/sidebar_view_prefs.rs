use gpui::Context;
use serde_json::{json, Value};

use super::{AleraApp, SidebarGroupBy, SidebarSortBy, SidebarWorkspaceKind};

impl AleraApp {
    pub(super) fn load_sidebar_view_prefs(&mut self, cx: &mut Context<Self>) {
        let generation=self.next_view_prefs_generation();
        let bridge = self.bridge.clone();
        let store=self.workbench_prefs_store.clone();
        cx.spawn(async move |this, cx| {
            let (result, local_prefs) = tokio::join!(
                bridge.request("workbenchViewPrefs.get", json!({})),
                store.load(),
            );
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if this.workbench_prefs_generation.get()!=generation {return;}
                let (prefs,initialize_shared)=match result {
                    Ok(record)=>resolve_loaded_view_prefs(local_prefs,&record),
                    Err(error)=>{
                        crate::app_log::warning("workbench_view_prefs",&format!("Could not load shared view preferences; using local preferences: {error}"));
                        let Some(local)=local_prefs.filter(Value::is_object) else {return;};
                        (local,false)
                    }
                };
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
                    this.sidebar_active_only = prefs
                        .get("showActiveWorkspacesOnly")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
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
                    this.source_control_tree_mode = source_control_tree_mode(prefs);
                    this.source_control_group_mode =
                        string_field(prefs, "gitDiffGroupMode") == "unified";
                    this.forge_create_draft =
                        string_field(prefs, "pullRequestCreateAction") == "draft";
                    this.refresh_local_activity(cx);
                    if initialize_shared {this.persist_sidebar_view_prefs(cx);}
                    cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn persist_sidebar_view_prefs(&self, cx: &mut Context<Self>) {
        self.next_view_prefs_generation();
        let bridge = self.bridge.clone();
        let store=self.workbench_prefs_store.clone();
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
            "showActiveWorkspacesOnly".into(),
            json!(self.sidebar_active_only),
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
            "gitDiffViewMode".into(),
            json!(source_control_view_mode_key(self.source_control_tree_mode)),
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
            // The remote change event must not race a stale local record.
            let _=store.save(&prefs).await;
            let _=bridge.request("workbenchViewPrefs.update",json!({"expectedRevision":null,"prefs":prefs})).await;
        })
        .detach();
    }

    fn next_view_prefs_generation(&self)->u64 {
        let generation=self.workbench_prefs_generation.get().wrapping_add(1);
        self.workbench_prefs_generation.set(generation);
        generation
    }
}

fn resolve_loaded_view_prefs(local:Option<Value>,record:&Value)->(Value,bool) {
    // A new runtime must be seeded from desktop-local preferences, not from
    // its default (or mobile-only) record. Legacy unwrapped replies still merge.
    if record.get("desktopInitialized").and_then(Value::as_bool)==Some(false) {
        return (local.filter(Value::is_object).unwrap_or_else(||json!({})),true);
    }
    (merge_local_and_shared_prefs(local,record.get("prefs").unwrap_or(record)),false)
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

fn source_control_tree_mode(prefs: &Value) -> bool {
    !matches!(string_field(prefs,"gitDiffViewMode"),"flat"|"list")
}

fn source_control_view_mode_key(tree:bool)->&'static str {if tree{"tree"}else{"flat"}}

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

#[cfg(test)]
mod tests {
    use super::{source_control_tree_mode,source_control_view_mode_key};
    use serde_json::json;

    #[test]
    fn source_control_defaults_to_tree_and_restores_list() {
        assert!(source_control_tree_mode(&json!({})));
        assert!(source_control_tree_mode(
            &json!({"gitDiffViewMode": "tree"})
        ));
        assert!(!source_control_tree_mode(
            &json!({"gitDiffViewMode": "list"})
        ));
    }

    #[test]
    fn source_control_flat_mode_uses_flutter_wire_value() {
        assert!(!source_control_tree_mode(&json!({"gitDiffViewMode":"flat"})));
        assert_eq!(source_control_view_mode_key(false),"flat");
        let fixture:serde_json::Value=serde_json::from_str(include_str!("../../tests/fixtures/workbench_view_prefs.json")).unwrap();
        assert_eq!(fixture["gitDiffViewMode"],source_control_view_mode_key(false));
    }
}
