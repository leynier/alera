use std::collections::BTreeSet;
use std::path::Path;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
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
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(gpui::SharedString::from(format!(
                "{label} {}",
                entries.len()
            )))
            .aria_expanded(!collapsed)
            .flex()
            .items_center()
            .h(px(28.0))
            .px_2()
            .cursor(CursorStyle::PointingHand)
            .on_click(cx.listener(move |this, _, _, cx| {
                if !this.source_control_collapsed_sections.remove(&area_key) {
                    this.source_control_collapsed_sections
                        .insert(area_key.clone());
                }
                cx.notify();
            }))
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
                        .on_click(cx.listener(move |this, _, _, cx| {
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
                        })),
                    )
                    .when(!staged, |actions| {
                        actions.child(
                            source_row_action(
                                gpui::SharedString::from(format!("source-group-discard-{area}")),
                                AleraIcon::GitDiscard,
                                true,
                            )
                            .on_click(cx.listener(
                                move |this, _, _, cx| {
                                    cx.stop_propagation();
                                    this.request_discard_paths(discard_paths.clone(), cx);
                                },
                            )),
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
            self.source_change_row(
                group_index,
                row_index,
                0,
                area,
                change,
                None,
                false,
                cx,
            )
                        },
                    ))
                })
                .when(!collapsed && self.source_control_tree_mode, |group| {
                    group.children(
                        source_tree_rows(&entries)
                            .into_iter()
                            .enumerate()
                            .filter_map(|(row_index, row)| {
                                self.source_tree_row(
                                    group_index,
                                    row_index,
                                    area,
                                    row,
                                    false,
                                    cx,
                                )
                            }),
                    )
                })
                        .into_any_element(),
        )
    }

    /// Render the unified Source Control mode. Entries stay sorted by path and
    /// retain their real staged area so stage/unstage/discard actions continue
    /// to target the correct side of the index.
    pub(super) fn source_unified_change_group(
        &self,
        changes: &[&GitChange],
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let mut entries = changes.to_vec();
        entries.sort_by(|left, right| {
            left.path.cmp(&right.path).then_with(|| {
                source_area_sort_index(&left.area).cmp(&source_area_sort_index(&right.area))
            })
        });
        let collapsed = self.source_control_collapsed_sections.contains("unified");
        let stage_paths = entries
            .iter()
            .filter(|change| !change.area.eq_ignore_ascii_case("staged"))
            .map(|change| change.path.clone())
            .collect::<Vec<_>>();
        let unstage_paths = entries
            .iter()
            .filter(|change| change.area.eq_ignore_ascii_case("staged"))
            .map(|change| change.path.clone())
            .collect::<Vec<_>>();
        let discard_paths = stage_paths.clone();
        let toggle_key = "unified".to_owned();
        let mut header = div()
            .id("source-group-unified")
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(gpui::SharedString::from(format!(
                "Changes {}",
                entries.len()
            )))
            .aria_expanded(!collapsed)
            .flex()
            .items_center()
            .h(px(28.0))
            .px_2()
            .cursor(CursorStyle::PointingHand)
            .on_click(cx.listener(move |this, _, _, cx| {
                if !this
                    .source_control_collapsed_sections
                    .remove(&toggle_key)
                {
                    this.source_control_collapsed_sections.insert(toggle_key.clone());
                }
                cx.notify();
            }))
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
                    .child("Changes"),
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
                    .w(px(86.0)),
            );
        if !stage_paths.is_empty() {
            let paths = stage_paths.clone();
            header = header.child(
                source_row_action(
                    "source-group-stage-unified",
                    AleraIcon::GitStage,
                    false,
                )
                .on_click(cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.run_git_path_actions(
                        paths
                            .iter()
                            .cloned()
                            .map(GitAction::StagePath)
                            .collect(),
                        cx,
                    );
                })),
            );
            let paths = discard_paths.clone();
            header = header.child(
                source_row_action(
                    "source-group-discard-unified",
                    AleraIcon::GitDiscard,
                    true,
                )
                .on_click(cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.request_discard_paths(paths.clone(), cx);
                })),
            );
        }
        if !unstage_paths.is_empty() {
            let paths = unstage_paths.clone();
            header = header.child(
                source_row_action(
                    "source-group-unstage-unified",
                    AleraIcon::GitUnstage,
                    false,
                )
                .on_click(cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.run_git_path_actions(
                        paths
                            .iter()
                            .cloned()
                            .map(GitAction::UnstagePath)
                            .collect(),
                        cx,
                    );
                })),
            );
        }
        let mut group = div().flex().flex_col().pb_2().child(header);
        if !collapsed && !self.source_control_tree_mode {
            group = group.children(
                entries.iter().enumerate().map(|(row_index, change)| {
                    self.source_change_row(
                        0,
                        row_index,
                        0,
                        "unified",
                        change,
                        None,
                        true,
                        cx,
                    )
                }),
            );
        }
        if !collapsed && self.source_control_tree_mode {
            group = group.children(
                source_tree_rows(&entries)
                    .into_iter()
                    .enumerate()
                    .filter_map(|(row_index, row)| {
                        self.source_tree_row(0, row_index, "unified", row, true, cx)
                    }),
            );
        }
        group.into_any_element()
    }

    fn source_tree_row(
        &self,
        group_index: usize,
        row_index: usize,
        area: &str,
        row: SourceTreeRow<'_>,
        show_area_marker: bool,
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
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label(row.name.clone())
                    .aria_expanded(!collapsed)
                    .flex()
                    .items_center()
                    .h(px(30.0))
                    .pl(px(8.0 + row.depth as f32 * 12.0))
                    .pr_2()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if !this.source_control_collapsed_tree_nodes.remove(&toggle_key) {
                            this.source_control_collapsed_tree_nodes
                                .insert(toggle_key.clone());
                        }
                        cx.notify();
                    }))
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
        Some(self.source_change_row(
            group_index,
            row_index,
            row.depth,
            area,
            change,
            Some(&row.name),
            show_area_marker,
            cx,
        ))
    }

    #[allow(clippy::too_many_arguments)]
    fn source_change_row(
        &self,
        _group_index: usize,
        _row_index: usize,
        depth: usize,
        area: &str,
        change: &GitChange,
        display_name: Option<&str>,
        show_area_marker: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let staged = change.area.eq_ignore_ascii_case("staged");
        let action_path = change.path.clone();
        let discard_path = change.path.clone();
        let diff_path = change.path.clone();
        let diff_area = change.area.clone();
        let action_area = if area == "unified" {
            change.area.as_str()
        } else {
            area
        };
        let display_name = display_name.unwrap_or(&change.path).to_owned();
        div()
            .id(gpui::SharedString::from(format!(
                "source-change-{area}-{action_area}-{}",
                change.path
            )))
            .focusable()
            .tab_stop(true)
            .role(Role::ListBoxOption)
            .aria_label(gpui::SharedString::from(format!(
                "{} {}",
                display_name, change.status
            )))
            .flex()
            .items_center()
            .h(px(30.0))
            .pl(px(8.0 + depth as f32 * 12.0))
            .pr_2()
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_selected()))
            .on_click(cx.listener(move |this, _, _, cx| {
                let permanent = this.should_keep_git_preview(format!(
                    "working:file:{}:{}",
                    diff_area, diff_path
                ));
                this.open_git_diff_preview_tab(
                    Some(diff_path.clone()),
                    Some(diff_area.clone()),
                    permanent,
                    cx,
                );
            }))
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
                    .whitespace_nowrap()
                    .text_ellipsis()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child(display_name),
            )
            .when(show_area_marker, |row| {
                row.child(area_badge(&change.area))
            })
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
                                "source-stage-{area}-{action_area}-{}",
                                change.path
                            )),
                            if staged {
                                AleraIcon::GitUnstage
                            } else {
                                AleraIcon::GitStage
                            },
                            false,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.run_git_action(
                                if staged {
                                    GitAction::UnstagePath(action_path.clone())
                                } else {
                                    GitAction::StagePath(action_path.clone())
                                },
                                cx,
                            );
                        })),
                    )
                    .when(!staged, |actions| {
                        actions.child(
                            source_row_action(
                                gpui::SharedString::from(format!(
                                    "source-discard-{area}-{action_area}-{}",
                                    change.path
                                )),
                                AleraIcon::GitDiscard,
                                true,
                            )
                            .on_click(cx.listener(
                                move |this, _, _, cx| {
                                    cx.stop_propagation();
                                    this.request_discard_path(discard_path.clone(), cx);
                                },
                            )),
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

fn area_badge(area: &str) -> AnyElement {
    let (label, color) = if area.eq_ignore_ascii_case("staged") {
        ("S", theme::success())
    } else if area.eq_ignore_ascii_case("unstaged") {
        ("U", theme::warning())
    } else {
        ("?", theme::text_muted())
    };
    div()
        .w(px(12.0))
        .text_center()
        .text_xs()
        .text_color(color)
        .child(label)
        .into_any_element()
}

fn source_area_sort_index(area: &str) -> usize {
    if area.eq_ignore_ascii_case("staged") {
        0
    } else if area.eq_ignore_ascii_case("unstaged") {
        1
    } else {
        2
    }
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
    paths.dedup();
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
        } else {
            for change in entries.iter().copied().filter(|entry| entry.path == path) {
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
    }
    rows
}

fn ancestor_keys(area: &str, path: &str) -> Vec<String> {
    let components = path.split('/').collect::<Vec<_>>();
    (0..components.len().saturating_sub(1))
        .map(|depth| format!("{area}:{}", components[..=depth].join("/")))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tree_leaf_uses_basename_without_losing_action_path() {
        let change = GitChange {
            path: "src/components/stats/top-languages-stat.astro".to_owned(),
            area: "unstaged".to_owned(),
            status: "M".to_owned(),
            added: Some(2),
            removed: Some(1),
        };
        let rows = source_tree_rows(&[&change]);
        let leaf = rows
            .iter()
            .find(|row| row.change.is_some())
            .expect("tree should retain the changed file");

        assert_eq!(leaf.name, "top-languages-stat.astro");
        assert_eq!(leaf.path, change.path);
        assert_eq!(
            leaf.change.map(|entry| entry.path.as_str()),
            Some(change.path.as_str())
        );
    }
}
