use std::cmp::Ordering;
use std::collections::{BTreeSet, HashSet};

use alera_desktop_core::{RuntimeBridge, WorkbenchSnapshot, model::WorkspaceRelation};
use freya::icons;
use freya::prelude::*;
use serde_json::{Value, json};

use crate::{ACCENT, BORDER, MUTED, SURFACE, SURFACE_RAISED, TEXT};

const DIALOG_WIDTH: f32 = 460.;
const LIST_MAX_HEIGHT: f32 = 260.;
const ROW_HEIGHT: f32 = 36.;
const PARENT_DROPDOWN_OPEN: &str = "__alera_parent_dropdown_open__";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum SidebarActionKind {
    RenameProject,
    RemoveProject,
    RenameWorkspace,
    ManageTags,
    SetParent,
    SleepWorkspace,
    RemoveWorkspace,
}

#[derive(Clone, Debug)]
pub(crate) struct SidebarActionDialog {
    pub(crate) kind: SidebarActionKind,
    pub(crate) target_id: String,
    pub(crate) display_name: String,
    pub(crate) branch: String,
    pub(crate) delete_branch: bool,
    pub(crate) current_parent_id: Option<String>,
    pub(crate) tag_ids: HashSet<String>,
}

impl SidebarActionDialog {
    pub(crate) fn project(kind: SidebarActionKind, id: String, name: String) -> Self {
        Self {
            kind,
            target_id: id,
            display_name: name,
            branch: String::new(),
            delete_branch: false,
            current_parent_id: None,
            tag_ids: HashSet::new(),
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn overlay(
    dialog: SidebarActionDialog,
    mut open: State<Option<SidebarActionDialog>>,
    value: State<String>,
    selected_tags: State<HashSet<String>>,
    selected_parent: State<Option<String>>,
    busy: State<bool>,
    error: State<Option<String>>,
    bridge: RuntimeBridge,
    snapshot: Option<WorkbenchSnapshot>,
    snapshot_revision: State<u64>,
    selected_workspace: State<String>,
) -> Element {
    let (title, message, confirm, destructive) = presentation(&dialog);
    let parent_dropdown_is_open = dialog.kind == SidebarActionKind::SetParent
        && selected_tags.read().contains(PARENT_DROPDOWN_OPEN);
    let mut dropdown_for_body = selected_tags;
    let is_rename = matches!(
        dialog.kind,
        SidebarActionKind::RenameProject | SidebarActionKind::RenameWorkspace
    );
    let is_graph_dialog = matches!(
        dialog.kind,
        SidebarActionKind::ManageTags | SidebarActionKind::SetParent
    );
    let mut body = rect()
        .width(Size::px(
            if matches!(
                dialog.kind,
                SidebarActionKind::ManageTags | SidebarActionKind::SetParent
            ) {
                DIALOG_WIDTH
            } else {
                420.
            },
        ))
        .vertical()
        .content(Content::fit())
        .spacing(if is_graph_dialog { 16. } else { 12. })
        .padding(Gaps::new_all(20.))
        .background(SURFACE_RAISED)
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(10.)
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            if parent_dropdown_is_open {
                let mut next = dropdown_for_body.read().clone();
                next.remove(PARENT_DROPDOWN_OPEN);
                dropdown_for_body.set(next);
            }
        })
        .child(dialog_title(dialog.kind, title));
    if !message.is_empty() {
        body = body.child(label().font_size(12.).color(MUTED).text(message));
    }
    if is_rename {
        body = body.child(
            Input::new(value)
                .width(Size::fill())
                .placeholder("Name")
                .theme_colors(
                    InputColorsThemePartial::new()
                        .background((24, 24, 24))
                        .focus_background((24, 24, 24))
                        .border_fill(BORDER)
                        .focus_border_fill((96, 96, 96))
                        .color(TEXT)
                        .placeholder_color(MUTED),
                ),
        );
    }
    if dialog.kind == SidebarActionKind::ManageTags {
        body = body.child(tag_selector(
            snapshot.as_ref(),
            value,
            selected_tags,
            selected_tags.read().clone(),
            selected_parent,
            busy,
            error,
            bridge.clone(),
            snapshot_revision,
        ));
    }
    if dialog.kind == SidebarActionKind::SetParent {
        body = body.child(parent_selector(
            snapshot.as_ref(),
            dialog.target_id.as_str(),
            value,
            selected_parent,
            selected_parent.read().clone(),
            selected_tags,
        ));
    }
    if let Some(message) = error.read().clone() {
        body = body.child(label().font_size(11.).color((248, 113, 113)).text(message));
    }

    let action_busy = busy();
    let mut close_for_cancel = open;
    let mut error_for_cancel = error;
    let submit_dialog = dialog.clone();
    let submit_bridge = bridge.clone();
    let submit_value = value;
    let submit_tags = selected_tags;
    let submit_parent = selected_parent;
    let open_for_submit = open;
    let mut busy_for_submit = busy;
    let mut error_for_submit = error;
    let submit = move |_| {
        if busy_for_submit() {
            return;
        }
        let name = submit_value.read().trim().to_string();
        if matches!(
            submit_dialog.kind,
            SidebarActionKind::RenameProject | SidebarActionKind::RenameWorkspace
        ) && name.is_empty()
        {
            error_for_submit.set(Some("Name Is Required".to_string()));
            return;
        }
        busy_for_submit.set(true);
        error_for_submit.set(None);
        let bridge = submit_bridge.clone();
        let dialog = submit_dialog.clone();
        let tag_ids = submit_tags.read().iter().cloned().collect::<Vec<_>>();
        let next_parent = submit_parent.read().clone();
        let mut open = open_for_submit;
        let mut busy = busy_for_submit;
        let mut error = error_for_submit;
        let mut revision = snapshot_revision;
        let mut selected_workspace = selected_workspace;
        spawn(async move {
            let result = submit_action(&bridge, &dialog, name, tag_ids, next_parent).await;
            busy.set(false);
            match result {
                Ok(()) => {
                    if matches!(
                        dialog.kind,
                        SidebarActionKind::SleepWorkspace | SidebarActionKind::RemoveWorkspace
                    ) && selected_workspace.peek().as_str() == dialog.target_id.as_str()
                    {
                        selected_workspace.set(String::new());
                    }
                    revision.set(revision.peek().saturating_add(1));
                    open.set(None);
                }
                Err(message) => error.set(Some(message)),
            }
        });
    };
    body = body.child(
        rect()
            .width(Size::fill())
            .margin(Gaps::new(if is_graph_dialog { 4. } else { 0. }, 0., 0., 0.))
            .horizontal()
            .content(Content::Flex)
            .main_align(Alignment::End)
            .spacing(8.)
            .child(
                Button::new()
                    .compact()
                    .flat()
                    .on_press(move |_| {
                        if !action_busy {
                            error_for_cancel.set(None);
                            close_for_cancel.set(None);
                        }
                    })
                    .child("Cancel"),
            )
            .child(
                Button::new()
                    .compact()
                    .style_variant(ButtonStyleVariant::Filled)
                    .theme_colors(
                        ButtonColorsThemePartial::new()
                            .background(if destructive {
                                (185, 28, 28)
                            } else {
                                (224, 224, 224)
                            })
                            .hover_background(if destructive {
                                (220, 38, 38)
                            } else {
                                (245, 245, 245)
                            })
                            .border_fill(BORDER)
                            .focus_border_fill(BORDER)
                            .color(if destructive { TEXT } else { (16, 16, 16) }),
                    )
                    .on_press(submit)
                    .child(if action_busy { "Working" } else { confirm }),
            ),
    );

    let armed_tag = if dialog.kind == SidebarActionKind::ManageTags {
        selected_parent.read().clone().and_then(|id| {
            snapshot.as_ref().and_then(|snapshot| {
                snapshot
                    .tags
                    .iter()
                    .find(|tag| tag.id == id)
                    .map(|tag| (tag.id.clone(), tag.name.clone()))
            })
        })
    } else {
        None
    };
    let tag_delete_is_armed = armed_tag.is_some();
    let mut delete_armed_for_escape = selected_parent;
    let mut dropdown_for_escape = selected_tags;
    let mut open_for_escape = open;
    let delete_confirmation = armed_tag.map(|(tag_id, tag_name)| {
        delete_tag_confirmation(
            tag_id,
            tag_name,
            selected_tags,
            selected_parent,
            busy,
            error,
            bridge,
            snapshot_revision,
        )
    });

    rect()
        .position(Position::new_absolute())
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .layer(Layer::Overlay)
        .center()
        .background((0, 0, 0, 150))
        .on_key_down(move |event: Event<KeyboardEventData>| {
            if matches!(event.key, Key::Named(NamedKey::Escape)) && !action_busy {
                event.stop_propagation();
                if parent_dropdown_is_open {
                    let mut next = dropdown_for_escape.read().clone();
                    next.remove(PARENT_DROPDOWN_OPEN);
                    dropdown_for_escape.set(next);
                } else if tag_delete_is_armed {
                    delete_armed_for_escape.set(None);
                } else {
                    open_for_escape.set(None);
                }
            }
        })
        .on_pointer_down(move |_| {
            if !action_busy {
                open.set(None);
            }
        })
        .child(body)
        .maybe_child(delete_confirmation)
        .into()
}

fn dialog_title(kind: SidebarActionKind, title: &'static str) -> Element {
    let icon = match kind {
        SidebarActionKind::ManageTags => Some(icons::lucide::tag()),
        SidebarActionKind::SetParent => Some(icons::lucide::link()),
        _ => None,
    };
    rect()
        .width(Size::fill())
        .height(Size::px(28.))
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(8.)
        .maybe_child(icon.map(|icon| {
            SvgViewer::new(icon)
                .width(Size::px(24.))
                .height(Size::px(24.))
                .color(ACCENT)
        }))
        .child(
            label()
                .font_size(16.)
                .font_weight(FontWeight::BOLD)
                .color(TEXT)
                .text(title),
        )
        .into_element()
}

fn presentation(dialog: &SidebarActionDialog) -> (&'static str, String, &'static str, bool) {
    match dialog.kind {
        SidebarActionKind::RenameProject => ("Rename Project", String::new(), "Rename", false),
        SidebarActionKind::RemoveProject => (
            "Remove Project?",
            "This Unregisters The Project And Deletes Its Workspace Metadata. Repository Files On Disk Are Not Deleted.".to_string(),
            "Remove",
            true,
        ),
        SidebarActionKind::RenameWorkspace => ("Rename Workspace", String::new(), "Rename", false),
        SidebarActionKind::ManageTags => ("Manage Tags", String::new(), "Save", false),
        SidebarActionKind::SetParent => ("Set Parent Workspace", String::new(), "Save", false),
        SidebarActionKind::SleepWorkspace => (
            "Sleep Workspace?",
            format!("This Closes All Tabs And Terminal Sessions For \"{}\". The Workspace, Branch, And Files Will Be Preserved.", dialog.display_name),
            "Sleep",
            true,
        ),
        SidebarActionKind::RemoveWorkspace => (
            "Remove Workspace?",
            if dialog.delete_branch && !dialog.branch.is_empty() {
                format!("This Removes The Worktree For \"{}\" And Deletes Branch \"{}\".", dialog.display_name, dialog.branch)
            } else {
                format!("This Removes The Worktree For \"{}\".", dialog.display_name)
            },
            "Remove",
            true,
        ),
    }
}

#[allow(clippy::too_many_arguments)]
fn tag_selector(
    snapshot: Option<&WorkbenchSnapshot>,
    query: State<String>,
    selected: State<HashSet<String>>,
    selected_ids: HashSet<String>,
    delete_armed: State<Option<String>>,
    busy: State<bool>,
    error: State<Option<String>>,
    bridge: RuntimeBridge,
    snapshot_revision: State<u64>,
) -> Element {
    let mut tags = snapshot
        .into_iter()
        .flat_map(|snapshot| &snapshot.tags)
        .collect::<Vec<_>>();
    tags.sort_by(|left, right| compare_names(&left.name, &right.name));

    let mut list = rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(4.);
    if tags.is_empty() {
        list = list.child(
            rect()
                .height(Size::px(36.))
                .cross_align(Alignment::Center)
                .child(label().font_size(12.).color(MUTED).text("No Tags Created")),
        );
    }
    for tag in &tags {
        let id = tag.id.clone();
        let checked = selected_ids.contains(&id);
        let mut selected_for_press = selected;
        let mut delete_for_press = delete_armed;
        let delete_id = id.clone();
        list = list.child(
            rect()
                .width(Size::fill())
                .height(Size::px(ROW_HEIGHT))
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(8.)
                .padding(Gaps::new(0., 4., 0., 4.))
                .corner_radius(6.)
                .background(if checked { SURFACE } else { SURFACE_RAISED })
                .child(
                    rect()
                        .height(Size::fill())
                        .width(Size::flex(1.))
                        .horizontal()
                        .cross_align(Alignment::Center)
                        .spacing(8.)
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            let mut next = selected_for_press.read().clone();
                            if !next.remove(&id) {
                                next.insert(id.clone());
                            }
                            selected_for_press.set(next);
                        })
                        .child(checkbox(checked))
                        .child(
                            label()
                                .font_size(12.)
                                .color(TEXT)
                                .text(format!("#{}", tag.name)),
                        ),
                )
                .child(
                    rect()
                        .width(Size::px(28.))
                        .height(Size::px(28.))
                        .center()
                        .corner_radius(6.)
                        .a11y_role(AccessibilityRole::Button)
                        .a11y_alt(format!("Delete Tag #{}", tag.name))
                        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                        .on_pointer_down(move |event: Event<PointerEventData>| {
                            event.stop_propagation();
                            delete_for_press.set(Some(delete_id.clone()));
                        })
                        .child(
                            SvgViewer::new(icons::lucide::trash_2())
                                .width(Size::px(16.))
                                .height(Size::px(16.))
                                .color(MUTED),
                        ),
                ),
        );
    }

    let list_height = ((tags.len().max(1) as f32 * ROW_HEIGHT) + 4.).min(LIST_MAX_HEIGHT);
    let all_tags = snapshot
        .into_iter()
        .flat_map(|snapshot| &snapshot.tags)
        .map(|tag| tag.name.clone())
        .collect::<Vec<_>>();
    let query_for_create = query;
    let selected_for_create = selected;
    let mut busy_for_create = busy;
    let mut error_for_create = error;
    let create_bridge = bridge;
    let revision_for_create = snapshot_revision;
    let create = move |_| {
        if busy_for_create() {
            return;
        }
        let name = query_for_create.read().trim().to_string();
        if name.is_empty() {
            error_for_create.set(Some("Tag Name Is Required".to_string()));
            return;
        }
        if all_tags.iter().any(|tag| tag.eq_ignore_ascii_case(&name)) {
            error_for_create.set(Some("Tag Already Exists".to_string()));
            return;
        }
        busy_for_create.set(true);
        error_for_create.set(None);
        let bridge = create_bridge.clone();
        let mut query = query_for_create;
        let mut selected = selected_for_create;
        let mut busy = busy_for_create;
        let mut error = error_for_create;
        let mut revision = revision_for_create;
        spawn(async move {
            match bridge
                .request("workspaceTag.create", json!({"name": name}))
                .await
            {
                Ok(value) => {
                    if let Some(id) = value.get("id").and_then(Value::as_str) {
                        let mut next = selected.read().clone();
                        next.insert(id.to_string());
                        selected.set(next);
                    }
                    query.set(String::new());
                    revision.set(revision.peek().saturating_add(1));
                    busy.set(false);
                }
                Err(message) => {
                    busy.set(false);
                    error.set(Some(message));
                }
            }
        });
    };

    rect()
        .width(Size::fill())
        .vertical()
        .content(Content::fit())
        .spacing(12.)
        .child(
            rect().height(Size::px(list_height)).child(
                crate::alera_scroll_view::AleraScrollView::new()
                    .show_scrollbar(tags.len() as f32 * ROW_HEIGHT > list_height)
                    .child(list),
            ),
        )
        .child(
            rect()
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Start)
                .spacing(8.)
                .child(
                    Input::new(query)
                        .width(Size::flex(1.))
                        .placeholder("New Tag")
                        .filled()
                        .theme_layout(
                            InputLayoutThemePartial::new()
                                .corner_radius(CornerRadius::new_all(6.))
                                .inner_margin(Gaps::new(16., 12., 16., 12.)),
                        )
                        .theme_colors(input_colors()),
                )
                .child(
                    Button::new()
                        .width(Size::px(100.))
                        .height(Size::px(32.))
                        .margin(Gaps::new(8., 0., 0., 0.))
                        .compact()
                        .style_variant(ButtonStyleVariant::Filled)
                        .on_press(create)
                        .child(if busy() { "Creating" } else { "Create Tag" }),
                ),
        )
        .into_element()
}

fn parent_selector(
    snapshot: Option<&WorkbenchSnapshot>,
    target_id: &str,
    query: State<String>,
    selected: State<Option<String>>,
    selected_id: Option<String>,
    dropdown_state: State<HashSet<String>>,
) -> Element {
    let normalized_query = query.read().trim().to_lowercase();
    let descendants = snapshot
        .map(|snapshot| workspace_descendant_ids(target_id, &snapshot.relations))
        .unwrap_or_default();
    let preferred_project_id = snapshot.and_then(|snapshot| {
        snapshot.projects.iter().find_map(|project| {
            project
                .workspaces
                .iter()
                .any(|workspace| workspace.id == target_id)
                .then_some(project.id.as_str())
        })
    });
    let mut options = snapshot
        .into_iter()
        .flat_map(|snapshot| &snapshot.projects)
        .flat_map(|project| {
            project
                .workspaces
                .iter()
                .map(move |workspace| (project, workspace))
        })
        .filter(|(_, workspace)| workspace.id != target_id)
        .collect::<Vec<_>>();
    options.sort_by(|(left_project, left), (right_project, right)| {
        compare_parent_options(
            preferred_project_id,
            left_project,
            left,
            right_project,
            right,
        )
    });
    let selected_label = selected_id
        .as_deref()
        .and_then(|selected_id| {
            options
                .iter()
                .find(|(_, workspace)| workspace.id == selected_id)
                .map(|(project, workspace)| workspace_parent_label(project, workspace))
        })
        .unwrap_or_else(|| "No Parent".to_string());
    let dropdown_open = dropdown_state.read().contains(PARENT_DROPDOWN_OPEN);

    let mut list = rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(4.);
    let mut clear = selected;
    let mut query_for_clear = query;
    let mut dropdown_for_clear = dropdown_state;
    let mut visible_rows = 0_usize;
    if filter_matches("No Parent", &normalized_query) {
        visible_rows += 1;
        list = list.child(parent_option(
            "No Parent".to_string(),
            selected_id.is_none(),
            false,
            move || {
                clear.set(None);
                query_for_clear.set(String::new());
                let mut next = dropdown_for_clear.read().clone();
                next.remove(PARENT_DROPDOWN_OPEN);
                dropdown_for_clear.set(next);
            },
        ));
    }
    for (project, workspace) in options {
        let id = workspace.id.clone();
        let checked = selected_id.as_deref() == Some(id.as_str());
        let mut selected_for_press = selected;
        let mut query_for_press = query;
        let mut dropdown_for_press = dropdown_state;
        let text = workspace_parent_label(project, workspace);
        if !filter_matches(&text, &normalized_query) {
            continue;
        }
        visible_rows += 1;
        let disabled = descendants.contains(&id);
        list = list.child(parent_option(text, checked, disabled, move || {
            selected_for_press.set(Some(id.clone()));
            query_for_press.set(String::new());
            let mut next = dropdown_for_press.read().clone();
            next.remove(PARENT_DROPDOWN_OPEN);
            dropdown_for_press.set(next);
        }));
    }
    if visible_rows == 0 {
        list = list.child(
            rect()
                .height(Size::px(36.))
                .padding(Gaps::new(0., 8., 0., 8.))
                .cross_align(Alignment::Center)
                .child(
                    label()
                        .font_size(12.)
                        .color(MUTED)
                        .text("No Matching Workspaces"),
                ),
        );
    }
    let list_height = ((visible_rows.max(1) as f32 * ROW_HEIGHT) + 8.).min(230.);

    let mut dropdown_for_trigger = dropdown_state;
    let dropdown = dropdown_open.then(|| {
        rect()
            .width(Size::fill())
            .vertical()
            .content(Content::fit())
            .spacing(6.)
            .padding(Gaps::new_all(4.))
            .background(SURFACE_RAISED)
            .border(Border::new().width(1.).fill(BORDER))
            .corner_radius(6.)
            .on_pointer_down(|event: Event<PointerEventData>| event.stop_propagation())
            .child(
                Input::new(query)
                    .width(Size::fill())
                    .placeholder("Search Workspaces")
                    .compact()
                    .filled()
                    .leading(
                        SvgViewer::new(icons::lucide::search())
                            .width(Size::px(14.))
                            .height(Size::px(14.))
                            .color(MUTED),
                    )
                    .theme_colors(input_colors()),
            )
            .child(
                rect()
                    .width(Size::fill())
                    .height(Size::px(list_height))
                    .background(SURFACE)
                    .corner_radius(6.)
                    .child(
                        crate::alera_scroll_view::AleraScrollView::new()
                            .show_scrollbar(visible_rows as f32 * ROW_HEIGHT > list_height)
                            .child(list),
                    ),
            )
    });

    rect()
        .width(Size::fill())
        .vertical()
        .content(Content::fit())
        .spacing(6.)
        .child(
            label()
                .font_size(10.)
                .font_weight(FontWeight::MEDIUM)
                .color(MUTED)
                .text("Parent Workspace"),
        )
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(34.))
                .horizontal()
                .cross_align(Alignment::Center)
                .padding(Gaps::new(0., 10., 0., 10.))
                .background(SURFACE)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(6.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Parent Workspace")
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    let mut next = dropdown_for_trigger.read().clone();
                    if !next.remove(PARENT_DROPDOWN_OPEN) {
                        next.insert(PARENT_DROPDOWN_OPEN.to_string());
                    }
                    dropdown_for_trigger.set(next);
                })
                .child(
                    label()
                        .width(Size::flex(1.))
                        .font_size(12.)
                        .color(TEXT)
                        .max_lines(1)
                        .text(selected_label),
                )
                .child(
                    SvgViewer::new(if dropdown_open {
                        icons::lucide::chevron_up()
                    } else {
                        icons::lucide::chevron_down()
                    })
                    .width(Size::px(14.))
                    .height(Size::px(14.))
                    .color(MUTED),
                ),
        )
        .maybe_child(dropdown)
        .into_element()
}

fn checkbox(checked: bool) -> Element {
    rect()
        .width(Size::px(16.))
        .height(Size::px(16.))
        .center()
        .corner_radius(3.)
        .background(if checked { ACCENT } else { SURFACE_RAISED })
        .border(
            Border::new()
                .width(1.)
                .fill(if checked { ACCENT } else { BORDER }),
        )
        .maybe_child(checked.then(|| {
            SvgViewer::new(icons::lucide::check())
                .width(Size::px(12.))
                .height(Size::px(12.))
                .color(SURFACE)
        }))
        .into_element()
}

fn parent_option(
    text: String,
    selected: bool,
    disabled: bool,
    mut on_press: impl FnMut() + 'static,
) -> Element {
    let mut row = rect()
        .width(Size::fill())
        .height(Size::px(32.))
        .padding(Gaps::new(0., 8., 0., 8.))
        .horizontal()
        .cross_align(Alignment::Center)
        .spacing(8.)
        .corner_radius(6.)
        .background(if selected { SURFACE_RAISED } else { SURFACE })
        .child(rect().width(Size::px(16.)).maybe_child(selected.then(|| {
            SvgViewer::new(icons::lucide::check())
                .width(Size::px(14.))
                .height(Size::px(14.))
                .color(ACCENT)
        })))
        .child(
            label()
                .font_size(12.)
                .color(if disabled { (92, 92, 92) } else { TEXT })
                .max_lines(1)
                .text(text),
        );
    if !disabled {
        row = row
            .a11y_role(AccessibilityRole::Button)
            .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
            .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
            .on_pointer_down(move |event: Event<PointerEventData>| {
                event.stop_propagation();
                on_press();
            });
    }
    row.into_element()
}

fn input_colors() -> InputColorsThemePartial {
    InputColorsThemePartial::new()
        .background(SURFACE)
        .focus_background(SURFACE)
        .border_fill(BORDER)
        .focus_border_fill(ACCENT)
        .color(TEXT)
        .placeholder_color(MUTED)
}

#[allow(clippy::too_many_arguments)]
fn delete_tag_confirmation(
    tag_id: String,
    tag_name: String,
    selected_tags: State<HashSet<String>>,
    mut delete_armed: State<Option<String>>,
    busy: State<bool>,
    mut error: State<Option<String>>,
    bridge: RuntimeBridge,
    snapshot_revision: State<u64>,
) -> Element {
    let action_busy = busy();
    let mut armed_for_cancel = delete_armed;
    let delete_bridge = bridge;
    let mut busy_for_delete = busy;
    let mut error_for_delete = error;
    let selected_for_delete = selected_tags;
    let armed_for_delete = delete_armed;
    let revision_for_delete = snapshot_revision;
    let delete_id = tag_id;
    let confirm = move |_| {
        if busy_for_delete() {
            return;
        }
        busy_for_delete.set(true);
        error_for_delete.set(None);
        let bridge = delete_bridge.clone();
        let id = delete_id.clone();
        let mut busy = busy_for_delete;
        let mut error = error_for_delete;
        let mut selected = selected_for_delete;
        let mut armed = armed_for_delete;
        let mut revision = revision_for_delete;
        spawn(async move {
            match request_unit(&bridge, "workspaceTag.remove", json!({"id": id.clone()})).await {
                Ok(()) => {
                    let mut next = selected.read().clone();
                    next.remove(&id);
                    selected.set(next);
                    armed.set(None);
                    revision.set(revision.peek().saturating_add(1));
                    busy.set(false);
                }
                Err(message) => {
                    busy.set(false);
                    error.set(Some(message));
                }
            }
        });
    };

    rect()
        .position(Position::new_absolute())
        .width(Size::percent(100.))
        .height(Size::percent(100.))
        .layer(Layer::Overlay)
        .center()
        .background((0, 0, 0, 170))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            if !action_busy {
                delete_armed.set(None);
            }
        })
        .child(
            rect()
                .width(Size::px(420.))
                .vertical()
                .spacing(12.)
                .padding(Gaps::new_all(20.))
                .background(SURFACE_RAISED)
                .border(Border::new().width(1.).fill(BORDER))
                .corner_radius(10.)
                .on_pointer_down(|event: Event<PointerEventData>| event.stop_propagation())
                .child(
                    label()
                        .font_size(16.)
                        .font_weight(FontWeight::BOLD)
                        .color(TEXT)
                        .text("Delete Tag"),
                )
                .child(
                    label()
                        .font_size(12.)
                        .color(MUTED)
                        .text(format!(
                            "Delete The Tag \"#{tag_name}\"? It Will Be Removed From Every Workspace That Uses It."
                        )),
                )
                .child(
                    rect()
                        .width(Size::fill())
                        .horizontal()
                        .main_align(Alignment::End)
                        .spacing(8.)
                        .child(
                            Button::new()
                                .compact()
                                .flat()
                                .on_press(move |_| {
                                    if !action_busy {
                                        error.set(None);
                                        armed_for_cancel.set(None);
                                    }
                                })
                                .child("Cancel"),
                        )
                        .child(
                            Button::new()
                                .compact()
                                .style_variant(ButtonStyleVariant::Filled)
                                .theme_colors(
                                    ButtonColorsThemePartial::new()
                                        .background((185, 28, 28))
                                        .hover_background((220, 38, 38))
                                        .border_fill(BORDER)
                                        .focus_border_fill(BORDER)
                                        .color(TEXT),
                                )
                                .on_press(confirm)
                                .child(if action_busy { "Deleting" } else { "Delete" }),
                        ),
                ),
        )
        .into_element()
}

fn workspace_descendant_ids(
    workspace_id: &str,
    relations: &[WorkspaceRelation],
) -> BTreeSet<String> {
    let mut descendants = BTreeSet::new();
    let mut pending = vec![workspace_id.to_string()];
    while let Some(parent_id) = pending.pop() {
        for relation in relations {
            if relation.parent_workspace_id == parent_id
                && descendants.insert(relation.child_workspace_id.clone())
            {
                pending.push(relation.child_workspace_id.clone());
            }
        }
    }
    descendants
}

fn compare_names(left: &str, right: &str) -> Ordering {
    left.to_lowercase()
        .cmp(&right.to_lowercase())
        .then_with(|| left.cmp(right))
}

fn workspace_parent_label(
    project: &alera_desktop_core::model::Project,
    workspace: &alera_desktop_core::model::Workspace,
) -> String {
    let branch = workspace
        .branch
        .as_deref()
        .filter(|branch| !branch.is_empty())
        .map(|branch| format!(" - {branch}"))
        .unwrap_or_default();
    format!("{} / {}{branch}", project.name, workspace.name)
}

fn filter_matches(candidate: &str, normalized_query: &str) -> bool {
    normalized_query.is_empty() || candidate.to_lowercase().contains(normalized_query)
}

fn compare_parent_options(
    preferred_project_id: Option<&str>,
    left_project: &alera_desktop_core::model::Project,
    left: &alera_desktop_core::model::Workspace,
    right_project: &alera_desktop_core::model::Project,
    right: &alera_desktop_core::model::Workspace,
) -> Ordering {
    let left_preferred = Some(left_project.id.as_str()) == preferred_project_id;
    let right_preferred = Some(right_project.id.as_str()) == preferred_project_id;
    right_preferred
        .cmp(&left_preferred)
        .then_with(|| compare_names(&left_project.name, &right_project.name))
        .then_with(|| left_project.id.cmp(&right_project.id))
        .then_with(|| (right.kind == "main").cmp(&(left.kind == "main")))
        .then_with(|| compare_names(&left.name, &right.name))
        .then_with(|| left.id.cmp(&right.id))
}

async fn submit_action(
    bridge: &RuntimeBridge,
    dialog: &SidebarActionDialog,
    name: String,
    tag_ids: Vec<String>,
    next_parent: Option<String>,
) -> Result<(), String> {
    match dialog.kind {
        SidebarActionKind::RenameProject => {
            request_unit(
                bridge,
                "project.rename",
                json!({"id": dialog.target_id, "name": name}),
            )
            .await
        }
        SidebarActionKind::RemoveProject => {
            request_unit(bridge, "project.remove", json!({"id": dialog.target_id})).await
        }
        SidebarActionKind::RenameWorkspace => {
            request_unit(
                bridge,
                "workspace.rename",
                json!({"workspaceId": dialog.target_id, "name": name}),
            )
            .await
        }
        SidebarActionKind::ManageTags => {
            request_unit(
                bridge,
                "workspaceTag.setForWorkspace",
                json!({"workspaceId": dialog.target_id, "tagIds": tag_ids}),
            )
            .await
        }
        SidebarActionKind::SleepWorkspace => {
            request_unit(
                bridge,
                "workspace.sleep",
                json!({"workspaceId": dialog.target_id}),
            )
            .await
        }
        SidebarActionKind::RemoveWorkspace => {
            request_unit(
                bridge,
                "workspace.removeManaged",
                json!({"id": dialog.target_id, "deleteBranch": dialog.delete_branch}),
            )
            .await
        }
        SidebarActionKind::SetParent => {
            if dialog.current_parent_id == next_parent {
                return Ok(());
            }
            if let Some(parent_id) = next_parent.as_ref() {
                if parent_id == &dialog.target_id {
                    return Err("A Workspace Cannot Be Its Own Parent".to_string());
                }
                let relations = bridge.request("workspaceRelation.list", json!({})).await?;
                if workspace_descendant_ids_from_json(&dialog.target_id, &relations)
                    .contains(parent_id)
                {
                    return Err("Cannot Set A Descendant Workspace As Parent".to_string());
                }
            }
            let mut removed_current_parent = false;
            if let Some(parent_id) = dialog.current_parent_id.as_ref() {
                request_unit(
                    bridge,
                    "workspaceRelation.unlink",
                    json!({"parentWorkspaceId": parent_id, "childWorkspaceId": dialog.target_id}),
                )
                .await?;
                removed_current_parent = true;
            }
            if let Some(parent_id) = next_parent {
                let result = request_unit(
                    bridge,
                    "workspaceRelation.link",
                    json!({"parentWorkspaceId": parent_id, "childWorkspaceId": dialog.target_id}),
                )
                .await;
                if let Err(link_error) = result {
                    if removed_current_parent
                        && let Some(previous_parent_id) = dialog.current_parent_id.as_ref()
                        && let Err(restore_error) = request_unit(
                            bridge,
                            "workspaceRelation.link",
                            json!({"parentWorkspaceId": previous_parent_id, "childWorkspaceId": dialog.target_id}),
                        )
                        .await
                    {
                        return Err(format!(
                            "Workspace Parent Update Failed: {link_error}. Previous Parent Restore Failed: {restore_error}"
                        ));
                    }
                    return Err(link_error);
                }
            }
            Ok(())
        }
    }
}

async fn request_unit(bridge: &RuntimeBridge, request: &str, payload: Value) -> Result<(), String> {
    bridge.request(request, payload).await.map(|_| ())
}

fn workspace_descendant_ids_from_json(workspace_id: &str, value: &Value) -> BTreeSet<String> {
    let relations = value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|relation| {
            Some((
                relation.get("parentWorkspaceId")?.as_str()?.to_string(),
                relation.get("childWorkspaceId")?.as_str()?.to_string(),
            ))
        })
        .collect::<Vec<_>>();
    let mut descendants = BTreeSet::new();
    let mut pending = vec![workspace_id.to_string()];
    while let Some(parent_id) = pending.pop() {
        for (candidate_parent, child_id) in &relations {
            if candidate_parent == &parent_id && descendants.insert(child_id.clone()) {
                pending.push(child_id.clone());
            }
        }
    }
    descendants
}

#[cfg(test)]
mod tests {
    use super::{
        compare_names, filter_matches, workspace_descendant_ids, workspace_descendant_ids_from_json,
    };
    use alera_desktop_core::model::WorkspaceRelation;
    use serde_json::json;

    fn relation(parent: &str, child: &str) -> WorkspaceRelation {
        WorkspaceRelation {
            parent_workspace_id: parent.to_string(),
            child_workspace_id: child.to_string(),
        }
    }

    #[test]
    fn descendant_filter_walks_the_full_workspace_tree() {
        let relations = vec![
            relation("root", "child"),
            relation("child", "grandchild"),
            relation("other", "unrelated"),
        ];

        let descendants = workspace_descendant_ids("root", &relations);

        assert_eq!(
            descendants.into_iter().collect::<Vec<_>>(),
            vec!["child".to_string(), "grandchild".to_string()]
        );
    }

    #[test]
    fn filters_are_case_insensitive_and_match_no_parent() {
        assert!(filter_matches("Sidebar Alpha / Readme", "alpha"));
        assert!(filter_matches("No Parent", "parent"));
        assert!(!filter_matches("Sidebar Beta", "alpha"));
    }

    #[test]
    fn runtime_relation_snapshot_is_rechecked_before_linking() {
        let relations = json!([
            {"parentWorkspaceId": "root", "childWorkspaceId": "child"},
            {"parentWorkspaceId": "child", "childWorkspaceId": "grandchild"},
            {"irrelevant": true}
        ]);

        assert_eq!(
            workspace_descendant_ids_from_json("root", &relations)
                .into_iter()
                .collect::<Vec<_>>(),
            vec!["child".to_string(), "grandchild".to_string()]
        );
    }

    #[test]
    fn names_sort_case_insensitively_with_a_stable_tie_breaker() {
        let mut names = ["beta", "Alpha", "alpha"];
        names.sort_by(|left, right| compare_names(left, right));
        assert_eq!(names, ["Alpha", "alpha", "beta"]);
    }
}
