use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SharedWorkbenchGroupBy {
    None,
    #[default]
    Project,
    Section,
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

/// Whether Source Control lists changed files as a folder tree or a flat list.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SharedGitDiffViewMode {
    #[default]
    Tree,
    Flat,
}

/// Whether Source Control groups files by staged state or shows one list.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum SharedGitDiffGroupMode {
    #[default]
    ByArea,
    Unified,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SharedWorkbenchViewPrefs {
    pub group_by: SharedWorkbenchGroupBy,
    #[serde(default)]
    pub section_sort: SharedWorkbenchSortBy,
    #[serde(default)]
    pub collapsed_section_ids: Vec<String>,
    #[serde(default)]
    pub others_section_collapsed: bool,
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
    pub git_diff_view_mode: SharedGitDiffViewMode,
    #[serde(default)]
    pub git_diff_group_mode: SharedGitDiffGroupMode,
    #[serde(default)]
    pub search_view_as_tree: bool,
    #[serde(default)]
    pub search_include_ignored: bool,
}

fn default_true() -> bool {
    true
}

impl Default for SharedWorkbenchViewPrefs {
    fn default() -> Self {
        Self {
            group_by: SharedWorkbenchGroupBy::Project,
            section_sort: SharedWorkbenchSortBy::Name,
            collapsed_section_ids: Vec::new(),
            others_section_collapsed: false,
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
            git_diff_view_mode: SharedGitDiffViewMode::Tree,
            git_diff_group_mode: SharedGitDiffGroupMode::ByArea,
            search_view_as_tree: false,
            search_include_ignored: false,
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
