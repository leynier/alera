#[cfg(test)]
use std::collections::HashSet;
use std::collections::{BTreeMap, HashMap};
use std::hash::Hash;
use std::sync::{Arc, Mutex};

use crate::alera_scroll_view::AleraScrollView as ScrollView;
use crate::preview_surface::{
    ImagePreviewSurface, MarkdownPreviewSurface, MermanPreviewSurface, is_image_path,
    is_markdown_path, is_merman_path,
};
use crate::{
    ACCENT, BACKGROUND, BORDER, EditorReloadRequest, EditorRevealTarget, ExplorerPathMove, FAINT,
    FileOpenRequest, MUTED, SURFACE, SURFACE_RAISED, TEXT,
    settings_terminal_state::StoredTerminalSettings,
};
use alera_desktop_core::terminal_model::{Rgba, TerminalCellStyle};
use alera_desktop_core::terminal_theme_catalog::TerminalThemePalette;
use alera_desktop_core::{
    KeyModifiers, RuntimeBridge, TerminalCell, TerminalEmulator, TerminalSelection,
    TerminalSelectionMode, TerminalSession, WorkbenchDropZone, WorkbenchLayout,
    WorkbenchLayoutNode, WorkbenchPaneGroup, WorkbenchSnapshot, WorkbenchSplitAxis,
    WorkbenchSplitDirection, replace_workspace_path_prefix,
};
use async_io::Timer;
use base64::prelude::{BASE64_STANDARD, Engine as _};
use chrono::Utc;
use freya::clipboard::Clipboard;
use freya::text_edit::{TextEditor, TextSelection};
use freya::{code_editor::*, icons, prelude::*, radio::*};
use serde_json::{Value, json};
use uuid::Uuid;

type TabId = usize;
type PanelId = usize;
const ALERA_MIDDLE_FLEX: f32 = 2.0;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitDiffOpenRequest {
    pub workspace_path: String,
    pub git_path: String,
    pub git_diff_root: Option<String>,
    pub relative_path: Option<String>,
    pub old_path: Option<String>,
    pub source_relative_path: Option<String>,
    pub source_old_path: Option<String>,
    pub area: Option<String>,
    pub commit_id: Option<String>,
    pub commit_subject: Option<String>,
}

impl GitDiffOpenRequest {
    pub fn working_tree(
        workspace_path: impl Into<String>,
        relative_path: Option<String>,
        area: Option<String>,
    ) -> Self {
        Self {
            workspace_path: workspace_path.into(),
            git_path: String::new(),
            git_diff_root: None,
            source_relative_path: relative_path.clone(),
            source_old_path: None,
            relative_path,
            old_path: None,
            area,
            commit_id: None,
            commit_subject: None,
        }
        .with_resolved_git_path()
    }

    pub fn working_tree_in_scope(
        workspace_path: impl Into<String>,
        git_path: impl Into<String>,
        git_diff_root: impl Into<String>,
        source_relative_path: Option<String>,
        area: Option<String>,
    ) -> Self {
        let workspace_path = workspace_path.into();
        let git_diff_root = git_diff_root.into();
        Self {
            workspace_path,
            git_path: git_path.into(),
            relative_path: source_relative_path
                .as_deref()
                .map(|path| workspace_relative_from_source(&git_diff_root, path)),
            old_path: None,
            source_relative_path,
            source_old_path: None,
            area,
            commit_id: None,
            commit_subject: None,
            git_diff_root: Some(git_diff_root),
        }
    }

    pub fn commit(
        workspace_path: impl Into<String>,
        relative_path: Option<String>,
        old_path: Option<String>,
        commit_id: impl Into<String>,
        commit_subject: impl Into<String>,
    ) -> Self {
        Self {
            workspace_path: workspace_path.into(),
            git_path: String::new(),
            git_diff_root: None,
            source_relative_path: relative_path.clone(),
            source_old_path: old_path.clone(),
            relative_path,
            old_path,
            area: None,
            commit_id: Some(commit_id.into()),
            commit_subject: Some(commit_subject.into()),
        }
        .with_resolved_git_path()
    }

    pub fn commit_in_scope(
        workspace_path: impl Into<String>,
        git_path: impl Into<String>,
        git_diff_root: impl Into<String>,
        source_relative_path: Option<String>,
        source_old_path: Option<String>,
        commit_id: impl Into<String>,
        commit_subject: impl Into<String>,
    ) -> Self {
        let workspace_path = workspace_path.into();
        let git_diff_root = git_diff_root.into();
        Self {
            workspace_path,
            git_path: git_path.into(),
            relative_path: source_relative_path
                .as_deref()
                .map(|path| workspace_relative_from_source(&git_diff_root, path)),
            old_path: source_old_path
                .as_deref()
                .map(|path| workspace_relative_from_source(&git_diff_root, path)),
            source_relative_path,
            source_old_path,
            area: None,
            commit_id: Some(commit_id.into()),
            commit_subject: Some(commit_subject.into()),
            git_diff_root: Some(git_diff_root),
        }
    }

    fn title(&self) -> String {
        if let Some(path) = self.relative_path.as_deref() {
            let name = path.rsplit('/').next().unwrap_or(path);
            if let Some(commit_id) = self.commit_id.as_deref() {
                return format!("{} {}", name, short_commit_id(commit_id));
            }
            if let Some(area) = self.area.as_deref() {
                return format!("{} {}", name, title_case_git_area(area));
            }
        }
        self.commit_id.as_deref().map_or_else(
            || "All Changes".to_string(),
            |commit_id| format!("Commit {}", short_commit_id(commit_id)),
        )
    }

    fn payload(&self) -> Value {
        json!({
            "gitDiffScope": if self.relative_path.is_some() { "file" } else { "all" },
            "gitDiffSource": self.commit_id.as_ref().map(|_| "commit"),
            "gitDiffCommitOid": self.commit_id,
            "gitDiffCompareRef": self.commit_id.as_deref().map(short_commit_id),
            "gitDiffCommitSubject": self.commit_subject,
            "filePath": self.relative_path,
            "gitDiffOldPath": self.old_path,
            "gitDiffArea": self.area,
            "gitDiffRoot": self.git_diff_root,
        })
    }

    fn from_payload(workspace_path: String, payload: &Value) -> Self {
        let string = |key: &str| payload.get(key).and_then(Value::as_str).map(str::to_string);
        let git_diff_root = string("gitDiffRoot");
        let relative_path = string("filePath");
        let old_path = string("gitDiffOldPath");
        Self {
            git_path: git_path_for_root(&workspace_path, git_diff_root.as_deref()),
            source_relative_path: relative_path
                .as_deref()
                .and_then(|path| source_relative_from_workspace(git_diff_root.as_deref(), path)),
            source_old_path: old_path
                .as_deref()
                .and_then(|path| source_relative_from_workspace(git_diff_root.as_deref(), path)),
            workspace_path,
            git_diff_root,
            relative_path,
            old_path,
            area: string("gitDiffArea"),
            commit_id: string("gitDiffCommitOid"),
            commit_subject: string("gitDiffCommitSubject"),
        }
    }

    fn matches_payload(&self, payload: &Value) -> bool {
        let other = Self::from_payload(self.workspace_path.clone(), payload);
        self == &other
    }

    fn with_resolved_git_path(mut self) -> Self {
        self.git_path = git_path_for_root(&self.workspace_path, self.git_diff_root.as_deref());
        self
    }
}

fn git_path_for_root(workspace_path: &str, root: Option<&str>) -> String {
    root.map_or_else(
        || workspace_path.to_string(),
        |root| {
            std::path::PathBuf::from(workspace_path)
                .join(root)
                .to_string_lossy()
                .into_owned()
        },
    )
}

fn workspace_relative_from_source(root: &str, source_path: &str) -> String {
    if source_path.is_empty() {
        root.to_string()
    } else {
        format!("{root}/{source_path}")
    }
}

fn source_relative_from_workspace(root: Option<&str>, workspace_path: &str) -> Option<String> {
    let Some(root) = root else {
        return Some(workspace_path.to_string());
    };
    if workspace_path == root {
        return Some(String::new());
    }
    workspace_path
        .strip_prefix(&format!("{root}/"))
        .map(str::to_string)
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct GitDiffResult {
    files: Vec<GitDiffFile>,
    truncated: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct GitDiffFile {
    path: String,
    old_path: Option<String>,
    area: String,
    status: String,
    lines: Vec<GitDiffLine>,
    added: Option<u64>,
    removed: Option<u64>,
    is_binary: bool,
    is_large: bool,
    is_gitlink: bool,
    truncated: bool,
    line_preview_truncated: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct GitDiffLine {
    text: String,
    kind: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum GitDiffLoadState {
    Loading,
    Loaded(Result<GitDiffResult, String>),
}

#[derive(Clone, PartialEq)]
struct AleraDockDrag<Value> {
    value: Value,
}

impl<Value> AleraDockDrag<Value> {
    fn new(value: Value) -> Self {
        Self { value }
    }
}

/// A local docking adapter keeps the public Freya drag/drop primitives while
/// leaving the edge targets mounted for the whole lifetime of a panel.  The
/// stock component mounts those targets only after the first drag frame; a
/// native pointer stream can deliver down/move/up in one frame and therefore
/// miss the newly-created target.  Toggling interactivity instead makes the
/// first subsequent move reliable without intercepting normal clicks.
#[derive(Clone, Copy, PartialEq)]
enum AleraHoverTarget<TabId> {
    Tab(TabId),
    Edge(Side),
    Center,
}

fn toggle_alera_hover<TabId: Copy + PartialEq + 'static>(
    mut hover: State<Option<AleraHoverTarget<TabId>>>,
    target: AleraHoverTarget<TabId>,
    hovering: bool,
) {
    if hovering {
        hover.set(Some(target));
    } else if hover() == Some(target) {
        hover.set(None);
    }
}

#[derive(Clone, PartialEq)]
struct AleraRenderers<TabId: 'static, PanelId: 'static> {
    content: Callback<ContentContext<TabId, PanelId>, Element>,
    tab: Callback<TabContext<TabId>, Element>,
    drag: Callback<TabId, Element>,
    bar: Callback<TabBarContext<PanelId>, Element>,
    ratio: Callback<(PanelId, PanelId), f32>,
}

struct AleraDockingArea<M: DockingModel> {
    controller: Writable<M>,
    renderers: AleraRenderers<M::TabId, M::PanelId>,
    persist: Callback<(), ()>,
    preview_element: Option<Element>,
    key: DiffKey,
}

impl<M: DockingModel> Clone for AleraDockingArea<M> {
    fn clone(&self) -> Self {
        Self {
            controller: self.controller.clone(),
            renderers: self.renderers.clone(),
            persist: self.persist.clone(),
            preview_element: self.preview_element.clone(),
            key: self.key.clone(),
        }
    }
}

impl<M: DockingModel> PartialEq for AleraDockingArea<M> {
    fn eq(&self, other: &Self) -> bool {
        self.controller == other.controller
            && self.renderers == other.renderers
            && self.persist == other.persist
            && self.preview_element == other.preview_element
            && self.key == other.key
    }
}

impl<M: DockingModel> KeyExt for AleraDockingArea<M> {
    fn write_key(&mut self) -> &mut DiffKey {
        &mut self.key
    }
}

impl<M: DockingModel> AleraDockingArea<M> {
    fn new(
        controller: impl Into<Writable<M>>,
        render_content: impl Into<Callback<ContentContext<M::TabId, M::PanelId>, Element>>,
        render_tab: impl Into<Callback<TabContext<M::TabId>, Element>>,
        render_drag: impl Into<Callback<M::TabId, Element>>,
        render_tab_bar: impl Into<Callback<TabBarContext<M::PanelId>, Element>>,
        ratio: impl Into<Callback<(M::PanelId, M::PanelId), f32>>,
        persist: impl Into<Callback<(), ()>>,
    ) -> Self {
        Self {
            controller: controller.into(),
            renderers: AleraRenderers {
                content: render_content.into(),
                tab: render_tab.into(),
                drag: render_drag.into(),
                bar: render_tab_bar.into(),
                ratio: ratio.into(),
            },
            persist: persist.into(),
            preview_element: None,
            key: DiffKey::default(),
        }
    }

    fn preview_element(mut self, element: impl IntoElement) -> Self {
        self.preview_element = Some(element.into_element());
        self
    }
}

impl<M> Component for AleraDockingArea<M>
where
    M: DockingModel,
    M::PanelId: Hash,
{
    fn render(&self) -> impl IntoElement {
        let controller = self.controller.clone();
        let renderers = self.renderers.clone();
        let persist = self.persist.clone();
        let preview_element = self.preview_element.clone();
        let node = controller.read().root().cloned();

        rect().expanded().map(node, move |element, root| {
            element.child(render_alera_node(
                root,
                controller,
                renderers,
                persist,
                preview_element,
            ))
        })
    }

    fn render_key(&self) -> DiffKey {
        self.key.clone().or(self.default_key())
    }
}

fn render_alera_node<M>(
    node: DockNode<M::TabId, M::PanelId>,
    controller: Writable<M>,
    renderers: AleraRenderers<M::TabId, M::PanelId>,
    persist: Callback<(), ()>,
    preview_element: Option<Element>,
) -> Element
where
    M: DockingModel,
    M::PanelId: Hash,
{
    match node {
        DockNode::Split {
            direction,
            children,
        } => {
            let share = children
                .first()
                .zip(children.get(1))
                .and_then(|(first, second)| {
                    first_panel_id(first)
                        .zip(first_panel_id(second))
                        .map(|panel_ids| renderers.ratio.call(panel_ids))
                })
                .unwrap_or(50.)
                .clamp(15., 85.);
            rect()
                .key("split")
                .expanded()
                .child(ResizableContainer::new().direction(direction).panels_iter(
                    children.into_iter().enumerate().map(|(index, child)| {
                        let size = if index == 0 { share } else { 100. - share };
                        ResizablePanel::new(PanelSize::percent(size))
                            .min_size(5.)
                            .child(render_alera_node(
                                child,
                                controller.clone(),
                                renderers.clone(),
                                persist.clone(),
                                preview_element.clone(),
                            ))
                    }),
                ))
                .into_element()
        }
        DockNode::Panel(panel) => rect()
            // A panel owns hook-bearing children (terminal surface, drag state
            // and hover state).  Keep its identity tied to the stable panel id
            // so adding/removing tabs cannot reuse another panel's hook scope.
            .key(panel.panel_id)
            .expanded()
            .child(
                AleraDockPanelView {
                    panel,
                    controller,
                    renderers,
                    persist: persist.clone(),
                    preview_element,
                    key: DiffKey::default(),
                }
                .into_element(),
            )
            .into_element(),
    }
}

fn first_panel_id<TabId: Copy, PanelId: Copy>(node: &DockNode<TabId, PanelId>) -> Option<PanelId> {
    match node {
        DockNode::Panel(panel) => Some(panel.panel_id),
        DockNode::Split { children, .. } => children.first().and_then(first_panel_id),
    }
}

struct AleraDockPanelView<M: DockingModel> {
    panel: DockPanel<M::TabId, M::PanelId>,
    controller: Writable<M>,
    renderers: AleraRenderers<M::TabId, M::PanelId>,
    persist: Callback<(), ()>,
    preview_element: Option<Element>,
    key: DiffKey,
}

impl<M: DockingModel> Clone for AleraDockPanelView<M> {
    fn clone(&self) -> Self {
        Self {
            panel: self.panel.clone(),
            controller: self.controller.clone(),
            renderers: self.renderers.clone(),
            persist: self.persist.clone(),
            preview_element: self.preview_element.clone(),
            key: self.key.clone(),
        }
    }
}

impl<M: DockingModel> PartialEq for AleraDockPanelView<M> {
    fn eq(&self, _other: &Self) -> bool {
        false
    }
}

impl<M: DockingModel> KeyExt for AleraDockPanelView<M> {
    fn write_key(&mut self) -> &mut DiffKey {
        &mut self.key
    }
}

impl<M> ComponentOwned for AleraDockPanelView<M>
where
    M: DockingModel,
    M::PanelId: Hash,
{
    fn render(self) -> impl IntoElement {
        let AleraDockPanelView {
            panel:
                DockPanel {
                    panel_id,
                    tabs,
                    active_tab_id,
                },
            controller,
            renderers,
            persist,
            preview_element,
            ..
        } = self;

        let drag = use_drag::<AleraDockDrag<M::DropValue>>();
        let is_dragging = drag.read().is_some();
        let hover = use_state(|| None::<AleraHoverTarget<M::TabId>>);

        let hovered = is_dragging.then(&*hover).flatten();
        let tab_count = tabs.len();
        let mut tab_children: Vec<Element> = tabs
            .iter()
            .enumerate()
            .map(|(index, &tab_id)| {
                let handle = renderers.tab.call(TabContext {
                    tab_id,
                    is_drop_target: hovered == Some(AleraHoverTarget::Tab(tab_id)),
                });
                let dragger = DragZone::<AleraDockDrag<M::DropValue>>::new(
                    AleraDockDrag::new(M::DropValue::from(tab_id)),
                    handle,
                )
                .drag_element(renderers.drag.call(tab_id))
                .into_element();

                let activatable = rect()
                    .on_press({
                        let mut controller = controller.clone();
                        move |_| {
                            let _ =
                                controller.write_if(|mut state| state.set_active(panel_id, tab_id));
                        }
                    })
                    .child(dragger)
                    .into_element();

                DropZone::<AleraDockDrag<M::DropValue>>::new(activatable, {
                    let mut controller = controller.clone();
                    let persist = persist.clone();
                    move |payload: AleraDockDrag<M::DropValue>| {
                        if controller.write_if(|mut state| {
                            state.on_drop(
                                payload.value,
                                DropTarget::Tab {
                                    panel_id,
                                    position: index,
                                },
                            )
                        }) {
                            persist.call(());
                        }
                    }
                })
                .on_drag_over(move |hovering| {
                    toggle_alera_hover(hover, AleraHoverTarget::Tab(tab_id), hovering)
                })
                .key(tab_id)
                .into_element()
            })
            .collect();

        tab_children.push(
            DropZone::<AleraDockDrag<M::DropValue>>::new(rect().expanded().into_element(), {
                let mut controller = controller.clone();
                let persist = persist.clone();
                move |payload: AleraDockDrag<M::DropValue>| {
                    if controller.write_if(|mut state| {
                        state.on_drop(
                            payload.value,
                            DropTarget::Tab {
                                panel_id,
                                position: tab_count,
                            },
                        )
                    }) {
                        persist.call(());
                    }
                }
            })
            // This trailing zone owns a `use_drag` hook.  It moves whenever a
            // tab is inserted, so it needs a panel-scoped key instead of the
            // default positional identity; otherwise creating a tab reuses a
            // neighboring hook scope and Freya raises its hook-order dialog.
            .key(("tab-end", panel_id))
            .into_element(),
        );
        let tab_bar = renderers.bar.call(TabBarContext {
            panel_id,
            tab_children,
            tab_count,
        });

        let content = renderers.content.call(ContentContext {
            panel_id,
            tab_id: active_tab_id,
            tab_count,
        });

        let ghost = match (hover(), preview_element) {
            (Some(AleraHoverTarget::Edge(side)), Some(preview)) if is_dragging => {
                let (width, height) = match side {
                    Side::Top | Side::Bottom => (Size::percent(100.), Size::percent(50.)),
                    Side::Left | Side::Right => (Size::percent(50.), Size::percent(100.)),
                };
                let position = match side {
                    Side::Top | Side::Left => Position::new_absolute(),
                    Side::Bottom => Position::new_absolute().bottom(0.),
                    Side::Right => Position::new_absolute().right(0.),
                };
                Some(drag_preview(position, width, height, preview))
            }
            (Some(AleraHoverTarget::Center), Some(preview)) if is_dragging => Some(drag_preview(
                Position::new_absolute(),
                Size::percent(100.),
                Size::percent(100.),
                preview,
            )),
            _ => None,
        };

        let edge = |side: Side, width: Size, height: Size| -> Element {
            rect()
                .width(width)
                .height(height)
                .child(alera_drop_surface(
                    panel_id,
                    Some(side),
                    controller.clone(),
                    hover,
                    persist.clone(),
                ))
                .into_element()
        };

        let center_drop =
            alera_drop_surface(panel_id, None, controller.clone(), hover, persist.clone());

        let middle_row = rect()
            .width(Size::percent(100.))
            .height(Size::flex(ALERA_MIDDLE_FLEX))
            .horizontal()
            .content(Content::flex())
            .child(edge(Side::Left, Size::flex(1.), Size::percent(100.)))
            .child(
                rect()
                    .width(Size::flex(ALERA_MIDDLE_FLEX))
                    .height(Size::percent(100.))
                    .child(center_drop),
            )
            .child(edge(Side::Right, Size::flex(1.), Size::percent(100.)));

        let overlay = rect()
            .position(Position::new_absolute())
            .layer(Layer::Overlay)
            .width(Size::percent(100.))
            .height(Size::percent(100.))
            .interactive(is_dragging)
            .vertical()
            .content(Content::flex())
            .maybe_child(ghost)
            .child(edge(Side::Top, Size::percent(100.), Size::flex(1.)))
            .child(middle_row)
            .child(edge(Side::Bottom, Size::percent(100.), Size::flex(1.)))
            .into_element();

        rect()
            .a11y_role(AccessibilityRole::Pane)
            .expanded()
            .child(tab_bar)
            .child(
                rect()
                    .expanded()
                    .overflow(Overflow::Clip)
                    .child(content)
                    .child(overlay),
            )
    }

    fn render_key(&self) -> DiffKey {
        self.key.clone().or(self.default_key())
    }
}

fn alera_drop_surface<M: DockingModel>(
    panel_id: M::PanelId,
    side: Option<Side>,
    mut controller: Writable<M>,
    hover: State<Option<AleraHoverTarget<M::TabId>>>,
    persist: Callback<(), ()>,
) -> Element {
    let hover_target = side
        .map(AleraHoverTarget::Edge)
        .unwrap_or(AleraHoverTarget::Center);
    let drop_target = side
        .map(|side| DropTarget::Split { panel_id, side })
        .unwrap_or(DropTarget::Center(panel_id));
    DropZone::<AleraDockDrag<M::DropValue>>::new(
        rect().expanded().into_element(),
        move |payload: AleraDockDrag<M::DropValue>| {
            if controller.write_if(|mut state| state.on_drop(payload.value, drop_target.clone())) {
                persist.call(());
            }
        },
    )
    .on_drag_over(move |hovering| toggle_alera_hover(hover, hover_target, hovering))
    .into_element()
}

fn drag_preview(position: Position, width: Size, height: Size, preview: Element) -> Element {
    rect()
        .position(position)
        .interactive(false)
        .width(width)
        .height(height)
        .child(preview)
        .into_element()
}

#[derive(Clone, Debug)]
struct FreyaWorkspace {
    layout: WorkbenchLayout,
    tree: Option<DockNode<TabId, PanelId>>,
    next_panel_id: PanelId,
    next_tab_id: TabId,
    tab_titles: HashMap<TabId, String>,
    tab_kinds: HashMap<TabId, String>,
    tab_paths: HashMap<TabId, String>,
    tab_payloads: HashMap<TabId, Value>,
    tab_runtime_ids: HashMap<TabId, String>,
    loaded_workspace_id: String,
}

#[derive(Clone, Debug, PartialEq)]
struct TabPathUpdate {
    runtime_tab_id: String,
    kind: String,
    title: String,
    payload: Value,
}

impl FreyaWorkspace {
    fn new() -> Self {
        let layout = WorkbenchLayout {
            workspace_id: "main".to_string(),
            root: WorkbenchLayoutNode::Split {
                axis: WorkbenchSplitAxis::Horizontal,
                first: Box::new(WorkbenchLayoutNode::Leaf {
                    group_id: "panel-0".to_string(),
                }),
                second: Box::new(WorkbenchLayoutNode::Leaf {
                    group_id: "panel-1".to_string(),
                }),
                ratio: 0.5,
            },
            groups: BTreeMap::from([
                (
                    "panel-0".to_string(),
                    WorkbenchPaneGroup {
                        id: "panel-0".to_string(),
                        tab_ids: vec!["1".to_string(), "2".to_string()],
                        active_tab_id: Some("1".to_string()),
                    },
                ),
                (
                    "panel-1".to_string(),
                    WorkbenchPaneGroup {
                        id: "panel-1".to_string(),
                        tab_ids: vec!["3".to_string()],
                        active_tab_id: Some("3".to_string()),
                    },
                ),
            ]),
            active_group_id: "panel-0".to_string(),
        };
        let mut workspace = Self {
            layout,
            tree: None,
            next_panel_id: 2,
            next_tab_id: 4,
            tab_titles: HashMap::from([
                (1, "Terminal 1".to_string()),
                (2, "Terminal 2".to_string()),
                (3, "Terminal 3".to_string()),
            ]),
            tab_kinds: HashMap::from([
                (1, "terminal".to_string()),
                (2, "terminal".to_string()),
                (3, "terminal".to_string()),
            ]),
            tab_paths: HashMap::new(),
            tab_payloads: HashMap::new(),
            tab_runtime_ids: HashMap::from([
                (1, "1".to_string()),
                (2, "2".to_string()),
                (3, "3".to_string()),
            ]),
            loaded_workspace_id: "__freya_default__".to_string(),
        };
        workspace.sync_tree();
        workspace
    }

    fn apply_snapshot(&mut self, snapshot: &WorkbenchSnapshot, workspace_id: &str) {
        if self.loaded_workspace_id == workspace_id {
            return;
        }
        *self = Self::from_snapshot(snapshot, workspace_id);
    }

    fn from_snapshot(snapshot: &WorkbenchSnapshot, workspace_id: &str) -> Self {
        let tabs = snapshot
            .tabs
            .iter()
            .filter(|tab| tab.workspace_id == workspace_id)
            .collect::<Vec<_>>();
        let mut tab_titles = HashMap::new();
        let mut tab_kinds = HashMap::new();
        let mut tab_paths = HashMap::new();
        let mut tab_payloads = HashMap::new();
        let mut tab_runtime_ids = HashMap::new();
        let mut external_to_tab = HashMap::new();
        for (index, tab) in tabs.iter().enumerate() {
            let tab_id = index + 1;
            tab_titles.insert(tab_id, tab.title.clone());
            tab_kinds.insert(tab_id, tab.kind.clone());
            if let Some(path) = tab
                .payload
                .get("relativePath")
                .and_then(Value::as_str)
                .or_else(|| tab.payload.get("filePath").and_then(Value::as_str))
                .or_else(|| tab.payload.get("path").and_then(Value::as_str))
            {
                tab_paths.insert(tab_id, path.to_string());
            }
            tab_runtime_ids.insert(tab_id, tab.id.clone());
            tab_payloads.insert(tab_id, tab.payload.clone());
            external_to_tab.insert(tab.id.clone(), tab_id.to_string());
        }

        let mut layout = snapshot.layout.clone().unwrap_or_else(|| {
            let tab_ids = (1..=tabs.len()).map(|id| id.to_string()).collect();
            let mut groups = BTreeMap::new();
            groups.insert(
                "panel-0".to_string(),
                WorkbenchPaneGroup {
                    id: "panel-0".to_string(),
                    tab_ids,
                    active_tab_id: (!tabs.is_empty()).then(|| "1".to_string()),
                },
            );
            WorkbenchLayout {
                workspace_id: workspace_id.to_string(),
                root: WorkbenchLayoutNode::Leaf {
                    group_id: "panel-0".to_string(),
                },
                groups,
                active_group_id: "panel-0".to_string(),
            }
        });

        let group_ids = layout.groups.keys().cloned().collect::<Vec<_>>();
        let group_map = group_ids
            .iter()
            .enumerate()
            .map(|(index, group_id)| (group_id.clone(), format!("panel-{index}")))
            .collect::<HashMap<_, _>>();
        let mut remapped_groups = BTreeMap::new();
        for group_id in group_ids {
            let Some(group) = layout.groups.remove(&group_id) else {
                continue;
            };
            let remapped_id = group_map
                .get(&group_id)
                .cloned()
                .unwrap_or_else(|| "panel-0".to_string());
            let tab_ids = group
                .tab_ids
                .into_iter()
                .filter_map(|tab_id| external_to_tab.get(&tab_id).cloned())
                .collect::<Vec<_>>();
            let active_tab_id = group
                .active_tab_id
                .and_then(|tab_id| external_to_tab.get(&tab_id).cloned())
                .or_else(|| tab_ids.first().cloned());
            remapped_groups.insert(
                remapped_id.clone(),
                WorkbenchPaneGroup {
                    id: remapped_id,
                    tab_ids,
                    active_tab_id,
                },
            );
        }
        if remapped_groups.is_empty() {
            remapped_groups.insert(
                "panel-0".to_string(),
                WorkbenchPaneGroup {
                    id: "panel-0".to_string(),
                    tab_ids: (1..=tabs.len()).map(|id| id.to_string()).collect(),
                    active_tab_id: (!tabs.is_empty()).then(|| "1".to_string()),
                },
            );
        }
        layout.root = remap_layout_node(layout.root, &group_map);
        layout.active_group_id = group_map
            .get(&layout.active_group_id)
            .cloned()
            .or_else(|| remapped_groups.keys().next().cloned())
            .unwrap_or_else(|| "panel-0".to_string());
        layout.groups = remapped_groups;
        layout.workspace_id = workspace_id.to_string();
        layout.reconcile_tabs(
            &(1..=tabs.len())
                .map(|id| id.to_string())
                .collect::<Vec<_>>(),
        );

        let next_tab_id = tabs.len() + 1;
        let next_panel_id = layout
            .groups
            .keys()
            .filter_map(|id| id.strip_prefix("panel-")?.parse::<usize>().ok())
            .max()
            .map_or(0, |id| id + 1);
        let mut workspace = Self {
            layout,
            tree: None,
            next_panel_id,
            next_tab_id,
            tab_titles,
            tab_kinds,
            tab_paths,
            tab_payloads,
            tab_runtime_ids,
            loaded_workspace_id: workspace_id.to_string(),
        };
        workspace.sync_tree();
        workspace
    }

    fn runtime_tab_id(&self, tab_id: TabId) -> String {
        self.tab_runtime_ids
            .get(&tab_id)
            .cloned()
            .unwrap_or_else(|| tab_id.to_string())
    }

    fn tab_id_for_runtime(&self, runtime_tab_id: &str) -> Option<TabId> {
        self.tab_runtime_ids
            .iter()
            .find_map(|(tab_id, candidate)| (candidate == runtime_tab_id).then_some(*tab_id))
    }

    fn tab_kind(&self, tab_id: TabId) -> &str {
        self.tab_kinds
            .get(&tab_id)
            .map(String::as_str)
            .unwrap_or("terminal")
    }

    fn tab_path(&self, tab_id: TabId) -> Option<String> {
        self.tab_paths.get(&tab_id).cloned()
    }

    fn tab_payload(&self, tab_id: TabId) -> Value {
        self.tab_payloads
            .get(&tab_id)
            .cloned()
            .unwrap_or_else(|| json!({}))
    }

    fn rewrite_file_backed_paths(
        &mut self,
        old_relative_path: &str,
        new_relative_path: &str,
    ) -> Vec<TabPathUpdate> {
        let tab_ids = self.tab_kinds.keys().copied().collect::<Vec<_>>();
        let mut updates = Vec::new();
        for tab_id in tab_ids {
            let kind = self.tab_kind(tab_id).to_string();
            let mut payload = self.tab_payload(tab_id);
            let mut next_title = None;
            let changed = if matches!(kind.as_str(), "editor" | "markdownViewer") {
                let Some(path) = self.tab_path(tab_id) else {
                    continue;
                };
                let Some(next_path) =
                    replace_workspace_path_prefix(&path, old_relative_path, new_relative_path)
                else {
                    continue;
                };
                self.tab_paths.insert(tab_id, next_path.clone());
                update_file_path_payload(&mut payload, &next_path);
                next_title = relative_path_name(&next_path).map(str::to_string);
                true
            } else if kind == "gitDiff"
                && payload.get("gitDiffSource").and_then(Value::as_str) != Some("commit")
            {
                let mut changed = false;
                for key in ["filePath", "gitDiffOldPath", "gitDiffRoot"] {
                    let Some(path) = payload.get(key).and_then(Value::as_str) else {
                        continue;
                    };
                    if let Some(next_path) =
                        replace_workspace_path_prefix(path, old_relative_path, new_relative_path)
                    {
                        payload[key] = Value::String(next_path);
                        changed = true;
                    }
                }
                if changed {
                    next_title =
                        Some(GitDiffOpenRequest::from_payload(String::new(), &payload).title());
                }
                changed
            } else {
                false
            };
            if !changed {
                continue;
            }
            if let Some(title) = next_title {
                self.tab_titles.insert(tab_id, title);
            }
            self.tab_payloads.insert(tab_id, payload.clone());
            updates.push(TabPathUpdate {
                runtime_tab_id: self.runtime_tab_id(tab_id),
                kind,
                title: self.title(tab_id),
                payload,
            });
        }
        updates
    }

    fn panel_group_id(panel_id: PanelId) -> String {
        format!("panel-{panel_id}")
    }

    fn panel_id(group_id: &str) -> Option<PanelId> {
        group_id.strip_prefix("panel-")?.parse().ok()
    }

    fn projected_node(
        node: &WorkbenchLayoutNode,
        groups: &BTreeMap<String, WorkbenchPaneGroup>,
    ) -> Option<DockNode<TabId, PanelId>> {
        match node {
            WorkbenchLayoutNode::Leaf { group_id } => {
                let panel_id = Self::panel_id(group_id)?;
                let group = groups.get(group_id)?;
                let tabs = group
                    .tab_ids
                    .iter()
                    .filter_map(|tab_id| tab_id.parse().ok())
                    .collect::<Vec<_>>();
                let active_tab_id = group
                    .active_tab_id
                    .as_ref()
                    .and_then(|tab_id| tab_id.parse().ok());
                Some(DockNode::Panel(DockPanel {
                    panel_id,
                    tabs,
                    active_tab_id,
                }))
            }
            WorkbenchLayoutNode::Split {
                axis,
                first,
                second,
                ..
            } => {
                let direction = match axis {
                    WorkbenchSplitAxis::Horizontal => Direction::Horizontal,
                    WorkbenchSplitAxis::Vertical => Direction::Vertical,
                };
                let children = [first.as_ref(), second.as_ref()]
                    .into_iter()
                    .filter_map(|child| Self::projected_node(child, groups))
                    .collect::<Vec<_>>();
                match children.as_slice() {
                    [] => None,
                    [only] => Some(only.clone()),
                    _ => Some(DockNode::Split {
                        direction,
                        children,
                    }),
                }
            }
        }
    }

    fn sync_tree(&mut self) {
        self.tree = Self::projected_node(&self.layout.root, &self.layout.groups);
    }

    fn open_new_tab(&mut self) -> (TabId, String) {
        let tab_id = self.next_tab_id;
        self.next_tab_id += 1;
        let runtime_id = Uuid::new_v4().to_string();
        self.tab_titles.insert(tab_id, format!("Terminal {tab_id}"));
        self.tab_kinds.insert(tab_id, "terminal".to_string());
        self.tab_payloads.insert(
            tab_id,
            json!({"terminalSessionId": runtime_id.clone(), "spawnOnCreate": false}),
        );
        self.tab_runtime_ids.insert(tab_id, runtime_id.clone());
        self.layout.add_tab_to_active_group(tab_id.to_string());
        self.sync_tree();
        (tab_id, runtime_id)
    }

    fn close_tab(&mut self, tab_id: TabId) -> bool {
        let tab_key = tab_id.to_string();
        if !self
            .layout
            .groups
            .values()
            .any(|group| group.tab_ids.iter().any(|candidate| candidate == &tab_key))
        {
            return false;
        }
        self.layout.remove_tab(&tab_key);
        self.tab_titles.remove(&tab_id);
        self.tab_kinds.remove(&tab_id);
        self.tab_paths.remove(&tab_id);
        self.tab_payloads.remove(&tab_id);
        self.tab_runtime_ids.remove(&tab_id);
        self.sync_tree();
        true
    }

    fn tab_group(&self, tab_id: TabId) -> Option<String> {
        let tab_key = tab_id.to_string();
        self.layout
            .groups
            .iter()
            .find(|(_, group)| group.tab_ids.iter().any(|candidate| candidate == &tab_key))
            .map(|(group_id, _)| group_id.clone())
    }

    fn tabs_in_group(&self, group_id: &str) -> Vec<TabId> {
        self.layout
            .groups
            .get(group_id)
            .map(|group| {
                group
                    .tab_ids
                    .iter()
                    .filter_map(|tab_id| tab_id.parse::<TabId>().ok())
                    .collect()
            })
            .unwrap_or_default()
    }

    fn tabs_other_than(&self, tab_id: TabId) -> Vec<TabId> {
        self.tab_group(tab_id)
            .map(|group_id| {
                self.tabs_in_group(&group_id)
                    .into_iter()
                    .filter(|candidate| *candidate != tab_id)
                    .collect()
            })
            .unwrap_or_default()
    }

    fn tabs_to_right(&self, tab_id: TabId) -> Vec<TabId> {
        let Some(group_id) = self.tab_group(tab_id) else {
            return Vec::new();
        };
        let tabs = self.tabs_in_group(&group_id);
        let Some(index) = tabs.iter().position(|candidate| *candidate == tab_id) else {
            return Vec::new();
        };
        tabs.into_iter().skip(index + 1).collect()
    }

    /// Create the terminal pane used by the tab context menu's directional
    /// split actions.  The dragged-tab path remains in `on_drop`; menu splits
    /// intentionally create a new terminal, matching Flutter's menu action.
    fn split_with_terminal(
        &mut self,
        group_id: &str,
        direction: WorkbenchSplitDirection,
    ) -> Option<(TabId, String)> {
        if !self.layout.groups.contains_key(group_id) {
            return None;
        }
        let tab_id = self.next_tab_id;
        self.next_tab_id += 1;
        let runtime_id = Uuid::new_v4().to_string();
        self.tab_titles.insert(tab_id, format!("Terminal {tab_id}"));
        self.tab_kinds.insert(tab_id, "terminal".to_string());
        self.tab_payloads.insert(
            tab_id,
            json!({"terminalSessionId": runtime_id.clone(), "spawnOnCreate": false}),
        );
        self.tab_runtime_ids.insert(tab_id, runtime_id.clone());
        let new_group_id = Self::panel_group_id(self.next_panel_id);
        self.next_panel_id += 1;
        self.layout.split_group(
            group_id,
            direction,
            WorkbenchPaneGroup {
                id: new_group_id,
                tab_ids: vec![tab_id.to_string()],
                active_tab_id: Some(tab_id.to_string()),
            },
        );
        self.sync_tree();
        Some((tab_id, runtime_id))
    }

    fn open_editor_tab(&mut self, relative_path: &str) -> Option<(TabId, String)> {
        self.open_file_backed_tab(relative_path, "editor", None)
    }

    fn open_file_tab(&mut self, relative_path: &str) -> Option<(TabId, String)> {
        if is_markdown_path(relative_path) {
            self.open_file_backed_tab(relative_path, "markdownViewer", None)
        } else {
            self.open_editor_tab(relative_path)
        }
    }

    fn open_file_request(&mut self, request: &FileOpenRequest) -> Option<(TabId, String)> {
        if request.force_editor {
            self.open_editor_tab(&request.relative_path)
        } else {
            self.open_file_tab(&request.relative_path)
        }
    }

    fn open_file_backed_tab(
        &mut self,
        relative_path: &str,
        kind: &str,
        file_role: Option<&str>,
    ) -> Option<(TabId, String)> {
        let normalized = relative_path.trim_matches('/');
        if normalized.is_empty() {
            return None;
        }
        if let Some(tab_id) = self.tab_paths.iter().find_map(|(tab_id, path)| {
            (path == normalized
                && self.tab_kind(*tab_id) == kind
                && self
                    .tab_payloads
                    .get(tab_id)
                    .and_then(|payload| payload.get("fileRole"))
                    .and_then(Value::as_str)
                    == file_role)
                .then_some(*tab_id)
        }) {
            self.set_active_tab(tab_id);
            return Some((tab_id, self.runtime_tab_id(tab_id)));
        }
        let tab_id = self.next_tab_id;
        self.next_tab_id += 1;
        let runtime_id = Uuid::new_v4().to_string();
        self.tab_titles.insert(
            tab_id,
            normalized
                .rsplit('/')
                .next()
                .unwrap_or(normalized)
                .to_string(),
        );
        self.tab_kinds.insert(tab_id, kind.to_string());
        self.tab_paths.insert(tab_id, normalized.to_string());
        let mut payload = json!({"filePath": normalized});
        if let Some(file_role) = file_role {
            payload["fileRole"] = Value::String(file_role.to_string());
        }
        self.tab_payloads.insert(tab_id, payload);
        self.tab_runtime_ids.insert(tab_id, runtime_id.clone());
        self.layout.add_tab_to_active_group(tab_id.to_string());
        self.sync_tree();
        Some((tab_id, runtime_id))
    }

    fn open_git_diff_tab(&mut self, request: &GitDiffOpenRequest) -> (TabId, String, bool) {
        if let Some(tab_id) = self.tab_kinds.iter().find_map(|(tab_id, kind)| {
            (kind == "gitDiff"
                && self
                    .tab_payloads
                    .get(tab_id)
                    .is_some_and(|payload| request.matches_payload(payload)))
            .then_some(*tab_id)
        }) {
            self.set_active_tab(tab_id);
            return (tab_id, self.runtime_tab_id(tab_id), false);
        }

        let tab_id = self.next_tab_id;
        self.next_tab_id += 1;
        let runtime_id = Uuid::new_v4().to_string();
        self.tab_titles.insert(tab_id, request.title());
        self.tab_kinds.insert(tab_id, "gitDiff".to_string());
        self.tab_payloads.insert(tab_id, request.payload());
        self.tab_runtime_ids.insert(tab_id, runtime_id.clone());
        self.layout.add_tab_to_active_group(tab_id.to_string());
        self.sync_tree();
        (tab_id, runtime_id, true)
    }

    fn active_git_diff(&self, workspace_path: &str) -> Option<(String, GitDiffOpenRequest)> {
        let tab_id = self
            .layout
            .groups
            .get(&self.layout.active_group_id)?
            .active_tab_id
            .as_deref()?
            .parse::<TabId>()
            .ok()?;
        (self.tab_kind(tab_id) == "gitDiff").then(|| {
            (
                self.runtime_tab_id(tab_id),
                GitDiffOpenRequest::from_payload(
                    workspace_path.to_string(),
                    &self.tab_payload(tab_id),
                ),
            )
        })
    }

    #[cfg(test)]
    fn close_active(&mut self) -> bool {
        let Some(tab_id) = self
            .layout
            .groups
            .get(&self.layout.active_group_id)
            .and_then(|group| group.active_tab_id.as_deref())
            .and_then(|tab_id| tab_id.parse::<TabId>().ok())
        else {
            return false;
        };
        self.close_tab(tab_id)
    }

    fn rename_tab(&mut self, tab_id: TabId, title: &str) -> bool {
        let tab_key = tab_id.to_string();
        if title.trim().is_empty()
            || !self
                .layout
                .groups
                .values()
                .any(|group| group.tab_ids.iter().any(|candidate| candidate == &tab_key))
        {
            return false;
        }
        self.tab_titles.insert(tab_id, title.trim().to_string());
        self.sync_tree();
        true
    }

    fn title(&self, tab_id: TabId) -> String {
        self.tab_titles
            .get(&tab_id)
            .cloned()
            .unwrap_or_else(|| format!("Terminal {tab_id}"))
    }

    fn is_active(&self, tab_id: TabId) -> bool {
        self.layout
            .groups
            .get(&self.layout.active_group_id)
            .and_then(|group| group.active_tab_id.as_ref())
            .is_some_and(|active| active == &tab_id.to_string())
    }

    fn set_active_tab(&mut self, tab_id: TabId) -> bool {
        let Some(group_id) = self
            .layout
            .groups
            .iter()
            .find(|(_, group)| {
                group
                    .tab_ids
                    .iter()
                    .any(|candidate| candidate == &tab_id.to_string())
            })
            .map(|(group_id, _)| group_id.clone())
        else {
            return false;
        };
        self.layout.activate_tab(&tab_id.to_string());
        self.layout.active_group_id = group_id;
        self.sync_tree();
        true
    }

    fn drop_zone_to_direction(side: Side) -> WorkbenchDropZone {
        match side {
            Side::Top => WorkbenchDropZone::Up,
            Side::Bottom => WorkbenchDropZone::Down,
            Side::Left => WorkbenchDropZone::Left,
            Side::Right => WorkbenchDropZone::Right,
        }
    }

    fn ratio_for_panels(&self, first_panel: PanelId, second_panel: PanelId) -> f32 {
        let first_group = Self::panel_group_id(first_panel);
        let second_group = Self::panel_group_id(second_panel);
        find_layout_ratio(&self.layout.root, &first_group, &second_group).unwrap_or(0.5) as f32
    }
}

fn relative_path_name(path: &str) -> Option<&str> {
    path.trim_matches('/')
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
}

fn update_file_path_payload(payload: &mut Value, path: &str) {
    let Some(payload) = payload.as_object_mut() else {
        *payload = json!({"filePath": path});
        return;
    };
    let mut updated = false;
    for key in ["relativePath", "filePath", "path"] {
        if payload.contains_key(key) {
            payload.insert(key.to_string(), Value::String(path.to_string()));
            updated = true;
        }
    }
    if !updated {
        payload.insert("filePath".to_string(), Value::String(path.to_string()));
    }
}

fn find_layout_ratio(
    node: &WorkbenchLayoutNode,
    first_group: &str,
    second_group: &str,
) -> Option<f64> {
    match node {
        WorkbenchLayoutNode::Leaf { .. } => None,
        WorkbenchLayoutNode::Split {
            first,
            second,
            ratio,
            ..
        } => {
            if layout_contains_group(first, first_group)
                && layout_contains_group(second, second_group)
            {
                Some(*ratio)
            } else {
                find_layout_ratio(first, first_group, second_group)
                    .or_else(|| find_layout_ratio(second, first_group, second_group))
            }
        }
    }
}

fn queue_layout_persist(bridge: &RuntimeBridge, workspace: &Writable<FreyaWorkspace>) {
    let layout = workspace.read().layout.clone();
    let payload = json!({
        "workspaceId": layout.workspace_id,
        "data": layout.to_value(),
    });
    let _ = bridge.send_ordered("layout.upsert", payload);
}

fn layout_contains_group(node: &WorkbenchLayoutNode, group_id: &str) -> bool {
    match node {
        WorkbenchLayoutNode::Leaf {
            group_id: candidate,
        } => candidate == group_id,
        WorkbenchLayoutNode::Split { first, second, .. } => {
            layout_contains_group(first, group_id) || layout_contains_group(second, group_id)
        }
    }
}

impl DockingModel for FreyaWorkspace {
    type TabId = TabId;
    type PanelId = PanelId;
    type DropValue = TabId;

    fn root(&self) -> Option<&DockNode<TabId, PanelId>> {
        self.tree.as_ref()
    }

    fn on_drop(&mut self, tab_id: TabId, target: DropTarget<PanelId>) -> bool {
        let success = match target {
            DropTarget::Tab { panel_id, position } => self.layout.move_tab_to_group(
                &tab_id.to_string(),
                &Self::panel_group_id(panel_id),
                position,
            ),
            DropTarget::Center(panel_id) => self.layout.move_tab_to_group(
                &tab_id.to_string(),
                &Self::panel_group_id(panel_id),
                usize::MAX,
            ),
            DropTarget::Split { panel_id, side } => {
                let new_panel_id = self.next_panel_id;
                let new_group_id = Self::panel_group_id(new_panel_id);
                let success = self.layout.move_tab_to_drop(
                    &tab_id.to_string(),
                    &Self::panel_group_id(panel_id),
                    Self::drop_zone_to_direction(side),
                    &new_group_id,
                    None,
                );
                if success {
                    self.next_panel_id += 1;
                }
                success
            }
        };
        if success {
            self.sync_tree();
        }
        success
    }

    fn set_active(&mut self, panel_id: PanelId, tab_id: TabId) -> bool {
        let Some(group) = self.layout.groups.get(&Self::panel_group_id(panel_id)) else {
            return false;
        };
        if !group
            .tab_ids
            .iter()
            .any(|candidate| candidate == &tab_id.to_string())
        {
            return false;
        }
        self.layout.activate_tab(&tab_id.to_string());
        self.layout.active_group_id = Self::panel_group_id(panel_id);
        self.sync_tree();
        true
    }
}

fn remap_layout_node(
    node: WorkbenchLayoutNode,
    group_map: &HashMap<String, String>,
) -> WorkbenchLayoutNode {
    match node {
        WorkbenchLayoutNode::Leaf { group_id } => WorkbenchLayoutNode::Leaf {
            group_id: group_map.get(&group_id).cloned().unwrap_or(group_id),
        },
        WorkbenchLayoutNode::Split {
            axis,
            first,
            second,
            ratio,
        } => WorkbenchLayoutNode::Split {
            axis,
            first: Box::new(remap_layout_node(*first, group_map)),
            second: Box::new(remap_layout_node(*second, group_map)),
            ratio,
        },
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum AppChannel {
    Workspace,
}

#[derive(Clone, Debug)]
struct DirtyTabCloseConfirmation {
    tab_ids: Vec<TabId>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct EditorRevealRequest {
    generation: u64,
    runtime_tab_id: String,
    target: EditorRevealTarget,
}

pub(crate) fn alera_theme() -> Theme {
    let mut theme = dark_theme().with_dark_code_editor();
    theme.set(
        "code_editor",
        EditorThemePreference::from(EditorTheme {
            background: Color::from_rgb(16, 16, 16),
            gutter_selected: Color::from_rgb(245, 245, 245),
            gutter_unselected: Color::from_rgb(96, 96, 96),
            line_selected_background: Color::from_rgb(32, 32, 32),
            cursor: Color::from_rgb(224, 224, 224),
            highlight: Color::from_rgb(64, 64, 64),
            text: Color::from_rgb(245, 245, 245),
            whitespace: Color::from_af32rgb(0.2, 96, 96, 96),
        }),
    );
    theme.set("code_editor_syntax", alera_editor_syntax_theme());
    theme.set(
        "scrollbar",
        ScrollBarThemePreference {
            background: Preference::Specific(Color::from_af32rgb(0., 0, 0, 0)),
            thumb_background: Preference::Specific(Color::from_af32rgb(0., 0, 0, 0)),
            hover_thumb_background: Preference::Specific(Color::from_rgb(96, 96, 96)),
            active_thumb_background: Preference::Specific(Color::from_rgb(161, 161, 161)),
            size: Preference::Specific(12.),
        },
    );
    theme
}

impl RadioChannel<FreyaWorkspace> for AppChannel {}

#[allow(clippy::too_many_arguments)]
pub fn workbench(
    bridge: RuntimeBridge,
    runtime_context: Option<(String, String)>,
    snapshot_cache: State<Option<WorkbenchSnapshot>>,
    terminal_outputs: State<HashMap<String, Vec<u8>>>,
    terminal_output_tick: State<u64>,
    open_editor_path: State<Option<FileOpenRequest>>,
    editor_dirty_tabs: State<HashMap<String, String>>,
    editor_reload: State<Option<EditorReloadRequest>>,
    explorer_path_move: State<Option<ExplorerPathMove>>,
    open_git_diff_request: State<Option<GitDiffOpenRequest>>,
    rename_request: State<Option<TabId>>,
    rename_title: State<String>,
    selected_tab_request: State<Option<String>>,
    terminal_settings: State<StoredTerminalSettings>,
) -> Element {
    use_init_radio_station::<FreyaWorkspace, AppChannel>(FreyaWorkspace::new);

    let radio = use_radio::<FreyaWorkspace, AppChannel>(AppChannel::Workspace);
    let workspace = radio.slice_mut_current(|state| state).into_writable();
    let dirty_tab_close_confirmation = use_state(|| None::<DirtyTabCloseConfirmation>);
    let editor_reveal = use_state(|| None::<EditorRevealRequest>);
    let mut editor_reveal_for_open = editor_reveal;
    let mut open_editor_path_for_effect = open_editor_path;
    let open_bridge = bridge.clone();
    let mut workspace_for_open = workspace.clone();
    use_side_effect_with_deps(&open_editor_path.read().clone(), move |request| {
        let Some(request) = request.clone() else {
            return;
        };
        let mut opened = None;
        let _ = workspace_for_open.write_if(|mut state| {
            opened = state.open_file_request(&request);
            true
        });
        if let Some((tab_id, runtime_tab_id)) = opened {
            if let Some(target) = request.reveal.clone() {
                let generation = editor_reveal_for_open
                    .read()
                    .as_ref()
                    .map_or(1, |request| request.generation.saturating_add(1));
                editor_reveal_for_open.set(Some(EditorRevealRequest {
                    generation,
                    runtime_tab_id: runtime_tab_id.clone(),
                    target,
                }));
            }
            let workspace_id = workspace_for_open.read().layout.workspace_id.clone();
            let state = workspace_for_open.read();
            let title = state.title(tab_id);
            let kind = state.tab_kind(tab_id).to_string();
            let payload = state.tab_payload(tab_id);
            drop(state);
            let now = Utc::now().to_rfc3339();
            let _ = open_bridge.send_ordered(
                "tab.upsert",
                json!({
                    "id": runtime_tab_id,
                    "workspaceId": workspace_id,
                    "kind": kind,
                    "title": title,
                    "createdAt": now,
                    "updatedAt": now,
                    "payload": payload,
                }),
            );
            queue_layout_persist(&open_bridge, &workspace_for_open);
        }
        open_editor_path_for_effect.set(None);
    });
    let active_workspace_path = runtime_context
        .as_ref()
        .map(|(_, path)| path.clone())
        .unwrap_or_default();
    let path_move_deps = (
        explorer_path_move.read().clone(),
        active_workspace_path.clone(),
    );
    let path_move_bridge = bridge.clone();
    let mut workspace_for_path_move = workspace.clone();
    use_side_effect_with_deps(&path_move_deps, move |(path_move, workspace_path)| {
        let Some(path_move) = path_move.as_ref() else {
            return;
        };
        if path_move.workspace_path != *workspace_path {
            return;
        }
        let mut updates = Vec::new();
        let changed = workspace_for_path_move.write_if(|mut workspace| {
            updates = workspace.rewrite_file_backed_paths(
                &path_move.old_relative_path,
                &path_move.new_relative_path,
            );
            !updates.is_empty()
        });
        if !changed {
            return;
        }
        let workspace_id = workspace_for_path_move.read().layout.workspace_id.clone();
        let now = Utc::now().to_rfc3339();
        for update in updates {
            let _ = path_move_bridge.send_ordered(
                "tab.upsert",
                json!({
                    "id": update.runtime_tab_id,
                    "workspaceId": workspace_id,
                    "kind": update.kind,
                    "title": update.title,
                    "createdAt": now,
                    "updatedAt": now,
                    "payload": update.payload,
                }),
            );
        }
    });
    let desired_workspace_id = runtime_context
        .as_ref()
        .map(|(workspace_id, _)| workspace_id.clone())
        .unwrap_or_else(|| "main".to_string());
    let snapshot_cache_for_apply = snapshot_cache;
    let mut workspace_for_snapshot = workspace.clone();
    use_side_effect_with_deps(&desired_workspace_id, move |workspace_id| {
        let snapshot = snapshot_cache_for_apply.read().clone();
        if let Some(snapshot) = snapshot.as_ref().filter(|snapshot| {
            snapshot.selected_workspace_id.as_deref() == Some(workspace_id.as_str())
        }) {
            let _ = workspace_for_snapshot.write_if(|mut state| {
                state.apply_snapshot(snapshot, workspace_id);
                true
            });
        }
    });
    let selected_tab_deps = (
        desired_workspace_id.clone(),
        selected_tab_request.read().clone(),
        snapshot_cache
            .read()
            .as_ref()
            .map(|snapshot| snapshot.tabs.len())
            .unwrap_or_default(),
    );
    let mut selected_tab_request_for_effect = selected_tab_request;
    let mut workspace_for_selected_tab = workspace.clone();
    let selected_tab_bridge = bridge.clone();
    use_side_effect_with_deps(
        &selected_tab_deps,
        move |(_workspace_id, requested_tab_id, _tab_count)| {
            let Some(requested_tab_id) = requested_tab_id.as_deref() else {
                return;
            };
            let changed = workspace_for_selected_tab.write_if(|mut state| {
                state
                    .tab_id_for_runtime(requested_tab_id)
                    .is_some_and(|tab_id| state.set_active_tab(tab_id))
            });
            if changed {
                queue_layout_persist(&selected_tab_bridge, &workspace_for_selected_tab);
                selected_tab_request_for_effect.set(None);
            }
        },
    );

    let git_diff_results = use_state(HashMap::<String, GitDiffLoadState>::new);
    let git_diff_refresh_revision = use_state(|| 0_u64);
    let mut open_git_diff_for_effect = open_git_diff_request;
    let open_diff_bridge = bridge.clone();
    let mut workspace_for_diff_open = workspace.clone();
    use_side_effect_with_deps(&open_git_diff_request.read().clone(), move |request| {
        let Some(request) = request.clone() else {
            return;
        };
        let mut opened = None;
        let _ = workspace_for_diff_open.write_if(|mut state| {
            opened = Some(state.open_git_diff_tab(&request));
            true
        });
        if let Some((tab_id, runtime_tab_id, created)) = opened {
            if created {
                let workspace_id = workspace_for_diff_open.read().layout.workspace_id.clone();
                let title = workspace_for_diff_open.read().title(tab_id);
                let payload = workspace_for_diff_open.read().tab_payload(tab_id);
                let now = Utc::now().to_rfc3339();
                let _ = open_diff_bridge.send_ordered(
                    "tab.upsert",
                    json!({
                        "id": runtime_tab_id,
                        "workspaceId": workspace_id,
                        "kind": "gitDiff",
                        "title": title,
                        "createdAt": now,
                        "updatedAt": now,
                        "payload": payload,
                    }),
                );
            }
            queue_layout_persist(&open_diff_bridge, &workspace_for_diff_open);
        }
        open_git_diff_for_effect.set(None);
    });

    let working_directory_for_diff = runtime_context
        .as_ref()
        .map(|(_, path)| path.clone())
        .unwrap_or_else(|| ".".to_string());
    let active_git_diff = workspace
        .read()
        .active_git_diff(&working_directory_for_diff);
    let active_git_diff_deps = (active_git_diff.clone(), *git_diff_refresh_revision.read());
    let diff_bridge = bridge.clone();
    let mut diff_results_for_effect = git_diff_results;
    use_side_effect_with_deps(&active_git_diff_deps, move |deps| {
        let Some((runtime_tab_id, request)) = deps.0.clone() else {
            return;
        };
        let mut next = diff_results_for_effect.peek().clone();
        next.insert(runtime_tab_id.clone(), GitDiffLoadState::Loading);
        diff_results_for_effect.set(next);
        let bridge = diff_bridge.clone();
        let mut results = diff_results_for_effect;
        spawn(async move {
            let response = bridge
                .request(
                    "workspaceGit.diff",
                    json!({
                        "workspacePath": request.git_path,
                        "filePath": request.source_relative_path,
                        "area": request.area,
                        "commitId": request.commit_id,
                        "parentId": null,
                        "oldPath": request.source_old_path,
                    }),
                )
                .await
                .and_then(|value| parse_git_diff(&value));
            let mut next = results.read().clone();
            next.insert(runtime_tab_id, GitDiffLoadState::Loaded(response));
            results.set(next);
        });
    });
    let tab_workspace = workspace.clone();
    let add_workspace = workspace.clone();
    let close_workspace = workspace.clone();
    let ratio_workspace = workspace.clone();
    let add_bridge = bridge.clone();
    let content_bridge = bridge.clone();
    let tab_bridge = std::sync::Arc::new(bridge.clone());
    let close_bridge = bridge.clone();
    let layout_bridge = bridge.clone();

    let render_content = move |ctx: ContentContext<TabId, PanelId>| {
        let Some(tab_id) = ctx.tab_id else {
            return rect()
                .expanded()
                .center()
                .background((16, 16, 16))
                .color((150, 150, 150))
                .child("This panel has no open tabs.")
                .into_element();
        };
        let workspace_state = radio.read();
        let title = workspace_state.title(tab_id);
        let tab_kind = workspace_state.tab_kind(tab_id).to_string();
        let editor_path = workspace_state.tab_path(tab_id);
        let runtime_tab_id = workspace_state.runtime_tab_id(tab_id);
        let tab_payload = workspace_state.tab_payload(tab_id);
        let (workspace_id, working_directory) = runtime_context.clone().unwrap_or_else(|| {
            (
                "main".to_string(),
                std::env::current_dir().map_or_else(
                    |_| ".".to_string(),
                    |path| path.to_string_lossy().into_owned(),
                ),
            )
        });
        let file_role = tab_payload.get("fileRole").and_then(Value::as_str);
        if tab_kind == "markdownViewer" {
            MarkdownPreviewSurface {
                bridge: content_bridge.clone(),
                workspace_path: working_directory,
                relative_path: editor_path.unwrap_or_default(),
            }
            .into_element()
        } else if tab_kind == "editor"
            && file_role == Some("mermanPreview")
            && editor_path.as_deref().is_some_and(is_merman_path)
        {
            MermanPreviewSurface {
                bridge: content_bridge.clone(),
                workspace_path: working_directory,
                relative_path: editor_path.unwrap_or_default(),
            }
            .into_element()
        } else if tab_kind == "editor" && editor_path.as_deref().is_some_and(is_image_path) {
            ImagePreviewSurface {
                bridge: content_bridge.clone(),
                workspace_path: working_directory,
                relative_path: editor_path.unwrap_or_default(),
            }
            .into_element()
        } else if tab_kind == "editor" {
            let editor_path = editor_path.unwrap_or_default();
            let reload_generation = editor_reload
                .read()
                .as_ref()
                .filter(|request| {
                    request.workspace_path == working_directory
                        && request.relative_paths.contains(&editor_path)
                })
                .map_or(0, |request| request.generation);
            let reveal_request = editor_reveal
                .read()
                .as_ref()
                .filter(|request| request.runtime_tab_id == runtime_tab_id)
                .cloned();
            editor_surface(
                content_bridge.clone(),
                working_directory,
                editor_path,
                title,
                runtime_tab_id,
                editor_dirty_tabs,
                reload_generation,
                reveal_request,
            )
        } else if tab_kind == "gitDiff" {
            git_diff_surface(
                title,
                tab_payload,
                git_diff_results.read().get(&runtime_tab_id).cloned(),
                git_diff_refresh_revision,
                open_editor_path,
            )
        } else {
            rect()
                .key(ctx.panel_id)
                .child(FreyaTerminalSurface {
                    bridge: content_bridge.clone(),
                    panel_id: ctx.panel_id,
                    workspace_id,
                    working_directory,
                    tab_id: runtime_tab_id,
                    terminal_outputs,
                    terminal_output_tick,
                    terminal_settings,
                })
                .into_element()
        }
    };

    let render_tab = move |ctx: TabContext<TabId>| {
        let workspace = radio.read();
        let title = workspace.title(ctx.tab_id);
        let tab_kind = workspace.tab_kind(ctx.tab_id).to_string();
        let active = workspace.is_active(ctx.tab_id);
        let mut workspace_for_tab = tab_workspace.clone();
        let mut rename_title = rename_title;
        let rename_request = rename_request;
        let workspace_for_context = tab_workspace.clone();
        let workspace_for_close = tab_workspace.clone();
        let title_for_context = title.clone();
        let bridge_for_context = std::sync::Arc::new(tab_bridge.as_ref().clone());
        let bridge_for_close = std::sync::Arc::new(tab_bridge.as_ref().clone());
        let dirty_tabs_for_close = editor_dirty_tabs;
        let dirty_confirmation_for_close = dirty_tab_close_confirmation;
        let close_action = Callback::new(move |_| {
            close_tabs_with_dirty_guard(
                vec![ctx.tab_id],
                workspace_for_close.clone(),
                bridge_for_close.as_ref().clone(),
                dirty_tabs_for_close,
                dirty_confirmation_for_close,
            );
        });
        rect()
            .on_pointer_down(move |_| {
                let _ = workspace_for_tab.write_if(|mut state| state.set_active_tab(ctx.tab_id));
            })
            .on_secondary_down(move |event: Event<PressEventData>| {
                event.stop_propagation();
                rename_title.set(title_for_context.clone());
                ContextMenu::open_from_down(tab_context_menu(
                    ctx.tab_id,
                    rename_title,
                    rename_request,
                    workspace_for_context.clone(),
                    bridge_for_context.as_ref().clone(),
                    editor_dirty_tabs,
                    dirty_tab_close_confirmation,
                ));
            })
            .child(freya_tab_visual(
                title,
                tab_kind,
                active,
                false,
                Some(close_action),
            ))
            .into_element()
    };

    let render_drag = move |tab_id: TabId| {
        let workspace = radio.read();
        let title = workspace.title(tab_id);
        let tab_kind = workspace.tab_kind(tab_id).to_string();
        rect()
            .interactive(false)
            .child(freya_tab_visual(title, tab_kind, true, false, None))
            .into_element()
    };

    let render_tab_bar = |ctx: TabBarContext<PanelId>| {
        ScrollView::new()
            // Each split pane owns its own scroll controller hook.  Give the
            // bars stable panel identities before their tab list changes.
            .key(ctx.panel_id)
            .width(Size::fill())
            .direction(Direction::Horizontal)
            .height(Size::px(44.))
            .show_scrollbar(false)
            .child(
                rect()
                    .key(ctx.panel_id)
                    .width(Size::fill())
                    .padding(4.)
                    .spacing(4.)
                    .horizontal()
                    .cross_align(Alignment::Center)
                    .children(ctx.tab_children),
            )
            .into_element()
    };

    let rename_target = *rename_request.read();
    rect()
        .expanded()
        .child(
            rect()
                .height(Size::px(44.))
                .background((28, 28, 28))
                .border(Border::new().width(1.).fill((50, 50, 50)))
                .horizontal()
                .cross_align(Alignment::Center)
                .padding(Gaps::new(8., 4., 8., 4.))
                .spacing(4.)
                .child(
                    rect()
                        .width(Size::px(28.))
                        .height(Size::px(28.))
                        .center()
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("New Terminal Tab")
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            let mut workspace = add_workspace.clone();
                            let mut created = None;
                            let _ = workspace.write_if(|mut state| {
                                created = Some(state.open_new_tab());
                                true
                            });
                            let Some((tab_id, runtime_tab_id)) = created else {
                                return;
                            };
                            let workspace_id = workspace.read().layout.workspace_id.clone();
                            let title = workspace.read().title(tab_id);
                            let now = Utc::now().to_rfc3339();
                            let _ = add_bridge.send_ordered(
                                "tab.upsert",
                                json!({
                                    "id": runtime_tab_id.clone(),
                                    "workspaceId": workspace_id,
                                    "kind": "terminal",
                                    "title": title,
                                    "createdAt": now,
                                    "updatedAt": now,
                                    "payload": {
                                        "terminalSessionId": runtime_tab_id,
                                        "spawnOnCreate": false,
                                    },
                                }),
                            );
                            queue_layout_persist(&add_bridge, &workspace);
                        })
                        .child(
                            rect()
                                .interactive(false)
                                .child(label().color(MUTED).text("+")),
                        ),
                )
                .child(
                    rect()
                        .width(Size::px(28.))
                        .height(Size::px(28.))
                        .center()
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt("Close Active Tab")
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            let workspace = close_workspace.clone();
                            let Some(tab_id) = ({
                                let state = workspace.read();
                                state
                                    .layout
                                    .groups
                                    .get(&state.layout.active_group_id)
                                    .and_then(|group| group.active_tab_id.clone())
                                    .and_then(|tab_id| tab_id.parse::<TabId>().ok())
                            }) else {
                                return;
                            };
                            close_tabs_with_dirty_guard(
                                vec![tab_id],
                                workspace,
                                close_bridge.clone(),
                                editor_dirty_tabs,
                                dirty_tab_close_confirmation,
                            );
                        })
                        .child(
                            rect()
                                .interactive(false)
                                .child(label().color(MUTED).text("×")),
                        ),
                )
                .child(rect().width(Size::flex(1.)).child("")),
        )
        .child(
            AleraDockingArea::new(
                workspace.clone(),
                render_content,
                render_tab,
                render_drag,
                render_tab_bar,
                move |(first_panel, second_panel)| {
                    ratio_workspace
                        .read()
                        .ratio_for_panels(first_panel, second_panel)
                        * 100.
                },
                Callback::new({
                    let workspace = workspace.clone();
                    move |_| queue_layout_persist(&layout_bridge, &workspace)
                }),
            )
            .preview_element(
                rect()
                    .interactive(false)
                    .expanded()
                    .background((255, 255, 255, 0.10)),
            ),
        )
        .maybe_child(rename_target.map(|tab_id| {
            tab_title_overlay(
                tab_id,
                rename_request,
                rename_title,
                workspace.clone(),
                bridge.clone(),
            )
        }))
        .maybe_child(
            dirty_tab_close_confirmation
                .read()
                .clone()
                .map(|confirmation| {
                    dirty_tab_close_overlay(
                        confirmation,
                        dirty_tab_close_confirmation,
                        editor_dirty_tabs,
                        workspace,
                        bridge,
                    )
                }),
        )
        .into()
}

fn close_tabs_with_dirty_guard(
    tab_ids: Vec<TabId>,
    workspace: Writable<FreyaWorkspace>,
    bridge: RuntimeBridge,
    dirty_tabs: State<HashMap<String, String>>,
    mut confirmation: State<Option<DirtyTabCloseConfirmation>>,
) {
    let has_unsaved_editor =
        tabs_include_unsaved_editor(&tab_ids, &workspace.read(), &dirty_tabs.read());
    if has_unsaved_editor {
        confirmation.set(Some(DirtyTabCloseConfirmation { tab_ids }));
        return;
    }
    execute_close_tabs(tab_ids, workspace, bridge, dirty_tabs);
}

fn tabs_include_unsaved_editor(
    tab_ids: &[TabId],
    workspace: &FreyaWorkspace,
    dirty_tabs: &HashMap<String, String>,
) -> bool {
    tab_ids.iter().any(|tab_id| {
        workspace.tab_kind(*tab_id) == "editor"
            && dirty_tabs.contains_key(&workspace.runtime_tab_id(*tab_id))
    })
}

fn execute_close_tabs(
    tab_ids: Vec<TabId>,
    mut workspace: Writable<FreyaWorkspace>,
    bridge: RuntimeBridge,
    mut dirty_tabs: State<HashMap<String, String>>,
) {
    let runtime_tab_ids = {
        let workspace = workspace.read();
        tab_ids
            .iter()
            .map(|tab_id| (*tab_id, workspace.runtime_tab_id(*tab_id)))
            .collect::<Vec<_>>()
    };
    let mut closed_runtime_tab_ids = Vec::new();
    let changed = workspace.write_if(|mut state| {
        for (tab_id, runtime_tab_id) in &runtime_tab_ids {
            if state.close_tab(*tab_id) {
                closed_runtime_tab_ids.push(runtime_tab_id.clone());
            }
        }
        !closed_runtime_tab_ids.is_empty()
    });
    if !changed {
        return;
    }
    {
        let mut dirty_tabs = dirty_tabs.write();
        for runtime_tab_id in &closed_runtime_tab_ids {
            dirty_tabs.remove(runtime_tab_id);
        }
    }
    for runtime_tab_id in closed_runtime_tab_ids {
        let _ = bridge.send_ordered("tab.remove", json!({"id": runtime_tab_id}));
    }
    queue_layout_persist(&bridge, &workspace);
}

fn dirty_tab_close_overlay(
    confirmation: DirtyTabCloseConfirmation,
    confirmation_state: State<Option<DirtyTabCloseConfirmation>>,
    dirty_tabs: State<HashMap<String, String>>,
    workspace: Writable<FreyaWorkspace>,
    bridge: RuntimeBridge,
) -> Element {
    let tab_count = confirmation.tab_ids.len();
    let message = if tab_count == 1 {
        "This Editor Has Unsaved Changes. Discard Them And Close The Tab?".to_string()
    } else {
        format!(
            "Some Of These {tab_count} Tabs Have Unsaved Changes. Discard Them And Close The Tabs?"
        )
    };
    let mut close_from_overlay = confirmation_state;
    let mut close_from_cancel = confirmation_state;
    let mut close_from_discard = confirmation_state;
    let discard_tab_ids = confirmation.tab_ids;
    let discard = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        execute_close_tabs(
            discard_tab_ids.clone(),
            workspace.clone(),
            bridge.clone(),
            dirty_tabs,
        );
        close_from_discard.set(None);
    };
    rect()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.55, 0, 0, 0))
        .on_press(move |_| close_from_overlay.set(None))
        .child(
            rect()
                .position(Position::new_absolute())
                .width(Size::percent(100.))
                .height(Size::percent(100.))
                .center()
                .child(
                    rect()
                        .width(Size::px(430.))
                        .background(SURFACE_RAISED)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(10.)
                        .padding(Gaps::new_all(20.))
                        .vertical()
                        .spacing(13.)
                        .on_press(|event: Event<PressEventData>| event.stop_propagation())
                        .child(
                            label()
                                .font_size(17.)
                                .color(TEXT)
                                .text("Discard Unsaved Changes?"),
                        )
                        .child(label().font_size(12.).color(MUTED).text(message))
                        .child(
                            rect()
                                .width(Size::fill())
                                .height(Size::px(30.))
                                .horizontal()
                                .content(Content::Flex)
                                .spacing(8.)
                                .child(rect().width(Size::flex(1.)).child(""))
                                .child(
                                    rect()
                                        .height(Size::fill())
                                        .padding(Gaps::new(10., 0., 10., 0.))
                                        .center()
                                        .corner_radius(7.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Cancel")
                                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(move |event: Event<PointerEventData>| {
                                            event.stop_propagation();
                                            close_from_cancel.set(None);
                                        })
                                        .child(label().font_size(11.).color(MUTED).text("Cancel")),
                                )
                                .child(
                                    rect()
                                        .height(Size::fill())
                                        .padding(Gaps::new(12., 0., 12., 0.))
                                        .center()
                                        .background((220, 38, 38))
                                        .corner_radius(7.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Discard")
                                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(discard)
                                        .child(
                                            label()
                                                .font_size(11.)
                                                .color(BACKGROUND)
                                                .text("Discard"),
                                        ),
                                ),
                        ),
                ),
        )
        .into_element()
}

fn tab_context_menu(
    tab_id: TabId,
    rename_title: State<String>,
    rename_request: State<Option<TabId>>,
    workspace: Writable<FreyaWorkspace>,
    bridge: RuntimeBridge,
    dirty_tabs: State<HashMap<String, String>>,
    dirty_confirmation: State<Option<DirtyTabCloseConfirmation>>,
) -> Menu {
    let group_id = workspace.read().tab_group(tab_id);
    let close_others = workspace.read().tabs_other_than(tab_id);
    let close_right = workspace.read().tabs_to_right(tab_id);
    // Keep a fixed content column so the overlay stays compact like
    // Flutter's tab menu. The rows carry explicit accessibility roles below.
    let mut menu_items = rect()
        .width(Size::px(238.))
        .vertical()
        .content(Content::fit());

    for (label_text, direction) in [
        ("Split Up", WorkbenchSplitDirection::Up),
        ("Split Down", WorkbenchSplitDirection::Down),
        ("Split Left", WorkbenchSplitDirection::Left),
        ("Split Right", WorkbenchSplitDirection::Right),
    ] {
        let target_group = group_id.clone();
        let mut split_workspace = workspace.clone();
        let split_bridge = bridge.clone();
        menu_items = menu_items.child(
            MenuButton::new()
                .on_press(move |_| {
                    let Some(target_group) = target_group.as_deref() else {
                        ContextMenu::close();
                        return;
                    };
                    let mut created = None;
                    let changed = split_workspace.write_if(|mut state| {
                        created = state.split_with_terminal(target_group, direction);
                        created.is_some()
                    });
                    if changed && let Some((created_tab_id, runtime_tab_id)) = created {
                        let workspace_id = split_workspace.read().layout.workspace_id.clone();
                        let title = split_workspace.read().title(created_tab_id);
                        let now = Utc::now().to_rfc3339();
                        let _ = split_bridge.send_ordered(
                            "tab.upsert",
                            json!({
                                "id": runtime_tab_id.clone(),
                                "workspaceId": workspace_id,
                                "kind": "terminal",
                                "title": title,
                                "createdAt": now,
                                "updatedAt": now,
                                "payload": {
                                    "terminalSessionId": runtime_tab_id,
                                    "spawnOnCreate": false,
                                },
                            }),
                        );
                        queue_layout_persist(&split_bridge, &split_workspace);
                    }
                    ContextMenu::close();
                })
                .child(tab_context_menu_item(label_text, MUTED)),
        );
    }

    menu_items = menu_items.child(
        rect()
            .width(Size::fill())
            .height(Size::px(1.))
            .margin((4., 0.))
            .background(BORDER)
            .interactive(false),
    );

    let close_workspace = workspace.clone();
    let close_bridge = bridge.clone();
    menu_items = menu_items.child(
        MenuButton::new()
            .on_press(move |_| {
                ContextMenu::close();
                close_tabs_with_dirty_guard(
                    vec![tab_id],
                    close_workspace.clone(),
                    close_bridge.clone(),
                    dirty_tabs,
                    dirty_confirmation,
                );
            })
            .child(tab_context_menu_item("Close", MUTED)),
    );

    if close_others.is_empty() {
        menu_items =
            menu_items.child(MenuButton::new().child(tab_context_menu_item("Close Others", FAINT)));
    } else {
        let ids = close_others.clone();
        let close_workspace = workspace.clone();
        let close_bridge = bridge.clone();
        menu_items = menu_items.child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    close_tabs_with_dirty_guard(
                        ids.clone(),
                        close_workspace.clone(),
                        close_bridge.clone(),
                        dirty_tabs,
                        dirty_confirmation,
                    );
                })
                .child(tab_context_menu_item("Close Others", MUTED)),
        );
    }

    if close_right.is_empty() {
        menu_items = menu_items.child(
            MenuButton::new().child(tab_context_menu_item("Close Tabs to the Right", FAINT)),
        );
    } else {
        let ids = close_right.clone();
        let close_workspace = workspace.clone();
        let close_bridge = bridge.clone();
        menu_items = menu_items.child(
            MenuButton::new()
                .on_press(move |_| {
                    ContextMenu::close();
                    close_tabs_with_dirty_guard(
                        ids.clone(),
                        close_workspace.clone(),
                        close_bridge.clone(),
                        dirty_tabs,
                        dirty_confirmation,
                    );
                })
                .child(tab_context_menu_item("Close Tabs to the Right", MUTED)),
        );
    }

    menu_items = menu_items.child(
        rect()
            .width(Size::fill())
            .height(Size::px(1.))
            .margin((4., 0.))
            .background(BORDER)
            .interactive(false),
    );

    let current_title = workspace.read().title(tab_id);
    let mut request = rename_request;
    let mut title = rename_title;
    menu_items = menu_items.child(
        rect()
            .width(Size::px(206.))
            .height(Size::px(28.))
            .horizontal()
            .cross_align(Alignment::Center)
            .a11y_role(AccessibilityRole::Button)
            .a11y_alt("Change Title")
            .on_pointer_down(move |event: Event<PointerEventData>| {
                event.stop_propagation();
                title.set(current_title.clone());
                request.set(Some(tab_id));
            })
            .child(tab_context_menu_item("Change Title", MUTED)),
    );
    menu_items = menu_items.child(
        MenuButton::new()
            .on_press(|_| ContextMenu::close())
            .child(tab_context_menu_item("Dismiss menu", MUTED)),
    );
    Menu::new().child(menu_items)
}

fn tab_title_overlay(
    tab_id: TabId,
    mut request: State<Option<TabId>>,
    title: State<String>,
    workspace: Writable<FreyaWorkspace>,
    bridge: RuntimeBridge,
) -> Element {
    let mut save_workspace = workspace;
    let save_bridge = bridge;
    let save_title = title;
    let save = move |_| {
        let value = save_title.read().trim().to_string();
        if !value.is_empty() {
            let runtime_tab_id = save_workspace.read().runtime_tab_id(tab_id);
            if save_workspace.write_if(|mut state| state.rename_tab(tab_id, &value)) {
                let _ = save_bridge
                    .send_ordered("tab.rename", json!({"id": runtime_tab_id, "title": value}));
                queue_layout_persist(&save_bridge, &save_workspace);
            }
        }
        request.set(None);
    };
    let mut cancel_request = request;
    rect()
        .expanded()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.55, 0, 0, 0))
        .on_press(move |_| request.set(None))
        .child(
            rect()
                .position(Position::new_absolute())
                .width(Size::percent(100.))
                .height(Size::percent(100.))
                .center()
                .child(
                    rect()
                        .width(Size::px(420.))
                        .background(SURFACE_RAISED)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(10.)
                        .padding(Gaps::new_all(18.))
                        .vertical()
                        .spacing(12.)
                        .on_press(|event: Event<PressEventData>| event.stop_propagation())
                        .child(
                            rect()
                                .horizontal()
                                .cross_align(Alignment::Center)
                                .spacing(8.)
                                .child(
                                    label()
                                        .font_size(18.)
                                        .color(TEXT)
                                        .text("Change Terminal Title"),
                                ),
                        )
                        .child(label().font_size(11.).color(MUTED).text("Terminal Title"))
                        .child(
                            Input::new(title)
                                .width(Size::fill())
                                .compact()
                                .filled()
                                .auto_focus(true)
                                .theme_colors(
                                    InputColorsThemePartial::new()
                                        .background(SURFACE)
                                        .focus_background(SURFACE)
                                        .border_fill(BORDER)
                                        .focus_border_fill(ACCENT)
                                        .color(TEXT)
                                        .placeholder_color(MUTED),
                                ),
                        )
                        .child(
                            rect()
                                .horizontal()
                                .content(Content::Flex)
                                .cross_align(Alignment::Center)
                                .child(rect().width(Size::flex(1.)).child(""))
                                .child(
                                    rect()
                                        .height(Size::px(30.))
                                        .padding(Gaps::new(10., 6., 10., 6.))
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Cancel")
                                        .on_pointer_down(move |_| cancel_request.set(None))
                                        .child(label().font_size(12.).color(MUTED).text("Cancel")),
                                )
                                .child(
                                    rect()
                                        .height(Size::px(30.))
                                        .padding(Gaps::new(12., 6., 12., 6.))
                                        .background((228, 228, 228))
                                        .border(Border::new().width(1.).fill((228, 228, 228)))
                                        .corner_radius(5.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Change Title")
                                        .on_pointer_down(save)
                                        .child(
                                            label()
                                                .font_size(12.)
                                                .color(BACKGROUND)
                                                .text("Change Title"),
                                        ),
                                ),
                        ),
                ),
        )
        .into()
}

fn tab_context_menu_item(label_text: &'static str, color: (u8, u8, u8)) -> Element {
    let icon = match label_text {
        "Split Up" => icons::lucide::square_arrow_up(),
        "Split Down" => icons::lucide::square_arrow_down(),
        "Split Left" => icons::lucide::square_chevron_left(),
        "Split Right" => icons::lucide::square_chevron_right(),
        "Close" => icons::lucide::x(),
        "Close Others" => icons::lucide::square_equal(),
        "Close Tabs to the Right" => icons::lucide::arrow_right(),
        "Change Title" => icons::lucide::square_pen(),
        "Dismiss menu" => icons::lucide::x(),
        "Save" => icons::lucide::check(),
        "Cancel" => icons::lucide::x(),
        _ => icons::lucide::circle(),
    };
    rect()
        .width(Size::px(206.))
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(8.)
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(label_text)
        .child(
            SvgViewer::new(icon)
                .width(Size::px(14.))
                .height(Size::px(14.))
                .color(color),
        )
        .child(label().color(color).text(label_text))
        .into_element()
}

#[derive(Clone, PartialEq)]
struct TerminalTarget {
    workspace_id: String,
    working_directory: String,
    tab_id: String,
}

#[derive(Clone)]
struct FreyaTerminalSurface {
    bridge: RuntimeBridge,
    panel_id: PanelId,
    workspace_id: String,
    working_directory: String,
    tab_id: String,
    terminal_outputs: State<HashMap<String, Vec<u8>>>,
    terminal_output_tick: State<u64>,
    terminal_settings: State<StoredTerminalSettings>,
}

impl PartialEq for FreyaTerminalSurface {
    fn eq(&self, other: &Self) -> bool {
        self.workspace_id == other.workspace_id
            && self.panel_id == other.panel_id
            && self.working_directory == other.working_directory
            && self.tab_id == other.tab_id
    }
}

impl Component for FreyaTerminalSurface {
    fn render(&self) -> impl IntoElement {
        let bridge = self.bridge.clone();
        let target = TerminalTarget {
            workspace_id: self.workspace_id.clone(),
            working_directory: self.working_directory.clone(),
            tab_id: self.tab_id.clone(),
        };
        let mut terminal_outputs = self.terminal_outputs;
        let _terminal_output_revision = *self.terminal_output_tick.read();
        let preferences = self.terminal_settings.read().clone();
        let cursor_visible = use_state(|| true);
        let mut cursor_visible_for_task = cursor_visible;
        let terminal_settings_for_cursor = self.terminal_settings;
        let terminal_a11y_id = use_a11y();
        let _terminal_focus = use_focus(terminal_a11y_id);
        use_hook(move || {
            spawn(async move {
                loop {
                    Timer::after(std::time::Duration::from_millis(550)).await;
                    if terminal_settings_for_cursor.peek().terminal_cursor_blink {
                        let next = !*cursor_visible_for_task.peek();
                        cursor_visible_for_task.set(next);
                    } else {
                        cursor_visible_for_task.set_if_modified(true);
                    }
                }
            });
        });
        let cursor_visible = !preferences.terminal_cursor_blink || *cursor_visible.read();
        let session_id = format!("freya-{}-{}", target.workspace_id, target.tab_id);
        let session_store = use_hook({
            let session_key = session_id.clone();
            move || {
                let mut session = TerminalSession::new(session_key);
                session.attaching = true;
                Arc::new(Mutex::new(session))
            }
        });
        let session_revision = use_state(|| 0_u64);
        let _session_revision = *session_revision.read();
        let ime_preedit = use_state(String::new);
        let terminal_area = use_state(Area::default);
        let selection_dragging = use_state(|| false);
        let selection_drag_origin = use_state(|| None::<(f64, f64)>);
        let last_resized_grid = use_state(|| None::<(String, usize, usize)>);
        // The content component is keyed by panel, not by tab.  A tab switch
        // therefore updates one stable hook scope instead of removing one
        // `use_future` scope and inserting another in the same frame.  The
        // task watches the latest target and keeps the terminal session state
        // aligned with it without relying on conditional hooks.
        let desired_target =
            use_hook(|| std::sync::Arc::new(std::sync::Mutex::new(None::<TerminalTarget>)));
        {
            let mut desired = desired_target
                .lock()
                .expect("terminal target lock poisoned");
            if desired.as_ref() != Some(&target) {
                *desired = Some(target.clone());
            }
        }
        let desired_target_for_task = desired_target.clone();
        let session_for_task = session_store.clone();
        let bridge_for_task = bridge.clone();
        let mut session_revision_for_task = session_revision;
        use_hook(move || {
            spawn_forever(async move {
                let bridge = bridge_for_task;
                let desired_target = desired_target_for_task;
                let session = session_for_task;
                let mut attached_key = None::<String>;
                loop {
                    Timer::after(std::time::Duration::from_millis(30)).await;
                    let target = desired_target
                        .lock()
                        .expect("terminal target lock poisoned")
                        .clone();
                    let Some(target) = target else {
                        continue;
                    };
                    let target_key = format!("{}:{}", target.workspace_id, target.tab_id);
                    if attached_key.as_deref() == Some(target_key.as_str()) {
                        continue;
                    }
                    let expected_session_id =
                        format!("freya-{}-{}", target.workspace_id, target.tab_id);
                    {
                        let mut current = session.lock().expect("terminal session lock poisoned");
                        if current.session_id != expected_session_id {
                            *current = TerminalSession::new(expected_session_id.clone());
                        }
                        current.attaching = true;
                    }
                    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
                    let result = bridge
                        .request(
                            "createOrAttach",
                            json!({
                                "sessionId": expected_session_id,
                                "workspaceId": target.workspace_id,
                                "tabId": target.tab_id,
                                "workingDirectory": target.working_directory,
                                "launch": {
                                    "label": "Shell",
                                    "shell": shell,
                                    "arguments": [],
                                    "environment": {
                                        "TERM": "xterm-256color",
                                        "COLORTERM": "truecolor",
                                    },
                                },
                                "cols": 100,
                                "rows": 30,
                            }),
                        )
                        .await;
                    let still_current = desired_target
                        .lock()
                        .expect("terminal target lock poisoned")
                        .as_ref()
                        .is_some_and(|current| {
                            format!("{}:{}", current.workspace_id, current.tab_id) == target_key
                        });
                    if !still_current {
                        continue;
                    }
                    let mut current = session.lock().expect("terminal session lock poisoned");
                    if current.session_id != expected_session_id {
                        continue;
                    }
                    current.attaching = false;
                    match result {
                        Ok(payload) => {
                            let columns = payload
                                .get("cols")
                                .and_then(serde_json::Value::as_u64)
                                .map(|value| value as usize)
                                .unwrap_or(100);
                            let rows = payload
                                .get("rows")
                                .and_then(serde_json::Value::as_u64)
                                .map(|value| value as usize)
                                .unwrap_or(30);
                            let mut emulator = TerminalEmulator::new(columns, rows);
                            if let Some(encoded) = payload
                                .get("snapshotBase64")
                                .and_then(serde_json::Value::as_str)
                            {
                                match BASE64_STANDARD.decode(encoded) {
                                    Ok(bytes) => emulator.write(&bytes),
                                    Err(error) => current.error = Some(error.to_string()),
                                }
                            }
                            current.columns = columns;
                            current.rows = rows;
                            current.running = payload
                                .get("running")
                                .and_then(serde_json::Value::as_bool)
                                .unwrap_or(true);
                            current.emulator = emulator;
                        }
                        Err(error) => {
                            current.error = Some(error);
                            current.emulator.write(b"Alera Runtime Unavailable\r\n$ ");
                        }
                    }
                    drop(current);
                    let next_revision = session_revision_for_task.peek().saturating_add(1);
                    session_revision_for_task.set(next_revision);
                    attached_key = Some(target_key);
                }
            });
        });

        // Runtime output is collected once by the app-level event pump and then
        // applied to the matching emulator here.  This keeps sessions isolated
        // even when several dock panels are streaming at the same time.
        let pending_output = terminal_outputs.write().remove(&session_id);
        if let Some(bytes) = pending_output
            && let Ok(mut session) = session_store.lock()
        {
            session.emulator.write(&bytes);
        }

        let resize_bridge = bridge.clone();
        let resize_session = session_store.clone();
        let resize_session_id = session_id.clone();
        let resize_preferences = preferences.clone();
        let resize_area = terminal_area;
        let resize_revision = session_revision;
        let mut resize_last_grid = last_resized_grid;
        let mut resize_repaint_revision = session_revision;
        use_side_effect(move || {
            let _session_revision = *resize_revision.read();
            let area = *resize_area.read();
            let content_width =
                (area.size.width - (resize_preferences.terminal_padding_x as f32 * 2.)).max(0.);
            let content_height =
                (area.size.height - (resize_preferences.terminal_padding_y as f32 * 2.)).max(0.);
            let cell_width = (resize_preferences.terminal_font_size as f32 * 0.6).max(1.);
            let row_height = (resize_preferences.terminal_font_size
                * resize_preferences.terminal_line_height) as f32;
            if content_width <= 0. || content_height <= 0. || cell_width <= 0. || row_height <= 0. {
                return;
            }
            let columns = ((content_width / cell_width).floor() as usize).max(2);
            let rows = ((content_height / row_height).floor() as usize).max(2);
            let resize_key = (resize_session_id.clone(), columns, rows);
            if resize_last_grid.read().as_ref() == Some(&resize_key) {
                return;
            }
            let ready = resize_session
                .lock()
                .map(|session| !session.attaching && session.session_id == resize_session_id)
                .unwrap_or(false);
            if !ready {
                return;
            }
            if resize_bridge
                .send_ordered(
                    "resize",
                    json!({
                        "sessionId": resize_session_id,
                        "cols": columns,
                        "rows": rows,
                    }),
                )
                .is_err()
            {
                return;
            }
            if let Ok(mut session) = resize_session.lock() {
                session.emulator.resize(columns, rows);
                session.columns = columns;
                session.rows = rows;
            }
            resize_last_grid.set(Some(resize_key));
            let next_revision = resize_repaint_revision.peek().saturating_add(1);
            resize_repaint_revision.set(next_revision);
        });

        let key_session = session_store.clone();
        let key_bridge = bridge.clone();
        let key_session_id = session_id.clone();
        let key_preedit = ime_preedit;
        let on_key_down = move |event: Event<KeyboardEventData>| {
            let Some(key_name) = freya_terminal_key_name(&event.key) else {
                return;
            };
            let clipboard_shortcut = terminal_clipboard_shortcut(&key_name, event.modifiers);
            if clipboard_shortcut == Some(TerminalClipboardShortcut::Copy) {
                if let Some(selected_text) = key_session
                    .lock()
                    .ok()
                    .and_then(|session| session.emulator.selected_text())
                {
                    let _ = Clipboard::set(selected_text);
                }
                event.prevent_default();
                event.stop_propagation();
                return;
            }
            if clipboard_shortcut == Some(TerminalClipboardShortcut::Paste) {
                if let Ok(text) = Clipboard::get() {
                    let bytes = key_session
                        .lock()
                        .map(|session| session.emulator.encode_paste(&text))
                        .unwrap_or_default();
                    if !bytes.is_empty() {
                        let _ = key_bridge.send_ordered(
                            "write",
                            json!({
                                "sessionId": key_session_id,
                                "dataBase64": BASE64_STANDARD.encode(bytes),
                            }),
                        );
                    }
                }
                event.prevent_default();
                event.stop_propagation();
                return;
            }
            let text = event.try_as_str().map(str::to_owned);
            let preedit = key_preedit.read().clone();
            // A dead key is delivered both as a key event and as IME preedit on
            // macOS.  Do not send the preedit marker to the PTY; the following
            // committed character (for example "á") is sent as one UTF-8 value.
            if !preedit.is_empty() && text.as_deref() == Some(preedit.as_str()) {
                return;
            }
            let modifiers = KeyModifiers {
                control: event.modifiers.contains(Modifiers::CONTROL),
                alt: event.modifiers.contains(Modifiers::ALT),
                shift: event.modifiers.contains(Modifiers::SHIFT),
                platform: event.modifiers.contains(Modifiers::META),
                function: false,
            };
            let bytes = key_session
                .lock()
                .map(|session| {
                    session
                        .emulator
                        .encode_key(&key_name, text.as_deref(), modifiers)
                })
                .unwrap_or_default();
            if bytes.is_empty() {
                return;
            }
            if key_bridge
                .send_ordered(
                    "write",
                    json!({
                        "sessionId": key_session_id,
                        "dataBase64": BASE64_STANDARD.encode(bytes),
                    }),
                )
                .is_ok()
            {
                event.stop_propagation();
            }
        };
        let mut preedit_state = ime_preedit;
        let frame = session_store
            .lock()
            .map(|session| session.emulator.frame())
            .unwrap_or_default();
        let cursor = frame.cursor;
        let palette = preferences.resolved_palette();
        let foreground = color_from_rgb24(palette.foreground, 1.);
        let background = color_from_rgb24(
            palette.background,
            preferences.terminal_background_opacity as f32,
        );
        let selection = color_from_rgb24(palette.selection, 1.);
        let row_style = TerminalRowStyle {
            cursor_shape: &preferences.terminal_cursor_shape,
            foreground,
            background,
            selection,
            palette,
            cursor_opacity: preferences.terminal_cursor_opacity as f32,
            font_size: preferences.terminal_font_size as f32,
            line_height: preferences.terminal_line_height as f32,
            cell_width: (preferences.terminal_font_size as f32 * 0.6).max(1.),
        };
        let rows = frame
            .rows
            .iter()
            .enumerate()
            .map(|(row_index, row)| {
                terminal_row(
                    row,
                    row_index,
                    cursor,
                    frame.selection,
                    cursor_visible,
                    row_style,
                )
            })
            .collect::<Vec<_>>();

        let mut terminal_area_for_sized = terminal_area;
        let selection_down_session = session_store.clone();
        let mut selection_down_dragging = selection_dragging;
        let mut selection_down_origin = selection_drag_origin;
        let mut selection_down_revision = session_revision;
        let selection_padding_x = preferences.terminal_padding_x;
        let selection_padding_y = preferences.terminal_padding_y;
        let selection_row_height =
            preferences.terminal_font_size * preferences.terminal_line_height;
        let selection_cell_width = (preferences.terminal_font_size * 0.6).max(1.);
        let on_terminal_mouse_down = move |event: Event<MouseEventData>| {
            terminal_a11y_id.request_focus();
            if event.button != Some(MouseButton::Left) {
                return;
            }
            selection_down_origin.set(Some((
                event.global_location.x - event.element_location.x,
                event.global_location.y - event.element_location.y,
            )));
            let column = ((event.element_location.x - selection_padding_x).max(0.)
                / selection_cell_width) as f32;
            let row = ((event.element_location.y - selection_padding_y).max(0.)
                / selection_row_height.max(1.)) as f32;
            let mode = match EventsCombos::pressed(event.element_location) {
                PressEventType::Double => TerminalSelectionMode::Semantic,
                PressEventType::Triple => TerminalSelectionMode::Lines,
                _ => TerminalSelectionMode::Simple,
            };
            if let Ok(mut session) = selection_down_session.lock() {
                session.emulator.start_selection(row, column, mode);
            }
            selection_down_dragging.set(true);
            let next_revision = selection_down_revision.peek().saturating_add(1);
            selection_down_revision.set(next_revision);
            event.stop_propagation();
            event.prevent_default();
        };

        let selection_move_session = session_store.clone();
        let selection_move_dragging = selection_dragging;
        let selection_move_origin = selection_drag_origin;
        let mut selection_move_revision = session_revision;
        let on_terminal_pointer_move = move |event: Event<PointerEventData>| {
            if !*selection_move_dragging.peek() {
                return;
            }
            let Some((origin_x, origin_y)) = *selection_move_origin.peek() else {
                return;
            };
            let location_x = event.global_location().x - origin_x;
            let location_y = event.global_location().y - origin_y;
            let column = ((location_x - selection_padding_x).max(0.) / selection_cell_width) as f32;
            let row =
                ((location_y - selection_padding_y).max(0.) / selection_row_height.max(1.)) as f32;
            if let Ok(mut session) = selection_move_session.lock() {
                session.emulator.update_selection(row, column);
            }
            let next_revision = selection_move_revision.peek().saturating_add(1);
            selection_move_revision.set(next_revision);
        };

        let selection_release_session = session_store.clone();
        let mut selection_release_dragging = selection_dragging;
        let mut selection_release_origin = selection_drag_origin;
        let mut selection_release_revision = session_revision;
        let copy_on_select = preferences.terminal_clipboard_on_select;
        let on_terminal_pointer_release = move |event: Event<PointerEventData>| {
            if !*selection_release_dragging.peek() {
                return;
            }
            let Some((origin_x, origin_y)) = *selection_release_origin.peek() else {
                selection_release_dragging.set(false);
                return;
            };
            let location_x = event.global_location().x - origin_x;
            let location_y = event.global_location().y - origin_y;
            let column = ((location_x - selection_padding_x).max(0.) / selection_cell_width) as f32;
            let row =
                ((location_y - selection_padding_y).max(0.) / selection_row_height.max(1.)) as f32;
            let selected_text = selection_release_session
                .lock()
                .ok()
                .and_then(|mut session| {
                    session.emulator.update_selection(row, column);
                    session.emulator.selected_text()
                });
            if copy_on_select && let Some(selected_text) = selected_text {
                let _ = Clipboard::set(selected_text);
            }
            selection_release_dragging.set(false);
            selection_release_origin.set(None);
            let next_revision = selection_release_revision.peek().saturating_add(1);
            selection_release_revision.set(next_revision);
        };

        let wheel_session = session_store.clone();
        let mut wheel_revision = session_revision;
        let scroll_sensitivity = preferences.terminal_tui_scroll_sensitivity.max(1) as i32;
        let on_terminal_wheel = move |event: Event<WheelEventData>| {
            let lines = ((event.delta_y.abs().ceil() as i32).max(1) * scroll_sensitivity).min(30);
            let delta = if event.delta_y > 0. { lines } else { -lines };
            if let Ok(mut session) = wheel_session.lock() {
                session.emulator.scroll_display(delta);
            }
            let next_revision = wheel_revision.peek().saturating_add(1);
            wheel_revision.set(next_revision);
            event.stop_propagation();
        };

        rect()
            .expanded()
            .padding(Gaps::new(
                preferences.terminal_padding_x as f32,
                preferences.terminal_padding_y as f32,
                preferences.terminal_padding_x as f32,
                preferences.terminal_padding_y as f32,
            ))
            .background(background)
            .font_family(preferences.terminal_font_family.clone())
            .font_size(preferences.terminal_font_size as f32)
            .font_weight(FontWeight::from(preferences.terminal_font_weight as i32))
            .a11y_id(terminal_a11y_id)
            .a11y_role(AccessibilityRole::Terminal)
            .a11y_focusable(true)
            .on_sized(move |event: Event<SizedEventData>| {
                terminal_area_for_sized.set_if_modified(event.area);
            })
            .on_mouse_down(on_terminal_mouse_down)
            .on_global_pointer_move(on_terminal_pointer_move)
            .on_global_pointer_press(on_terminal_pointer_release)
            .on_wheel(on_terminal_wheel)
            .on_ime_preedit(move |event: Event<ImePreeditEventData>| {
                preedit_state.set(event.data().text.clone());
            })
            .on_key_down(on_key_down)
            .children(rows)
            .into_element()
    }

    fn render_key(&self) -> DiffKey {
        // Keep the hook scope stable while the active tab changes. The panel
        // owns one terminal surface and swaps its target in place; keying by
        // tab id would remove and reinsert a `use_future` task mid-frame.
        DiffKey::from(&self.panel_id)
    }
}

fn git_diff_surface(
    title: String,
    payload: Value,
    state: Option<GitDiffLoadState>,
    refresh_revision: State<u64>,
    open_editor_path: State<Option<FileOpenRequest>>,
) -> Element {
    let commit_diff = payload
        .get("gitDiffSource")
        .and_then(Value::as_str)
        .is_some_and(|source| source == "commit");
    let open_path = payload
        .get("filePath")
        .and_then(Value::as_str)
        .map(str::to_string);
    let can_open_file = !commit_diff && open_path.is_some();
    let loading = matches!(state, None | Some(GitDiffLoadState::Loading));
    let mut refresh_for_button = refresh_revision;
    let mut open_editor_for_button = open_editor_path;
    let open_path_for_button = open_path.clone();
    let toolbar = rect()
        .width(Size::fill())
        .height(Size::px(44.))
        .padding(Gaps::new(12., 4., 8., 4.))
        .background(SURFACE)
        .border(Border::new().width(1.).fill(BORDER))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(12.)
                .font_weight(FontWeight::MEDIUM)
                .color(TEXT)
                .max_lines(1)
                .text_overflow(TextOverflow::Ellipsis)
                .text(title),
        )
        .child(
            rect()
                .width(Size::px(28.))
                .height(Size::px(28.))
                .center()
                .corner_radius(5.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Open File")
                .on_pointer_enter(move |_| {
                    if can_open_file {
                        Cursor::set(CursorIcon::Pointer);
                    }
                })
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    if let Some(path) = open_path_for_button.clone() {
                        event.stop_propagation();
                        open_editor_for_button.set(Some(FileOpenRequest::editor(path)));
                    }
                })
                .child(
                    SvgViewer::new(icons::lucide::external_link())
                        .width(Size::px(16.))
                        .height(Size::px(16.))
                        .color(if can_open_file { MUTED } else { FAINT }),
                ),
        )
        .child(
            rect()
                .width(Size::px(28.))
                .height(Size::px(28.))
                .center()
                .corner_radius(5.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Refresh Diff")
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    let next = refresh_for_button.read().saturating_add(1);
                    refresh_for_button.set(next);
                })
                .child(if loading {
                    CircularLoader::new().size(15.).into_element()
                } else {
                    SvgViewer::new(icons::lucide::refresh_cw())
                        .width(Size::px(16.))
                        .height(Size::px(16.))
                        .color(MUTED)
                        .into_element()
                }),
        );

    let body = match state {
        None | Some(GitDiffLoadState::Loading) => rect()
            .expanded()
            .center()
            .horizontal()
            .spacing(8.)
            .child(CircularLoader::new().size(15.))
            .child(label().font_size(12.).color(MUTED).text("Loading Diff"))
            .into_element(),
        Some(GitDiffLoadState::Loaded(Err(error))) => rect()
            .expanded()
            .center()
            .padding(20.)
            .child(label().font_size(12.).color((248, 113, 113)).text(error))
            .into_element(),
        Some(GitDiffLoadState::Loaded(Ok(result))) if result.files.is_empty() => rect()
            .expanded()
            .center()
            .child(
                label()
                    .font_size(12.)
                    .color(MUTED)
                    .text("No Diff Available."),
            )
            .into_element(),
        Some(GitDiffLoadState::Loaded(Ok(result))) => {
            let mut files = rect().width(Size::fill()).vertical();
            if result.truncated {
                files = files.child(git_diff_banner("Diff Truncated For Preview"));
            }
            for file in result.files {
                files = files.child(render_git_diff_file(&file, commit_diff));
            }
            ScrollView::new()
                .width(Size::fill())
                .height(Size::fill())
                .show_scrollbar(true)
                .child(files)
                .into_element()
        }
    };

    rect()
        .expanded()
        .vertical()
        .content(Content::Flex)
        .background(BACKGROUND)
        .child(toolbar)
        .child(body)
        .into_element()
}

fn render_git_diff_file(file: &GitDiffFile, commit_diff: bool) -> Element {
    let display_path = file.old_path.as_ref().map_or_else(
        || file.path.clone(),
        |old_path| format!("{old_path} -> {}", file.path),
    );
    let scope = if commit_diff {
        "Commit"
    } else {
        title_case_git_area(&file.area)
    };
    let mut header = rect()
        .width(Size::fill())
        .height(Size::px(32.))
        .padding(Gaps::new(12., 4., 12., 4.))
        .background(SURFACE_RAISED)
        .border(Border::new().width(1.).fill(BORDER))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(8.)
        .child(
            SvgViewer::new(icons::lucide::file())
                .width(Size::px(15.))
                .height(Size::px(15.))
                .color(MUTED),
        )
        .child(
            label()
                .width(Size::flex(1.))
                .font_family("JetBrains Mono")
                .font_size(12.)
                .color(TEXT)
                .max_lines(1)
                .text_overflow(TextOverflow::Ellipsis)
                .text(format!("{scope} · {display_path}")),
        );
    if file.added.unwrap_or_default() > 0 {
        header = header.child(
            label()
                .font_size(11.)
                .color((74, 222, 128))
                .text(format!("+{}", file.added.unwrap_or_default())),
        );
    }
    if file.removed.unwrap_or_default() > 0 {
        header = header.child(
            label()
                .font_size(11.)
                .color((248, 113, 113))
                .text(format!("-{}", file.removed.unwrap_or_default())),
        );
    }

    let mut content = rect().width(Size::fill()).vertical().child(header);
    if file.is_binary {
        content = content.child(git_diff_banner("Binary File Diff Is Not Shown"));
    } else if file.is_large {
        content = content.child(git_diff_banner("Large Untracked File Diff Is Not Shown"));
    } else if file.lines.is_empty() {
        content = content.child(git_diff_banner("No Text Diff For This File"));
    } else {
        for line in file
            .lines
            .iter()
            .filter(|line| !commit_diff || !line.kind.eq_ignore_ascii_case("header"))
        {
            let kind = line.kind.to_ascii_lowercase();
            let (foreground, background) = match kind.as_str() {
                "addition" => ((74, 222, 128), (19, 78, 48, 0.40)),
                "deletion" => ((248, 113, 113), (127, 29, 29, 0.35)),
                "hunk" => ((251, 191, 36), (38, 38, 38, 1.0)),
                _ => ((160, 160, 160), (0, 0, 0, 0.0)),
            };
            content = content.child(
                rect()
                    .width(Size::fill())
                    .min_height(Size::px(20.))
                    .padding(Gaps::new(12., 2., 12., 2.))
                    .background(background)
                    .child(
                        label()
                            .font_family("JetBrains Mono")
                            .font_size(12.)
                            .color(foreground)
                            .text(line.text.clone()),
                    ),
            );
        }
    }
    if file.line_preview_truncated {
        content = content.child(git_diff_banner("Diff Line Preview Truncated"));
    }
    if file.truncated {
        content = content.child(git_diff_banner("File Diff Truncated For Preview"));
    }
    content.into_element()
}

fn git_diff_banner(message: &'static str) -> Element {
    rect()
        .width(Size::fill())
        .padding(12.)
        .child(label().font_size(12.).color(MUTED).text(message))
        .into_element()
}

fn parse_git_diff(value: &Value) -> Result<GitDiffResult, String> {
    let files = value
        .get("files")
        .and_then(Value::as_array)
        .ok_or_else(|| "Workspace Git Diff Response Omitted Files.".to_string())?
        .iter()
        .map(|file| {
            let required = |key: &str| {
                file.get(key)
                    .and_then(Value::as_str)
                    .map(str::to_string)
                    .ok_or_else(|| format!("Workspace Git Diff File Omitted {key}."))
            };
            let lines = file
                .get("lines")
                .and_then(Value::as_array)
                .ok_or_else(|| "Workspace Git Diff File Omitted Lines.".to_string())?
                .iter()
                .map(|line| {
                    Ok(GitDiffLine {
                        text: line
                            .get("text")
                            .and_then(Value::as_str)
                            .ok_or_else(|| "Workspace Git Diff Line Omitted Text.".to_string())?
                            .to_string(),
                        kind: line
                            .get("kind")
                            .and_then(Value::as_str)
                            .ok_or_else(|| "Workspace Git Diff Line Omitted Kind.".to_string())?
                            .to_string(),
                    })
                })
                .collect::<Result<Vec<_>, String>>()?;
            Ok(GitDiffFile {
                path: required("path")?,
                old_path: file
                    .get("oldPath")
                    .and_then(Value::as_str)
                    .map(str::to_string),
                area: required("area")?,
                status: required("status")?,
                lines,
                added: file.get("added").and_then(Value::as_u64),
                removed: file.get("removed").and_then(Value::as_u64),
                is_binary: file
                    .get("isBinary")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                is_large: file
                    .get("isLarge")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                is_gitlink: file
                    .get("isGitlink")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                truncated: file
                    .get("truncated")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                line_preview_truncated: file
                    .get("linePreviewTruncated")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(GitDiffResult {
        files,
        truncated: value
            .get("truncated")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

fn short_commit_id(commit_id: &str) -> String {
    commit_id.chars().take(7).collect()
}

fn title_case_git_area(area: &str) -> &'static str {
    match area.to_ascii_lowercase().as_str() {
        "staged" => "Staged",
        "untracked" => "Untracked",
        _ => "Unstaged",
    }
}

#[derive(Clone)]
struct FreyaEditorSurface {
    bridge: RuntimeBridge,
    workspace_path: String,
    relative_path: String,
    title: String,
    runtime_tab_id: String,
    dirty_tabs: State<HashMap<String, String>>,
    reload_generation: u64,
    reveal_request: Option<EditorRevealRequest>,
}

#[derive(Clone, Debug, PartialEq)]
struct FreyaEditorDocument {
    raw_content: Option<String>,
    display_content: String,
    content_token: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
struct EditorSaveConflict {
    document: FreyaEditorDocument,
    display_content: String,
}

fn parse_editor_document(value: &Value) -> Result<FreyaEditorDocument, String> {
    value
        .get("displayContent")
        .and_then(Value::as_str)
        .map(|display_content| FreyaEditorDocument {
            raw_content: value
                .get("rawContent")
                .and_then(Value::as_str)
                .map(str::to_string),
            display_content: display_content.to_string(),
            content_token: value
                .get("contentToken")
                .and_then(Value::as_str)
                .map(str::to_string),
        })
        .ok_or_else(|| "Editor response omitted displayContent".to_string())
}

fn editor_language_for_path(path: &str) -> Option<EditorLanguage> {
    path.strip_suffix(".json").map(|_| {
        EditorLanguage::new(
            tree_sitter_json::LANGUAGE,
            tree_sitter_json::HIGHLIGHTS_QUERY,
        )
    })
}

fn alera_editor_syntax_theme() -> EditorSyntaxTheme {
    let text = Color::from_rgb(245, 245, 245);
    let faint = Color::from_rgb(96, 96, 96);
    let keyword = Color::from_rgb(199, 146, 234);
    let operator = Color::from_rgb(137, 221, 255);
    let function = Color::from_rgb(130, 170, 255);
    let literal = Color::from_rgb(255, 203, 107);
    let variable = Color::from_rgb(255, 204, 128);
    let success = Color::from_rgb(34, 197, 94);
    let warning = Color::from_rgb(245, 158, 11);
    EditorSyntaxTheme {
        text,
        whitespace: Color::from_af32rgb(0.2, 96, 96, 96),
        attribute: literal,
        boolean: keyword,
        comment: faint,
        constant: keyword,
        constructor: literal,
        escape: operator,
        function,
        function_macro: function,
        function_method: function,
        keyword,
        label: literal,
        module: literal,
        number: warning,
        operator,
        property: function,
        punctuation: text,
        punctuation_bracket: text,
        punctuation_delimiter: text,
        punctuation_special: operator,
        string: success,
        string_escape: literal,
        string_special: success,
        tag: keyword,
        text_literal: literal,
        text_reference: operator,
        text_title: literal,
        text_uri: operator,
        text_emphasis: text,
        type_: operator,
        variable,
        variable_builtin: keyword,
        variable_parameter: variable,
    }
}

impl PartialEq for FreyaEditorSurface {
    fn eq(&self, other: &Self) -> bool {
        self.workspace_path == other.workspace_path
            && self.relative_path == other.relative_path
            && self.title == other.title
            && self.runtime_tab_id == other.runtime_tab_id
            && self.reload_generation == other.reload_generation
            && self.reveal_request == other.reveal_request
    }
}

impl Component for FreyaEditorSurface {
    fn render(&self) -> impl IntoElement {
        let bridge = self.bridge.clone();
        let workspace_path = self.workspace_path.clone();
        let relative_path = self.relative_path.clone();
        let document = use_future(move || {
            let bridge = bridge.clone();
            let workspace_path = workspace_path.clone();
            let relative_path = relative_path.clone();
            async move {
                bridge
                    .request(
                        "workspaceFiles.readEditor",
                        json!({
                            "workspacePath": workspace_path,
                            "relativePath": relative_path,
                            "tabSize": 4,
                        }),
                    )
                    .await
                    .and_then(|value| parse_editor_document(&value))
            }
        });
        let editor_language = editor_language_for_path(&self.relative_path);
        let mut editor = use_state(move || {
            let mut data = CodeEditorData::new(Rope::from_str("Loading…"), editor_language.clone());
            data.set_theme(alera_editor_syntax_theme());
            data.measure(14., "JetBrains Mono");
            data
        });
        let loaded_document = match &*document.state() {
            FutureState::Fulfilled(Ok(document)) => Some(document.clone()),
            _ => None,
        };
        let mut document_for_save = use_state(|| None::<FreyaEditorDocument>);
        let mut applied_reveal_generation = use_state(|| 0_u64);
        // Freya's async future can complete between two layout passes. Load
        // the document into the editor as soon as the fulfilled value is
        // visible, guarded by the sentinel rope so this write cannot loop.
        if let Some(document) = loaded_document.as_ref() {
            let is_loading = {
                let editor_data = editor.read();
                editor_data.rope.chars().eq("Loading…".chars())
            };
            if is_loading {
                let mut editor_data = editor.write();
                editor_data.rope = Rope::from_str(&document.display_content);
                editor_data.parse();
                editor_data.measure(14., "JetBrains Mono");
            }
            if document_for_save.read().is_none() {
                document_for_save.set(Some(document.clone()));
            }
        }
        if let Some(request) = self.reveal_request.as_ref().filter(|request| {
            request.generation > *applied_reveal_generation.read() && loaded_document.is_some()
        }) {
            apply_editor_reveal(&mut editor.write(), &request.target);
            applied_reveal_generation.set(request.generation);
        }
        let saving = use_state(|| false);
        let save_error = use_state(|| None::<String>);
        let save_conflict = use_state(|| None::<EditorSaveConflict>);
        let save_bridge = self.bridge.clone();
        let save_workspace_path = self.workspace_path.clone();
        let save_relative_path = self.relative_path.clone();
        let mut saving_for_key = saving;
        let mut save_error_for_key = save_error;
        let mut save_conflict_for_key = save_conflict;
        let editor_for_key = editor;
        let document_for_key = document_for_save;
        let on_pre_key_down = move |event: Event<KeyboardEventData>| {
            let is_save = matches!(&event.key, Key::Character(key) if key.eq_ignore_ascii_case("s"))
                && event.modifiers.contains(Modifiers::ctrl_or_meta());
            if !is_save {
                return true;
            }
            event.prevent_default();
            event.stop_propagation();
            if *saving_for_key.read() {
                return false;
            }
            let Some(document) = document_for_key.read().clone() else {
                return false;
            };
            let content = editor_for_key.read().to_string();
            let conflict_content = content.clone();
            let conflict_document = document.clone();
            saving_for_key.set(true);
            save_error_for_key.set(None);
            let bridge = save_bridge.clone();
            let workspace_path = save_workspace_path.clone();
            let relative_path = save_relative_path.clone();
            let mut saving = saving_for_key;
            let mut save_error = save_error_for_key;
            let mut editor = editor_for_key;
            let mut document_state = document_for_key;
            spawn(async move {
                let result = bridge
                    .request(
                        "workspaceFiles.writeEditor",
                        json!({
                            "workspacePath": workspace_path,
                            "relativePath": relative_path,
                            "currentDisplayContent": content,
                            "originalRawContent": document.raw_content,
                            "originalDisplayContent": document.display_content,
                            "expectedContentToken": document.content_token,
                            "overwriteIfChanged": false,
                            "tabSize": 4,
                        }),
                    )
                    .await
                    .and_then(|value| parse_editor_document(&value));
                match result {
                    Ok(document) => {
                        editor.write().mark_as_saved();
                        document_state.set(Some(document));
                        saving.set(false);
                    }
                    Err(error) => {
                        if is_editor_conflict_error(&error) {
                            save_conflict_for_key.set(Some(EditorSaveConflict {
                                document: conflict_document,
                                display_content: conflict_content,
                            }));
                        } else {
                            save_error.set(Some(error));
                        }
                        saving.set(false);
                    }
                }
            });
            false
        };
        let a11y_id = use_a11y();
        let edited = editor.read().is_edited();
        let dirty_tab_deps = (
            self.runtime_tab_id.clone(),
            self.relative_path.clone(),
            edited,
        );
        let mut dirty_tabs_for_effect = self.dirty_tabs;
        use_side_effect_with_deps(
            &dirty_tab_deps,
            move |(runtime_tab_id, relative_path, edited)| {
                let mut dirty_tabs = dirty_tabs_for_effect.write();
                if *edited {
                    dirty_tabs.insert(runtime_tab_id.clone(), relative_path.clone());
                } else {
                    dirty_tabs.remove(runtime_tab_id);
                }
            },
        );
        let save_status = if let Some(error) = save_error.read().as_ref() {
            label()
                .font_size(10.)
                .color((248, 113, 113))
                .text(error.clone())
        } else if *saving.read() {
            label().font_size(10.).color(MUTED).text("Saving…")
        } else {
            label()
                .font_size(10.)
                .color(if edited { ACCENT } else { FAINT })
                .text(if edited { "Unsaved changes" } else { "Saved" })
        };
        let editor_body = match &*document.state() {
            FutureState::Pending | FutureState::Loading => {
                rect().expanded().center().child(CircularLoader::new())
            }
            FutureState::Fulfilled(Err(error)) => rect().expanded().center().child(
                label()
                    .font_size(12.)
                    .color((248, 113, 113))
                    .text(error.clone()),
            ),
            FutureState::Fulfilled(Ok(_)) => rect().expanded().background(BACKGROUND).child(
                CodeEditor::new(editor, a11y_id)
                    .font_size(14.)
                    .line_height(1.4)
                    .font_family("JetBrains Mono")
                    .gutter(true)
                    .show_whitespace(false)
                    .on_pre_key_down(on_pre_key_down),
            ),
        };
        let conflict_view = save_conflict.read().clone().map(|conflict| {
            editor_conflict_overlay(
                conflict,
                self.bridge.clone(),
                self.workspace_path.clone(),
                self.relative_path.clone(),
                editor,
                document_for_save,
                saving,
                save_error,
                save_conflict,
            )
        });
        rect()
            .expanded()
            .background(BACKGROUND)
            .vertical()
            .child(
                rect()
                    .height(Size::px(34.))
                    .width(Size::fill())
                    .background(SURFACE)
                    .border(Border::new().width(1.).fill(BORDER))
                    .padding(Gaps::new(10., 8., 10., 8.))
                    .child(
                        rect()
                            .horizontal()
                            .cross_align(Alignment::Center)
                            .spacing(8.)
                            .child(label().font_size(12.).color(TEXT).text(self.title.clone()))
                            .maybe_child(
                                edited
                                    .then(|| label().font_size(10.).color(ACCENT).text("Unsaved")),
                            )
                            .child(save_status),
                    ),
            )
            .child(editor_body)
            .maybe_child(conflict_view)
            .into_element()
    }

    fn render_key(&self) -> DiffKey {
        let key = format!("{}:{}", self.runtime_tab_id, self.reload_generation);
        DiffKey::from(&key)
    }
}

fn is_editor_conflict_error(error: &str) -> bool {
    let error = error.to_ascii_lowercase();
    error.contains("changed on disk") || error.contains("conflict")
}

fn apply_editor_reveal(editor: &mut CodeEditorData, target: &EditorRevealTarget) {
    let line_index = target.line.saturating_sub(1) as usize;
    if line_index >= editor.len_lines() {
        return;
    }
    let line_start = editor.line_to_char(line_index);
    let line_end = if line_index + 1 < editor.len_lines() {
        editor.line_to_char(line_index + 1).saturating_sub(1)
    } else {
        editor.len_chars()
    };
    let start = line_start
        .saturating_add(target.column.saturating_sub(1) as usize)
        .min(line_end);
    let end = start
        .saturating_add(target.match_length as usize)
        .min(line_end);
    let from = editor.char_to_utf16_cu(start);
    let to = editor.char_to_utf16_cu(end);
    *editor.selection_mut() = if from == to {
        TextSelection::new_cursor(from)
    } else {
        TextSelection::new_range((from, to))
    };
}

#[allow(clippy::too_many_arguments)]
fn editor_conflict_overlay(
    conflict: EditorSaveConflict,
    bridge: RuntimeBridge,
    workspace_path: String,
    relative_path: String,
    editor: State<CodeEditorData>,
    document_state: State<Option<FreyaEditorDocument>>,
    saving: State<bool>,
    save_error: State<Option<String>>,
    save_conflict: State<Option<EditorSaveConflict>>,
) -> Element {
    let busy = *saving.read();
    let mut close_from_overlay = save_conflict;
    let mut close_from_cancel = save_conflict;
    let mut saving_for_confirm = saving;
    let mut error_for_confirm = save_error;
    let mut conflict_for_confirm = save_conflict;
    let mut editor_for_confirm = editor;
    let mut document_for_confirm = document_state;
    let confirm_conflict = conflict.clone();
    let confirm = move |event: Event<PointerEventData>| {
        event.stop_propagation();
        if busy {
            return;
        }
        saving_for_confirm.set(true);
        error_for_confirm.set(None);
        let bridge = bridge.clone();
        let workspace_path = workspace_path.clone();
        let relative_path = relative_path.clone();
        let conflict = confirm_conflict.clone();
        spawn(async move {
            let result = bridge
                .request(
                    "workspaceFiles.writeEditor",
                    json!({
                        "workspacePath": workspace_path,
                        "relativePath": relative_path,
                        "currentDisplayContent": conflict.display_content,
                        "originalRawContent": conflict.document.raw_content,
                        "originalDisplayContent": conflict.document.display_content,
                        "expectedContentToken": conflict.document.content_token,
                        "overwriteIfChanged": true,
                        "tabSize": 4,
                    }),
                )
                .await
                .and_then(|value| parse_editor_document(&value));
            match result {
                Ok(document) => {
                    editor_for_confirm.write().mark_as_saved();
                    document_for_confirm.set(Some(document));
                    conflict_for_confirm.set(None);
                }
                Err(error) => error_for_confirm.set(Some(error)),
            }
            saving_for_confirm.set(false);
        });
    };
    rect()
        .position(Position::new_absolute())
        .layer(Layer::Overlay)
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .background(Color::from_af32rgb(0.52, 0, 0, 0))
        .on_press(move |_| {
            if !busy {
                close_from_overlay.set(None);
            }
        })
        .child(
            rect()
                .position(Position::new_absolute())
                .width(Size::percent(100.))
                .height(Size::percent(100.))
                .center()
                .child(
                    rect()
                        .width(Size::px(430.))
                        .background(SURFACE_RAISED)
                        .border(Border::new().width(1.).fill(BORDER))
                        .corner_radius(10.)
                        .padding(Gaps::new_all(20.))
                        .vertical()
                        .spacing(13.)
                        .on_press(|event: Event<PressEventData>| event.stop_propagation())
                        .child(
                            label()
                                .font_size(17.)
                                .color(TEXT)
                                .text("File Changed On Disk"),
                        )
                        .child(
                            label()
                                .font_size(12.)
                                .color(MUTED)
                                .text("Overwrite The External Changes With The Editor Contents?"),
                        )
                        .child(
                            rect()
                                .width(Size::fill())
                                .height(Size::px(30.))
                                .horizontal()
                                .content(Content::Flex)
                                .spacing(8.)
                                .child(rect().width(Size::flex(1.)).child(""))
                                .child(
                                    rect()
                                        .height(Size::fill())
                                        .padding(Gaps::new(10., 0., 10., 0.))
                                        .center()
                                        .corner_radius(7.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Cancel")
                                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(move |event: Event<PointerEventData>| {
                                            event.stop_propagation();
                                            if !busy {
                                                close_from_cancel.set(None);
                                            }
                                        })
                                        .child(label().font_size(11.).color(MUTED).text("Cancel")),
                                )
                                .child(
                                    rect()
                                        .height(Size::fill())
                                        .padding(Gaps::new(12., 0., 12., 0.))
                                        .center()
                                        .background((220, 38, 38))
                                        .corner_radius(7.)
                                        .a11y_role(AccessibilityRole::Button)
                                        .a11y_alt("Overwrite")
                                        .on_pointer_enter(move |_| {
                                            Cursor::set(if busy {
                                                CursorIcon::default()
                                            } else {
                                                CursorIcon::Pointer
                                            })
                                        })
                                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                                        .on_pointer_down(confirm)
                                        .child(if busy {
                                            CircularLoader::new().size(14.).into_element()
                                        } else {
                                            label()
                                                .font_size(11.)
                                                .color(BACKGROUND)
                                                .text("Overwrite")
                                                .into_element()
                                        }),
                                ),
                        ),
                ),
        )
        .into_element()
}

#[allow(clippy::too_many_arguments)]
fn editor_surface(
    bridge: RuntimeBridge,
    workspace_path: String,
    relative_path: String,
    title: String,
    runtime_tab_id: String,
    dirty_tabs: State<HashMap<String, String>>,
    reload_generation: u64,
    reveal_request: Option<EditorRevealRequest>,
) -> Element {
    let component_key = format!("{runtime_tab_id}:{reload_generation}");
    rect()
        .key(component_key)
        .child(FreyaEditorSurface {
            bridge,
            workspace_path,
            relative_path,
            title,
            runtime_tab_id,
            dirty_tabs,
            reload_generation,
            reveal_request,
        })
        .into_element()
}

fn freya_tab_visual(
    title: String,
    tab_kind: String,
    active: bool,
    drop_target: bool,
    close_action: Option<Callback<(), ()>>,
) -> Element {
    let background = if drop_target {
        (57, 68, 86)
    } else if active {
        (42, 42, 42)
    } else {
        (28, 28, 28)
    };
    let (width, icon) = match tab_kind.as_str() {
        "editor" => (180., icons::lucide::file()),
        "gitDiff" => (180., icons::lucide::git_compare()),
        _ => (146., icons::lucide::terminal()),
    };
    rect()
        .width(Size::px(width))
        .height(Size::px(34.))
        .padding(Gaps::new(4., 10., 4., 10.))
        .background(background)
        .corner_radius(6.)
        .color((220, 220, 220))
        .overflow(Overflow::Clip)
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .child(
            SvgViewer::new(icon)
                .width(Size::px(14.))
                .height(Size::px(14.))
                .color(MUTED),
        )
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(12.)
                .max_lines(1)
                .text_overflow(TextOverflow::Ellipsis)
                .text(title),
        )
        .child(rect().width(Size::flex(1.)).child(""))
        .maybe_child(close_action.map(|close_action| {
            rect()
                .width(Size::px(16.))
                .height(Size::px(20.))
                .center()
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    close_action.call(());
                })
                .child(label().font_size(12.).color(MUTED).text("×"))
        }))
        .into_element()
}

fn freya_terminal_key_name(key: &Key) -> Option<String> {
    let name = match key {
        Key::Character(character) => return Some(character.clone()),
        Key::Named(NamedKey::Enter) => "enter",
        Key::Named(NamedKey::Backspace) => "backspace",
        Key::Named(NamedKey::Tab) => "tab",
        Key::Named(NamedKey::Escape) => "escape",
        Key::Named(NamedKey::ArrowUp) => "up",
        Key::Named(NamedKey::ArrowDown) => "down",
        Key::Named(NamedKey::ArrowLeft) => "left",
        Key::Named(NamedKey::ArrowRight) => "right",
        Key::Named(NamedKey::Home) => "home",
        Key::Named(NamedKey::End) => "end",
        Key::Named(NamedKey::Delete) => "delete",
        _ => return None,
    };
    Some(name.to_owned())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TerminalClipboardShortcut {
    Copy,
    Paste,
}

fn terminal_clipboard_shortcut(
    key: &str,
    modifiers: Modifiers,
) -> Option<TerminalClipboardShortcut> {
    let platform_shortcut = modifiers.contains(Modifiers::META);
    let terminal_shortcut =
        modifiers.contains(Modifiers::CONTROL) && modifiers.contains(Modifiers::SHIFT);
    if !platform_shortcut && !terminal_shortcut {
        return None;
    }
    if key.eq_ignore_ascii_case("c") {
        Some(TerminalClipboardShortcut::Copy)
    } else if key.eq_ignore_ascii_case("v") {
        Some(TerminalClipboardShortcut::Paste)
    } else {
        None
    }
}

#[derive(Clone, Copy)]
struct TerminalRowStyle<'a> {
    cursor_shape: &'a str,
    foreground: Color,
    background: Color,
    selection: Color,
    palette: TerminalThemePalette,
    cursor_opacity: f32,
    font_size: f32,
    line_height: f32,
    cell_width: f32,
}

fn terminal_row(
    row: &[TerminalCell],
    row_index: usize,
    cursor: alera_desktop_core::terminal_model::TerminalCursor,
    selection: Option<TerminalSelection>,
    cursor_visible: bool,
    style: TerminalRowStyle<'_>,
) -> Element {
    let cursor_column = (cursor.visible && cursor_visible && cursor.row == row_index)
        .then_some(cursor.column.min(row.len().saturating_sub(1)));
    let row_height = (style.font_size * style.line_height).max(style.font_size);
    let mut paragraph = paragraph()
        .layer(2)
        .height(Size::px(row_height))
        .font_size(style.font_size)
        .max_lines(1)
        .color(style.foreground);
    let mut run_text = String::new();
    let mut run_style = None::<(TerminalCellStyle, bool)>;
    for (column, cell) in row.iter().enumerate() {
        let is_cursor = cursor_column == Some(column);
        let visual_style = (cell.style, is_cursor);
        if run_style.is_some_and(|current| current != visual_style) {
            paragraph = paragraph.span(terminal_span(
                std::mem::take(&mut run_text),
                run_style.expect("terminal run style"),
                style,
            ));
        }
        run_style = Some(visual_style);
        if is_cursor {
            run_text.push(match style.cursor_shape {
                "bar" => '▌',
                "underline" => '▁',
                _ => '█',
            });
        } else if cell.text.is_empty() {
            run_text.push(' ');
        } else {
            run_text.push_str(&cell.text);
        }
    }
    if let Some(run_style) = run_style {
        paragraph = paragraph.span(terminal_span(run_text, run_style, style));
    }
    let overlay = selection.and_then(|selection| {
        terminal_row_selection(selection, row_index, row.len(), style, row_height)
    });
    let backgrounds = terminal_background_runs(row)
        .into_iter()
        .map(|(start, end, background)| {
            rect()
                .layer(0)
                .position(
                    Position::new_absolute()
                        .top(0.)
                        .left(start as f32 * style.cell_width),
                )
                .width(Size::px((end - start) as f32 * style.cell_width))
                .height(Size::px(row_height))
                .background(resolve_terminal_cell_color(
                    background,
                    style.palette,
                    style.background,
                ))
        });
    rect()
        .width(Size::fill())
        .height(Size::px(row_height))
        .children(backgrounds)
        .child(paragraph)
        .maybe_child(overlay)
        .into_element()
}

fn terminal_background_runs(row: &[TerminalCell]) -> Vec<(usize, usize, Rgba)> {
    let default_background = Rgba::rgb(16, 16, 16);
    let mut runs = Vec::new();
    let mut active = None::<(usize, Rgba)>;
    for (column, cell) in row.iter().enumerate() {
        let background = if cell.style.inverse {
            cell.style.foreground
        } else {
            cell.style.background
        };
        let background =
            (background.alpha != 0 && background != default_background).then_some(background);
        match (active, background) {
            (Some((start, current)), Some(next)) if current == next => {
                active = Some((start, current));
            }
            (Some((start, current)), next) => {
                runs.push((start, column, current));
                active = next.map(|color| (column, color));
            }
            (None, Some(next)) => active = Some((column, next)),
            (None, None) => {}
        }
    }
    if let Some((start, background)) = active {
        runs.push((start, row.len(), background));
    }
    runs
}

fn terminal_row_selection(
    selection: TerminalSelection,
    row_index: usize,
    row_len: usize,
    style: TerminalRowStyle<'_>,
    row_height: f32,
) -> Option<Element> {
    if row_index < selection.start_row || row_index > selection.end_row {
        return None;
    }
    let start = if row_index == selection.start_row {
        selection.start_column.min(row_len)
    } else {
        0
    };
    let end = if row_index == selection.end_row {
        selection.end_column.saturating_add(1).min(row_len)
    } else {
        row_len
    };
    (start < end).then(|| {
        rect()
            .layer(1)
            .position(
                Position::new_absolute()
                    .top(0.)
                    .left(start as f32 * style.cell_width),
            )
            .width(Size::px((end - start) as f32 * style.cell_width))
            .height(Size::px(row_height))
            .background(style.selection)
            .into_element()
    })
}

fn terminal_span(
    text: String,
    (cell_style, is_cursor): (TerminalCellStyle, bool),
    row_style: TerminalRowStyle<'_>,
) -> Span<'static> {
    let mut foreground = if cell_style.inverse {
        cell_style.background
    } else {
        cell_style.foreground
    };
    if is_cursor {
        foreground = packed_rgba(row_style.palette.cursor, row_style.cursor_opacity);
    }
    let mut span = Span::new(text).color(resolve_terminal_cell_color(
        foreground,
        row_style.palette,
        row_style.foreground,
    ));
    if cell_style.bold {
        span = span.font_weight(FontWeight::from(700));
    }
    if cell_style.italic {
        span = span.font_slant(FontSlant::Italic);
    }
    if cell_style.underline {
        span = span.text_decoration(TextDecoration::Underline);
    }
    span
}

fn resolve_terminal_cell_color(
    rgba: Rgba,
    palette: TerminalThemePalette,
    fallback: Color,
) -> Color {
    if rgba.alpha == 0 {
        return fallback;
    }
    let packed = (u32::from(rgba.red) << 16) | (u32::from(rgba.green) << 8) | u32::from(rgba.blue);
    let mapped = match packed {
        0x101010 => palette.background,
        0xe5e5e5 => palette.foreground,
        0x000000 => palette.normal[0],
        0xcd0000 => palette.normal[1],
        0x00cd00 => palette.normal[2],
        0xcdcd00 => palette.normal[3],
        0x0000ee => palette.normal[4],
        0xcd00cd => palette.normal[5],
        0x00cdcd => palette.normal[6],
        0x7f7f7f => palette.bright[0],
        0xff0000 => palette.bright[1],
        0x00ff00 => palette.bright[2],
        0xffff00 => palette.bright[3],
        0x5c5cff => palette.bright[4],
        0xff00ff => palette.bright[5],
        0x00ffff => palette.bright[6],
        0xffffff => palette.bright[7],
        _ => packed,
    };
    color_from_rgb24(mapped, f32::from(rgba.alpha) / 255.)
}

fn packed_rgba(value: u32, opacity: f32) -> Rgba {
    Rgba {
        red: ((value >> 16) & 0xff) as u8,
        green: ((value >> 8) & 0xff) as u8,
        blue: (value & 0xff) as u8,
        alpha: (opacity.clamp(0., 1.) * 255.).round() as u8,
    }
}

fn color_from_rgb24(value: u32, opacity: f32) -> Color {
    Color::from_af32rgb(
        opacity.clamp(0., 1.),
        ((value >> 16) & 0xff) as u8,
        ((value >> 8) & 0xff) as u8,
        (value & 0xff) as u8,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use freya_testing::prelude::*;

    #[test]
    fn terminal_backgrounds_merge_ansi_runs_and_respect_inverse_cells() {
        let default = TerminalCell {
            style: TerminalCellStyle {
                background: Rgba::rgb(16, 16, 16),
                ..TerminalCellStyle::default()
            },
            ..TerminalCell::default()
        };
        let blue = TerminalCell {
            style: TerminalCellStyle {
                background: Rgba::rgb(0, 0, 238),
                ..TerminalCellStyle::default()
            },
            ..TerminalCell::default()
        };
        let inverse_red = TerminalCell {
            style: TerminalCellStyle {
                foreground: Rgba::rgb(205, 0, 0),
                background: Rgba::rgb(0, 0, 238),
                inverse: true,
                ..TerminalCellStyle::default()
            },
            ..TerminalCell::default()
        };
        let row = [default.clone(), blue.clone(), blue, inverse_red, default];

        assert_eq!(
            terminal_background_runs(&row),
            vec![(1, 3, Rgba::rgb(0, 0, 238)), (3, 4, Rgba::rgb(205, 0, 0)),]
        );
    }

    #[test]
    fn terminal_clipboard_shortcuts_preserve_plain_control_c_for_the_pty() {
        assert_eq!(
            terminal_clipboard_shortcut("c", Modifiers::META),
            Some(TerminalClipboardShortcut::Copy)
        );
        assert_eq!(
            terminal_clipboard_shortcut("v", Modifiers::CONTROL | Modifiers::SHIFT),
            Some(TerminalClipboardShortcut::Paste)
        );
        assert_eq!(terminal_clipboard_shortcut("c", Modifiers::CONTROL), None);
    }

    #[test]
    fn freya_context_menu_button_invokes_action() {
        fn app() -> impl IntoElement {
            let clicked = use_state(|| 0_u8);
            let clicked_text = clicked.read().to_string();
            rect()
                .expanded()
                .child(ContextMenuViewer::new())
                .child(
                    Button::new()
                        .on_press(move |_| {
                            let mut clicked = clicked;
                            ContextMenu::open(
                                Menu::new().child(
                                    MenuButton::new()
                                        .on_press(move |_| clicked.set(1))
                                        .child("Close"),
                                ),
                            );
                        })
                        .child("Open"),
                )
                .child(label().text(clicked_text))
        }

        let mut test = launch_test(app);
        test.click_cursor((10., 10.));
        test.click_cursor((10., 10.));
        assert!(
            test.find(|_, element| {
                Label::try_downcast(element).filter(|label| label.text.as_ref() == "1")
            })
            .is_some()
        );
    }

    #[test]
    fn center_drop_reorders_tabs_inside_a_panel() {
        let mut workspace = FreyaWorkspace::new();

        assert!(workspace.on_drop(
            2,
            DropTarget::Tab {
                panel_id: 0,
                position: 0,
            },
        ));

        let Some(DockNode::Split { children, .. }) = workspace.tree.as_ref() else {
            panic!("expected the initial split");
        };
        let Some(DockNode::Panel(panel)) = children.first() else {
            panic!("expected the first panel");
        };
        assert_eq!(panel.tabs, [2, 1]);
        assert_eq!(panel.active_tab_id, Some(2));
    }

    #[test]
    fn directional_drop_prunes_the_empty_source_panel() {
        let mut workspace = FreyaWorkspace::new();

        assert!(workspace.on_drop(
            3,
            DropTarget::Split {
                panel_id: 0,
                side: Side::Right,
            },
        ));

        let Some(DockNode::Split { children, .. }) = workspace.tree.as_ref() else {
            panic!("expected a split tree");
        };
        assert_eq!(children.len(), 2);
        assert!(
            workspace
                .tree
                .as_ref()
                .is_some_and(|tree| tree.find_tab(&3).is_some())
        );
        assert!(
            workspace
                .tree
                .as_ref()
                .is_some_and(|tree| tree.find_tab(&1).is_some())
        );
        assert!(
            workspace
                .tree
                .as_ref()
                .is_some_and(|tree| tree.find_tab(&2).is_some())
        );
    }

    #[test]
    fn moving_a_tab_then_splitting_keeps_each_tab_once() {
        let mut workspace = FreyaWorkspace::new();

        assert!(workspace.on_drop(2, DropTarget::Center(1),));
        assert!(workspace.on_drop(
            1,
            DropTarget::Split {
                panel_id: 1,
                side: Side::Left,
            },
        ));

        let mut tabs = Vec::new();
        fn collect(node: &DockNode<TabId, PanelId>, tabs: &mut Vec<TabId>) {
            match node {
                DockNode::Panel(panel) => tabs.extend(panel.tabs.iter().copied()),
                DockNode::Split { children, .. } => {
                    for child in children {
                        collect(child, tabs);
                    }
                }
            }
        }
        collect(workspace.tree.as_ref().expect("layout"), &mut tabs);
        tabs.sort_unstable();
        assert_eq!(tabs, [1, 2, 3]);
    }

    #[test]
    fn close_active_uses_the_panel_selected_by_the_user() {
        let mut workspace = FreyaWorkspace::new();

        assert!(workspace.set_active(1, 3));
        workspace.close_active();

        let Some(DockNode::Panel(panel)) = workspace.tree.as_ref() else {
            panic!("expected the remaining panel after closing the split");
        };
        assert_eq!(panel.panel_id, 0);
        assert_eq!(panel.tabs, [1, 2]);
        assert_eq!(workspace.layout.active_group_id, "panel-0");
        assert!(!workspace.tab_titles.contains_key(&3));
    }

    #[test]
    fn context_actions_rename_and_close_the_requested_tab() {
        let mut workspace = FreyaWorkspace::new();

        assert!(workspace.rename_tab(2, "Build Output"));
        assert_eq!(workspace.title(2), "Build Output");
        assert!(!workspace.rename_tab(2, "   "));
        assert!(workspace.close_tab(2));
        assert!(!workspace.close_tab(2));
        assert!(!workspace.tab_titles.contains_key(&2));
        assert!(
            workspace
                .tree
                .as_ref()
                .is_some_and(|tree| tree.find_tab(&2).is_none())
        );
    }

    #[test]
    fn opening_editor_tab_tracks_path_and_reuses_existing_tab() {
        let mut workspace = FreyaWorkspace::new();

        let (tab_id, runtime_id) = workspace
            .open_editor_tab("src/main.rs")
            .expect("a non-empty editor path should open");
        assert_eq!(workspace.tab_kind(tab_id), "editor");
        assert_eq!(workspace.tab_path(tab_id).as_deref(), Some("src/main.rs"));
        assert_eq!(workspace.title(tab_id), "main.rs");
        assert_eq!(workspace.runtime_tab_id(tab_id), runtime_id);

        let (same_tab_id, same_runtime_id) = workspace
            .open_editor_tab("/src/main.rs/")
            .expect("the normalized path should reuse the tab");
        assert_eq!(same_tab_id, tab_id);
        assert_eq!(same_runtime_id, runtime_id);
        assert_eq!(
            workspace
                .layout
                .groups
                .values()
                .map(|group| group.tab_ids.len())
                .sum::<usize>(),
            4
        );
        assert!(workspace.open_editor_tab("/").is_none());
    }

    #[test]
    fn default_file_open_uses_flutter_markdown_tab_kind() {
        let mut workspace = FreyaWorkspace::new();

        let (preview_tab_id, _) = workspace
            .open_file_tab("README.md")
            .expect("markdown preview tab");
        let (editor_tab_id, _) = workspace
            .open_editor_tab("README.md")
            .expect("markdown source editor tab");

        assert_eq!(workspace.tab_kind(preview_tab_id), "markdownViewer");
        assert_eq!(workspace.tab_kind(editor_tab_id), "editor");
        assert_ne!(preview_tab_id, editor_tab_id);
        assert_eq!(
            workspace.tab_payload(preview_tab_id)["filePath"],
            "README.md"
        );
    }

    #[test]
    fn search_file_open_forces_flutter_editor_kind() {
        let mut workspace = FreyaWorkspace::new();
        let request = FileOpenRequest::editor("README.md");

        let (tab_id, _) = workspace
            .open_file_request(&request)
            .expect("search result editor tab");

        assert_eq!(workspace.tab_kind(tab_id), "editor");
    }

    #[test]
    fn search_reveal_selects_the_unicode_match_on_the_requested_line() {
        let mut editor = CodeEditorData::new(Rope::from_str("first\ná package value\nthird"), None);

        apply_editor_reveal(
            &mut editor,
            &EditorRevealTarget {
                line: 2,
                column: 3,
                match_length: 7,
            },
        );

        let TextSelection::Range { from, to } = editor.selection() else {
            panic!("expected selected search match");
        };
        assert_eq!((*from, *to), (8, 15));
    }

    #[test]
    fn dirty_close_guard_only_matches_unsaved_editor_tabs() {
        let mut workspace = FreyaWorkspace::new();
        let (editor_tab_id, editor_runtime_id) = workspace
            .open_editor_tab("src/main.rs")
            .expect("editor tab");
        let terminal_runtime_id = workspace.runtime_tab_id(1);
        let mut dirty_tabs = HashMap::from([(terminal_runtime_id, "terminal".to_string())]);

        assert!(!tabs_include_unsaved_editor(
            &[1, editor_tab_id],
            &workspace,
            &dirty_tabs,
        ));

        dirty_tabs.insert(editor_runtime_id, "src/main.rs".to_string());
        assert!(tabs_include_unsaved_editor(
            &[1, editor_tab_id],
            &workspace,
            &dirty_tabs,
        ));
        assert!(!tabs_include_unsaved_editor(&[1], &workspace, &dirty_tabs,));
    }

    #[test]
    fn path_moves_retarget_open_editor_and_working_tree_diff_tabs() {
        let mut workspace = FreyaWorkspace::new();
        let (editor_tab_id, editor_runtime_id) = workspace
            .open_editor_tab("src/main.rs")
            .expect("editor tab");
        let request = GitDiffOpenRequest::working_tree(
            "/workspace",
            Some("src/main.rs".to_string()),
            Some("unstaged".to_string()),
        );
        let (diff_tab_id, diff_runtime_id, _) = workspace.open_git_diff_tab(&request);

        let updates = workspace.rewrite_file_backed_paths("src", "lib");

        assert_eq!(
            workspace.tab_path(editor_tab_id).as_deref(),
            Some("lib/main.rs")
        );
        assert_eq!(
            workspace
                .tab_payload(editor_tab_id)
                .get("filePath")
                .and_then(Value::as_str),
            Some("lib/main.rs")
        );
        assert_eq!(
            workspace
                .tab_payload(diff_tab_id)
                .get("filePath")
                .and_then(Value::as_str),
            Some("lib/main.rs")
        );
        assert_eq!(
            updates
                .iter()
                .map(|update| update.runtime_tab_id.as_str())
                .collect::<HashSet<_>>(),
            HashSet::from([editor_runtime_id.as_str(), diff_runtime_id.as_str()])
        );

        workspace.rewrite_file_backed_paths("lib/main.rs", "lib/app.rs");
        assert_eq!(workspace.title(editor_tab_id), "app.rs");
        assert_eq!(workspace.title(diff_tab_id), "app.rs Unstaged");
    }

    #[test]
    fn restores_editor_path_from_flutter_file_path_payload() {
        let snapshot = WorkbenchSnapshot {
            tabs: vec![alera_desktop_core::WorkspaceTab {
                id: "tab-1".to_string(),
                workspace_id: "workspace-1".to_string(),
                title: "package.json".to_string(),
                kind: "editor".to_string(),
                payload: json!({"filePath": "package.json"}),
            }],
            selected_workspace_id: Some("workspace-1".to_string()),
            ..WorkbenchSnapshot::default()
        };
        let workspace = FreyaWorkspace::from_snapshot(&snapshot, "workspace-1");

        assert_eq!(workspace.tab_kind(1), "editor");
        assert_eq!(workspace.tab_path(1).as_deref(), Some("package.json"));
    }

    #[test]
    fn opening_git_diff_reuses_the_same_persisted_request() {
        let mut workspace = FreyaWorkspace::new();
        let request = GitDiffOpenRequest::working_tree(
            "/workspace",
            Some("src/main.rs".to_string()),
            Some("unstaged".to_string()),
        );

        let (tab_id, runtime_id, created) = workspace.open_git_diff_tab(&request);
        assert!(created);
        assert_eq!(workspace.tab_kind(tab_id), "gitDiff");
        assert_eq!(workspace.title(tab_id), "main.rs Unstaged");
        assert_eq!(
            workspace
                .tab_payload(tab_id)
                .get("filePath")
                .and_then(Value::as_str),
            Some("src/main.rs")
        );

        let (same_tab_id, same_runtime_id, created_again) = workspace.open_git_diff_tab(&request);
        assert!(!created_again);
        assert_eq!(same_tab_id, tab_id);
        assert_eq!(same_runtime_id, runtime_id);
    }

    #[test]
    fn scoped_git_diff_persists_workspace_paths_and_requests_source_paths() {
        let request = GitDiffOpenRequest::working_tree_in_scope(
            "/workspace",
            "/workspace/apps/web",
            "apps/web",
            Some("src/main.rs".to_string()),
            Some("unstaged".to_string()),
        );
        let payload = request.payload();

        assert_eq!(request.workspace_path, "/workspace");
        assert_eq!(request.git_path, "/workspace/apps/web");
        assert_eq!(request.source_relative_path.as_deref(), Some("src/main.rs"));
        assert_eq!(
            payload.get("filePath").and_then(Value::as_str),
            Some("apps/web/src/main.rs")
        );
        assert_eq!(
            payload.get("gitDiffRoot").and_then(Value::as_str),
            Some("apps/web")
        );

        let restored = GitDiffOpenRequest::from_payload("/workspace".to_string(), &payload);
        assert_eq!(restored, request);
    }

    #[test]
    fn parses_runtime_git_diff_payload() {
        let value = json!({
            "files": [{
                "path": "src/main.rs",
                "oldPath": null,
                "area": "unstaged",
                "status": "Modified",
                "lines": [{"text": "+hello", "kind": "addition"}],
                "added": 1,
                "removed": 0,
                "isBinary": false,
                "isLarge": false,
                "isGitlink": false,
                "truncated": false,
                "linePreviewTruncated": false
            }],
            "truncated": false
        });

        let result = parse_git_diff(&value).expect("valid diff payload");
        assert_eq!(result.files.len(), 1);
        assert_eq!(result.files[0].path, "src/main.rs");
        assert_eq!(result.files[0].lines[0].kind, "addition");
    }

    #[test]
    fn editor_conflict_errors_are_separated_from_normal_save_failures() {
        assert!(super::is_editor_conflict_error("File changed on disk"));
        assert!(super::is_editor_conflict_error("Workspace file conflict"));
        assert!(!super::is_editor_conflict_error("Permission denied"));
    }

    #[test]
    fn split_ratio_is_read_from_the_framework_neutral_layout() {
        let mut workspace = FreyaWorkspace::new();
        if let WorkbenchLayoutNode::Split { ratio, .. } = &mut workspace.layout.root {
            *ratio = 0.72;
        }
        assert!((workspace.ratio_for_panels(0, 1) - 0.72).abs() < f32::EPSILON);
    }
}
