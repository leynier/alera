use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SharedWorkbenchGroupBy {
    None,
    #[default]
    Project,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SharedWorkbenchSortBy {
    #[default]
    Name,
    Recent,
    Activity,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SharedWorkspaceKindFilter {
    #[default]
    All,
    DefaultOnly,
    NonDefaultOnly,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SharedWorkbenchViewPrefs {
    pub group_by: SharedWorkbenchGroupBy,
    pub project_sort: SharedWorkbenchSortBy,
    pub workspace_sort: SharedWorkbenchSortBy,
    #[serde(default)]
    pub selected_project_ids: Vec<String>,
    #[serde(default)]
    pub selected_tag_ids: Vec<String>,
    #[serde(default)]
    pub collapsed_project_ids: Vec<String>,
    #[serde(default)]
    pub collapsed_parent_workspace_ids: Vec<String>,
    #[serde(default)]
    pub pinned_section_collapsed: bool,
    #[serde(default)]
    pub all_section_collapsed: bool,
    #[serde(default = "default_true")]
    pub show_pinned_workspaces_below: bool,
    pub workspace_kind_filter: SharedWorkspaceKindFilter,
    #[serde(default)]
    pub show_active_workspaces_only: bool,
    #[serde(default)]
    pub source_control_root_by_workspace_id: BTreeMap<String, String>,
}

fn default_true() -> bool {
    true
}

impl Default for SharedWorkbenchViewPrefs {
    fn default() -> Self {
        Self {
            group_by: SharedWorkbenchGroupBy::Project,
            project_sort: SharedWorkbenchSortBy::Name,
            workspace_sort: SharedWorkbenchSortBy::Name,
            selected_project_ids: Vec::new(),
            selected_tag_ids: Vec::new(),
            collapsed_project_ids: Vec::new(),
            collapsed_parent_workspace_ids: Vec::new(),
            pinned_section_collapsed: false,
            all_section_collapsed: false,
            show_pinned_workspaces_below: true,
            workspace_kind_filter: SharedWorkspaceKindFilter::All,
            show_active_workspaces_only: false,
            source_control_root_by_workspace_id: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SharedWorkbenchPrefsWriter {
    #[default]
    Runtime,
    Desktop,
    Mobile,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct SharedWorkbenchViewPrefsRecord {
    pub revision: i64,
    pub desktop_initialized: bool,
    pub last_writer: SharedWorkbenchPrefsWriter,
    pub prefs: SharedWorkbenchViewPrefs,
}
