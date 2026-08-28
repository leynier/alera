use std::collections::BTreeMap;

use gpui::{Pixels, Point, ScrollAnchor};

use crate::activity::SettingsPane;
use crate::model::WorkbenchDropZone;

pub(super) type SettingsGroupAnchors = BTreeMap<(SettingsPane, usize), ScrollAnchor>;

#[derive(Clone, Debug)]
pub(super) struct SplitResizeState {
    pub(super) path: Vec<usize>,
    pub(super) axis: crate::model::WorkbenchSplitAxis,
    pub(super) start: Point<Pixels>,
    pub(super) initial_ratio: f64,
    /// Extent of this split's content, excluding the 4 px resize handle.
    /// Flutter normalizes the drag delta against the local split, not the
    /// whole window; keeping the measured value stable avoids nested/sidebar
    /// geometry changing the ratio during a gesture.
    pub(super) content_extent: f32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum PanelResizeTarget {
    ProjectSidebar,
    ContextSidebar,
}

#[derive(Clone, Debug)]
pub(super) struct PanelResizeState {
    pub(super) target: PanelResizeTarget,
    pub(super) start_x: Pixels,
    pub(super) initial_width: f32,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct ResizeDrag;

#[derive(Clone, Copy, Debug)]
pub(super) struct GitHistoryResizeState {
    pub(super) start_y: Pixels,
    pub(super) initial_height: f32,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct GitHistoryResizeDrag;

#[derive(Clone, Debug)]
pub(super) struct PreviewDragState {
    pub(super) tab_id: String,
    pub(super) start: Point<Pixels>,
    pub(super) initial_offset: Point<Pixels>,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct PreviewTransform {
    pub(super) scale: f32,
    pub(super) offset: Point<Pixels>,
}

impl Default for PreviewTransform {
    fn default() -> Self {
        Self {
            scale: 1.0,
            offset: gpui::point(gpui::px(0.0), gpui::px(0.0)),
        }
    }
}

#[derive(Clone, Debug)]
pub(super) enum WorkbenchMenu {
    NewTab {
        group_id: String,
        position: Point<Pixels>,
    },
    Pane {
        group_id: String,
        position: Point<Pixels>,
    },
    Tab {
        group_id: String,
        tab_id: String,
        position: Point<Pixels>,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct TabDropTarget {
    pub(super) group_id: String,
    pub(super) gap_index: usize,
    pub(super) insert_index: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct PaneDropTarget {
    pub(super) group_id: String,
    pub(super) zone: WorkbenchDropZone,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum AddProjectMode {
    #[default]
    LocalFolder,
    CloneFromUrl,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum SidebarGroupBy {
    None,
    #[default]
    Project,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum SidebarSortBy {
    #[default]
    Name,
    Recent,
    Activity,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum SidebarWorkspaceKind {
    #[default]
    All,
    DefaultOnly,
    NonDefaultOnly,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum SidebarSortTarget {
    Project,
    Workspace,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum NewWorkspaceMode {
    #[default]
    FromPrompt,
    Manual,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum NewWorkspaceStep {
    #[default]
    Entry,
    ManualSelection,
    ManualSettings,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum SidebarMenu {
    Project(String),
    Workspace(String),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum SidebarDialogKind {
    RenameProject,
    RemoveProject,
    RenameWorkspace,
    ManageWorkspaceTags,
    SetWorkspaceParent,
    SleepWorkspace,
    RemoveWorkspace,
}

#[derive(Clone, Debug)]
pub(super) struct SidebarDialog {
    pub(super) kind: SidebarDialogKind,
    pub(super) target_id: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum ExplorerMenuTarget {
    Background,
    Entry(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct ExplorerClipboard {
    pub(super) relative_path: String,
    pub(super) cut: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct ExplorerDragData {
    pub(super) relative_path: String,
    pub(super) name: String,
    pub(super) is_directory: bool,
    pub(super) is_symlink: bool,
    pub(super) depth: usize,
    pub(super) expanded: bool,
    pub(super) git_status: Option<String>,
    pub(super) source_control_root: bool,
}

#[derive(Clone, Debug)]
pub(super) struct ResourceCloseConfirmation {
    pub(super) tab_id: String,
    pub(super) label: String,
}
