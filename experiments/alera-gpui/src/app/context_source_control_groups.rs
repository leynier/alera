use std::collections::BTreeSet;
use std::path::Path;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, MouseDownEvent, ParentElement as _, Styled as _,
};

use super::context_source_control_actions::source_row_action;
use super::AleraApp;
use crate::file_icons::file_icon;
use crate::icons::{icon, AleraIcon};
use crate::theme;
use crate::workspace_git::{GitAction, GitChange};

struct SourceTreeRow<'a> {
    path: String,
    name: String,
    depth: usize,
    file_count: usize,
    change: Option<&'a GitChange>,
}

impl AleraApp {
    pub(super) fn source_change_group(
        &self,
        group_index: usize,
        area: &'static str,
        changes: &[&GitChange],
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let entries = changes
            .iter()
            .copied()
            .filter(|change| change.area.eq_ignore_ascii_case(area))
            .collect::<Vec<_>>();
        if entries.is_empty() {
            return None;
        }
        let collapsed = self.source_control_collapsed_sections.contains(area);
        let label = match area {
            "staged" => "Staged",
            "untracked" => "Untracked",
            _ => "Unstaged",
        };
        let area_key = area.to_owned();
        let paths = entries
            .iter()
            .map(|entry| entry.path.clone())
            .collect::<Vec<_>>();
        let stage_paths = paths.clone();
        let discard_paths = paths.clone();
        let staged = area == "staged";
        let header = div()
            .id(gpui::SharedString::from(format!("source-group-{area}")))
            .flex()
            .items_center()
            .h(px(28.0))
            .px_2()
            .cursor(CursorStyle::PointingHand)
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    if !this.source_control_collapsed_sections.remove(&area_key) {
                        this.source_control_collapsed_sections
                            .insert(area_key.clone());
                    }
                    cx.notify();
                }),
            )
            .child(icon(
                if collapsed {
                    AleraIcon::ChevronRight
                } else {
                    AleraIcon::ChevronDown
                },
                14.0,
                theme::text_muted(),
            ))
            .child(div().w(px(4.0)))
            .child(
                div()
                    .flex_1()
                    .text_xs()
                    .text_color(theme::text_muted())
                    .child(label),
            )
            .child(
                div()
                    .text_xs()
                    .text_color(theme::text_faint())
                    .child(entries.len().to_string()),
            )
            .child(div().w(px(6.0)))
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_end()
                    .w(px(58.0))
                    .child(
                        source_row_action(
                            gpui::SharedString::from(format!("source-group-stage-{area}")),
                            if staged {
                                AleraIcon::GitUnstage
                            } else {
                                AleraIcon::GitStage
                            },
                            false,
                        )
                        .on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                cx.stop_propagation();
                                this.run_git_path_actions(
                                    stage_paths
                                        .iter()
                                        .map(|path| {
                                            if staged {
                                                GitAction::UnstagePath(path.clone())
                                            } else {
                                                GitAction::StagePath(path.clone())
                                            }
                                        })
                                        .collect(),
                                    cx,
                                );
                            }),
                        ),
                    )
                    .when(!staged, |actions| {
                        actions.child(
                            source_row_action(
                                gpui::SharedString::from(format!("source-group-discard-{area}")),
                                AleraIcon::GitDiscard,
                                true,
                            )
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                    cx.stop_propagation();
                                    this.request_discard_paths(discard_paths.clone(), cx);
                                }),
                            ),
                        )
                    }),
            );
        Some(
            div()
                .flex()
                .flex_col()
                .pb_2()
                .child(header)
                .when(!collapsed && !self.source_control_tree_mode, |group| {
                    group.children(entries.iter().copied().enumerate().map(
                        |(row_index, change)| {
                            self.source_change_row(group_index, row_index, 0, area, change, cx)
                        },
                    ))
                })
                .when(!collapsed && self.source_control_tree_mode, |group| {
                    group.children(
                        source_tree_rows(&entries)
                            .into_iter()
                            .enumerate()
                            .filter_map(|(row_index, row)| {
                                self.source_tree_row(group_index, row_index, area, row, cx)
                            }),
                    )
                })
                .into_any_element(),
        )
    }

    fn source_tree_row(
        &self,
        group_index: usize,
        row_index: usize,
        area: &str,
        row: SourceTreeRow<'_>,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let tree_key = format!("{area}:{}", row.path);
        let hidden = ancestor_keys(area, &row.path)
            .into_iter()
            .any(|key| self.source_control_collapsed_tree_nodes.contains(&key));
        if hidden {
            return None;
        }
        let Some(change) = row.change else {
            let collapsed = self.source_control_collapsed_tree_nodes.contains(&tree_key);
            let toggle_key = tree_key.clone();
            return Some(
                div()
                    .id(gpui::SharedString::from(format!(
                        "source-tree-dir-{area}-{}",
                        row.path
                    )))
                    .flex()
                    .items_center()
                    .h(px(30.0))
                    .pl(px(8.0 + row.depth as f32 * 12.0))
                    .pr_2()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            if !this.source_control_collapsed_tree_nodes.remove(&toggle_key) {
                                this.source_control_collapsed_tree_nodes
                                    .insert(toggle_key.clone());
                            }
                            cx.notify();
                        }),
                    )
                    .child(icon(
                        if collapsed {
                            AleraIcon::ChevronRight
                        } else {
                            AleraIcon::ChevronDown
                        },
                        14.0,
                        theme::text_muted(),
                    ))
                    .child(file_icon(
                        &row.name,
                        true,
                        false,
                        false,
                        15.0,
                        theme::text_muted(),
                    ))
                    .child(
                        div()
                            .ml(px(6.0))
                            .flex_1()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(row.name),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(theme::text_faint())
                            .child(row.file_count.to_string()),
                    )
                    .into_any_element(),
            );
        };
        Some(self.source_change_row(group_index, row_index, row.depth, area, change, cx))
    }

    fn source_change_row(
        &self,
        _group_index: usize,
        _row_index: usize,
        depth: usize,
        area: &str,
        change: &GitChange,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let staged = area == "staged";
        let action_path = change.path.clone();
        let discard_path = change.path.clone();
        let diff_path = change.path.clone();
        let diff_area = area.to_owned();
        div()
            .id(gpui::SharedString::from(format!(
                "source-change-{area}-{}",
                change.path
            )))
            .flex()
            .items_center()
            .h(px(30.0))
            .pl(px(8.0 + depth as f32 * 12.0))
            .pr_2()
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_selected()))
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    this.open_git_diff_tab(Some(diff_path.clone()), Some(diff_area.clone()), cx);
                }),
            )
            .child(div().w(px(16.0)))
            .child(file_icon(
                &change.path,
                false,
                false,
                false,
                15.0,
                theme::text_muted(),
            ))
            .child(
                div()
                    .ml(px(6.0))
                    .flex_1()
                    .overflow_hidden()
                    .text_ellipsis()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child(change.path.clone()),
            )
            .child(status_badge(&change.status))
            .child(div().w(px(6.0)))
            .child(line_stats(change.added, change.removed))
            .child(div().w(px(4.0)))
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_end()
                    .w(px(58.0))
                    .child(
                        source_row_action(
                            gpui::SharedString::from(format!(
                                "source-stage-{area}-{}",
                                change.path
                            )),
                            if staged {
                                AleraIcon::GitUnstage
                            } else {
                                AleraIcon::GitStage
                            },
                            false,
                        )
                        .on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                cx.stop_propagation();
                                this.run_git_action(
                                    if staged {
                                        GitAction::UnstagePath(action_path.clone())
                                    } else {
                                        GitAction::StagePath(action_path.clone())
                                    },
                                    cx,
                                );
                            }),
                        ),
                    )
                    .when(!staged, |actions| {
                        actions.child(
                            source_row_action(
                                gpui::SharedString::from(format!(
                                    "source-discard-{area}-{}",
                                    change.path
                                )),
                                AleraIcon::GitDiscard,
                                true,
                            )
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                    cx.stop_propagation();
                                    this.request_discard_path(discard_path.clone(), cx);
                                }),
                            ),
                        )
                    }),
            )
            .into_any_element()
    }
}

fn status_badge(status: &str) -> AnyElement {
    let badge = status.chars().next().unwrap_or('M').to_ascii_uppercase();
    let color = match badge {
        'A' | 'U' => theme::success(),
        'D' => theme::danger(),
        _ => theme::warning(),
    };
    div()
        .w(px(12.0))
        .text_center()
        .text_xs()
        .text_color(color)
        .child(badge.to_string())
        .into_any_element()
}

fn line_stats(added: Option<u32>, removed: Option<u32>) -> AnyElement {
    div()
        .flex()
        .items_center()
        .justify_end()
        .w(px(64.0))
        .gap(px(4.0))
        .when(added.unwrap_or_default() > 0, |stats| {
            stats.child(
                div()
                    .text_xs()
                    .text_color(theme::success())
                    .child(format!("+{}", added.unwrap_or_default())),
            )
        })
        .when(removed.unwrap_or_default() > 0, |stats| {
            stats.child(
                div()
                    .text_xs()
                    .text_color(theme::danger())
                    .child(format!("-{}", removed.unwrap_or_default())),
            )
        })
        .into_any_element()
}

fn source_tree_rows<'a>(entries: &[&'a GitChange]) -> Vec<SourceTreeRow<'a>> {
    let mut directories = BTreeSet::new();
    for entry in entries {
        let components = entry.path.split('/').collect::<Vec<_>>();
        for depth in 0..components.len().saturating_sub(1) {
            directories.insert(components[..=depth].join("/"));
        }
    }
    let mut rows = Vec::new();
    let mut paths = entries
        .iter()
        .map(|entry| entry.path.as_str())
        .chain(directories.iter().map(String::as_str))
        .collect::<Vec<_>>();
    paths.sort();
    for path in paths {
        if directories.contains(path) {
            rows.push(SourceTreeRow {
                name: Path::new(path)
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or(path)
                    .to_owned(),
                path: path.to_owned(),
                depth: path.matches('/').count(),
                file_count: entries
                    .iter()
                    .filter(|entry| entry.path.starts_with(&format!("{path}/")))
                    .count(),
                change: None,
            });
        } else if let Some(change) = entries.iter().copied().find(|entry| entry.path == path) {
            rows.push(SourceTreeRow {
                name: Path::new(path)
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or(path)
                    .to_owned(),
                path: path.to_owned(),
                depth: path.matches('/').count(),
                file_count: 1,
                change: Some(change),
            });
        }
    }
    rows
}

fn ancestor_keys(area: &str, path: &str) -> Vec<String> {
    let components = path.split('/').collect::<Vec<_>>();
    (0..components.len().saturating_sub(1))
        .map(|depth| format!("{area}:{}", components[..=depth].join("/")))
        .collect()
}
