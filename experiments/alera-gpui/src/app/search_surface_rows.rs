use std::collections::BTreeMap;
use std::rc::Rc;

use gpui::{
    div, list, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle, FontWeight,
    HighlightStyle, InteractiveElement as _, IntoElement as _, ParentElement as _, Role,
    SharedString, StatefulInteractiveElement as _, StrikethroughStyle, Styled as _, StyledText,
};

use super::AleraApp;
use crate::file_icons::file_icon;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;
use crate::workspace_service::{SearchFile, SearchMatch};

#[derive(Default)]
struct SearchTreeDirectory {
    match_count: usize,
    directories: BTreeMap<String, SearchTreeDirectory>,
    files: Vec<SearchFile>,
}

#[derive(Clone)]
enum SearchRenderRow {
    Directory {
        name: String,
        path: String,
        depth: usize,
        match_count: usize,
    },
    File {
        file: SearchFile,
        depth: usize,
        show_directory: bool,
    },
    Match {
        path: String,
        item: SearchMatch,
        depth: usize,
    },
}

impl AleraApp {
    pub(super) fn render_search_results(&self, cx: &mut Context<Self>) -> AnyElement {
        let has_query = !self.search_input.read(cx).value().trim().is_empty();
        let rows = search_rows(
            &self.search_results.files,
            self.search_view_as_tree,
            &self.search_collapsed_result_paths,
        );
        if self.search_list_state.item_count() != rows.len() {
            self.search_list_state.reset(rows.len());
        }
        let rows_empty = rows.is_empty();
        let virtual_rows = if rows_empty {
            None
        } else {
            let rows = Rc::new(rows);
            let entity = cx.entity().downgrade();
            Some(
                list(self.search_list_state.clone(), move |index, _, cx| {
                    let Some(row) = rows.get(index).cloned() else {
                        return div().into_any_element();
                    };
                    entity
                        .upgrade()
                        .map(|entity| {
                            entity.update(cx, |this, cx| this.render_search_result_row(row, cx))
                        })
                        .unwrap_or_else(|| div().into_any_element())
                })
                .size_full()
                .into_any_element(),
            )
        };
        div()
            .id("search-results")
            .flex()
            .flex_col()
            .flex_1()
            .min_h_0()
            .when(self.search_results.truncated, |results| {
                results.child(
                    div()
                        .p_2()
                        .text_size(px(12.0))
                        .text_color(theme::warning())
                        .child("Results Truncated By The Runtime Limit"),
                )
            })
            .when(
                has_query && self.search_results.files.is_empty() && !self.search_busy,
                |results| {
                    results.child(
                        div()
                            .flex()
                            .items_center()
                            .justify_center()
                            .flex_1()
                            .min_h_0()
                            .w_full()
                            .text_size(px(12.0))
                            .text_color(theme::text_muted())
                            .child("No results"),
                    )
                },
            )
            .when(self.search_busy && rows_empty, |results| {
                results.child(
                    div()
                        .id("search-loading")
                        .role(Role::ProgressIndicator)
                        .aria_label("Searching")
                        .flex()
                        .flex_1()
                        .min_h(px(160.0))
                        .w_full()
                        .items_center()
                        .justify_center()
                        .child(loading_indicator(36.0, theme::text_muted())),
                )
            })
            .when_some(virtual_rows, |results, rows| results.child(rows))
            .into_any_element()
    }

    fn render_search_result_row(&self, row: SearchRenderRow, cx: &mut Context<Self>) -> AnyElement {
        match row {
            SearchRenderRow::Directory {
                name,
                path,
                depth,
                match_count,
            } => self.render_search_directory_row(name, path, depth, match_count, cx),
            SearchRenderRow::File {
                file,
                depth,
                show_directory,
            } => self.render_search_file_row(file, depth, show_directory, cx),
            SearchRenderRow::Match { path, item, depth } => {
                self.render_search_match_row(path, item, depth, cx)
            }
        }
    }

    fn render_search_directory_row(
        &self,
        name: String,
        path: String,
        depth: usize,
        match_count: usize,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let key = format!("dir:{path}");
        let collapsed = self.search_collapsed_result_paths.contains(&key);
        let accessibility_name = format!("Toggle {name}");
        div()
            .id(SharedString::from(format!("search-directory-{path}")))
            .w_full()
            .min_w_0()
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(accessibility_name)
            .flex()
            .items_center()
            .py(px(6.0))
            .pr_2()
            .pl(px(8.0 + depth as f32 * 16.0))
            .gap(px(4.0))
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_selected()))
            .on_click(cx.listener(move |this, _, _, cx| {
                if !this.search_collapsed_result_paths.insert(key.clone()) {
                    this.search_collapsed_result_paths.remove(&key);
                }
                cx.notify();
            }))
            .child(icon(
                if collapsed {
                    AleraIcon::ChevronRight
                } else {
                    AleraIcon::ChevronDown
                },
                16.0,
                theme::text_muted(),
            ))
            .child(file_icon(
                &name,
                true,
                !collapsed,
                false,
                15.0,
                theme::text_muted(),
            ))
            .child(div().w(px(2.0)))
            .child(
                div()
                    .flex_1()
                    .overflow_hidden()
                    .text_ellipsis()
                    .text_size(px(12.0))
                    .font_weight(FontWeight::SEMIBOLD)
                    .child(name),
            )
            .child(
                div()
                    .w(px(24.0))
                    .text_align(gpui::TextAlign::Right)
                    .text_size(px(12.0))
                    .font_weight(FontWeight::BOLD)
                    .child(match_count.to_string()),
            )
            .into_any_element()
    }

    fn render_search_file_row(
        &self,
        file: SearchFile,
        depth: usize,
        show_directory: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let key = format!("file:{}", file.relative_path);
        let collapsed = self.search_collapsed_result_paths.contains(&key);
        let ids = file
            .matches
            .iter()
            .map(|item| item.id.clone())
            .collect::<Vec<_>>();
        let (name, directory) = split_path(&file.relative_path);
        let can_replace = self.search_replace_expanded && !self.search_busy;
        let accessibility_name = format!("Toggle {}", file.relative_path);
        div()
            .id(SharedString::from(format!(
                "search-file-{}",
                file.relative_path
            )))
            .w_full()
            .min_w_0()
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(accessibility_name)
            .flex()
            .items_center()
            .py(px(6.0))
            .pr_2()
            .pl(px(8.0 + depth as f32 * 16.0))
            .gap(px(4.0))
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_selected()))
            .on_click(cx.listener(move |this, _, _, cx| {
                if !this.search_collapsed_result_paths.insert(key.clone()) {
                    this.search_collapsed_result_paths.remove(&key);
                }
                cx.notify();
            }))
            .child(icon(
                if collapsed {
                    AleraIcon::ChevronRight
                } else {
                    AleraIcon::ChevronDown
                },
                16.0,
                theme::text_muted(),
            ))
            .child(file_icon(
                &name,
                false,
                false,
                false,
                15.0,
                theme::text_muted(),
            ))
            .child(div().w(px(2.0)))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .flex_1()
                    .min_w_0()
                    .overflow_hidden()
                    .child(
                        div()
                            .min_w_0()
                            .text_ellipsis()
                            .text_size(px(12.0))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child(name),
                    )
                    .when(show_directory && !directory.is_empty(), |label| {
                        label.child(
                            div()
                                .overflow_hidden()
                                .text_ellipsis()
                                .text_size(px(12.0))
                                .text_color(theme::text_muted())
                                .child(directory),
                        )
                    }),
            )
            .child(
                div()
                    .w(px(24.0))
                    .text_align(gpui::TextAlign::Right)
                    .text_size(px(12.0))
                    .font_weight(FontWeight::BOLD)
                    .child(file.matches.len().to_string()),
            )
            .child(div().w(px(4.0)))
            .child(
                super::search_surface::search_icon_button(
                    SharedString::from(format!("replace-search-file-{}", file.relative_path)),
                    AleraIcon::Replace,
                    can_replace,
                    false,
                    "Replace in file",
                )
                .when(can_replace, |button| {
                    button.on_click(cx.listener(move |this, _, _, cx| {
                        this.request_replace(ids.clone(), cx);
                        cx.stop_propagation();
                    }))
                }),
            )
            .into_any_element()
    }

    fn render_search_match_row(
        &self,
        path: String,
        item: SearchMatch,
        depth: usize,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let open_path = path.clone();
        let line = item.line;
        let column = item.column;
        let match_length = item.match_length;
        let match_id = item.id.clone();
        let can_replace = self.search_replace_expanded && !self.search_busy;
        let preview = styled_match_preview(&item, self.search_replace_expanded);
        let accessibility_name = format!("Open {path} line {line}");
        let row_id = SharedString::from(format!("search-match-{path}-{match_id}"));
        let action = super::search_surface::search_icon_button(
            SharedString::from(format!("replace-search-match-{path}-{match_id}")),
            AleraIcon::Replace, can_replace, false, "Replace match",
        ).when(can_replace, |button| {
            button.on_click(cx.listener(move |this, _, _, cx| {
                this.request_replace(vec![match_id.clone()], cx);
                cx.stop_propagation();
            }))
        }).into_any_element();
        super::search_result_layout::match_row(line, preview, action, depth)
            .id(row_id)
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(accessibility_name)
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_selected()))
            .on_click(cx.listener(move |this, _, window, cx| {
                this.open_search_match(open_path.clone(), line, column, match_length, window, cx);
            }))
            .into_any_element()
    }
}

fn search_rows(
    files: &[SearchFile],
    view_as_tree: bool,
    collapsed: &std::collections::BTreeSet<String>,
) -> Vec<SearchRenderRow> {
    if !view_as_tree {
        let mut rows = Vec::new();
        for file in files {
            rows.push(SearchRenderRow::File {
                file: file.clone(),
                depth: 0,
                show_directory: true,
            });
            if !collapsed.contains(&format!("file:{}", file.relative_path)) {
                rows.extend(
                    file.matches
                        .iter()
                        .cloned()
                        .map(|item| SearchRenderRow::Match {
                            path: file.relative_path.clone(),
                            item,
                            depth: 0,
                        }),
                );
            }
        }
        return rows;
    }

    let mut root = SearchTreeDirectory::default();
    for file in files {
        let segments = file
            .relative_path
            .split(['/', '\\'])
            .filter(|segment| !segment.is_empty())
            .collect::<Vec<_>>();
        let mut directory = &mut root;
        for segment in segments.iter().take(segments.len().saturating_sub(1)) {
            directory = directory
                .directories
                .entry((*segment).to_owned())
                .or_default();
            directory.match_count += file.matches.len();
        }
        directory.files.push(file.clone());
    }
    let mut rows = Vec::new();
    append_tree_rows(&root, "", 0, collapsed, &mut rows);
    rows
}

pub(super) fn search_collapsible_keys(
    files: &[SearchFile],
    view_as_tree: bool,
) -> std::collections::BTreeSet<String> {
    let mut keys = files
        .iter()
        .map(|file| format!("file:{}", file.relative_path))
        .collect::<std::collections::BTreeSet<_>>();
    if view_as_tree {
        for file in files {
            let normalized = file.relative_path.replace('\\', "/");
            let segments = normalized
                .split('/')
                .filter(|segment| !segment.is_empty())
                .collect::<Vec<_>>();
            for end in 1..segments.len() {
                keys.insert(format!("dir:{}", segments[..end].join("/")));
            }
        }
    }
    keys
}

fn append_tree_rows(
    directory: &SearchTreeDirectory,
    parent_path: &str,
    depth: usize,
    collapsed: &std::collections::BTreeSet<String>,
    rows: &mut Vec<SearchRenderRow>,
) {
    for (name, child) in &directory.directories {
        let path = if parent_path.is_empty() {
            name.clone()
        } else {
            format!("{parent_path}/{name}")
        };
        rows.push(SearchRenderRow::Directory {
            name: name.clone(),
            path: path.clone(),
            depth,
            match_count: child.match_count,
        });
        if !collapsed.contains(&format!("dir:{path}")) {
            append_tree_rows(child, &path, depth + 1, collapsed, rows);
        }
    }
    let mut files = directory.files.clone();
    files.sort_by(|a, b| a.relative_path.cmp(&b.relative_path));
    for file in files {
        let key = format!("file:{}", file.relative_path);
        rows.push(SearchRenderRow::File {
            file: file.clone(),
            depth,
            show_directory: false,
        });
        if !collapsed.contains(&key) {
            rows.extend(
                file.matches
                    .iter()
                    .cloned()
                    .map(|item| SearchRenderRow::Match {
                        path: file.relative_path.clone(),
                        item,
                        depth: depth + 1,
                    }),
            );
        }
    }
}

fn split_path(path: &str) -> (String, String) {
    let normalized = path.replace('\\', "/");
    normalized.rsplit_once('/').map_or_else(
        || (normalized.clone(), String::new()),
        |(directory, name)| (name.to_owned(), directory.to_owned()),
    )
}

fn styled_match_preview(item: &SearchMatch, show_replacement: bool) -> StyledText {
    let text = item.line_content.trim_end().to_owned();
    let column = item.display_column.unwrap_or(item.column).saturating_sub(1) as usize;
    let length = item.display_match_length.unwrap_or(item.match_length) as usize;
    let start = char_to_byte(&text, column);
    let end = char_to_byte(&text, column.saturating_add(length));
    let mut highlights = vec![(
        start..end,
        HighlightStyle {
            color: Some(theme::text().into()),
            background_color: Some(theme::accent_subtle().into()),
            font_weight: Some(FontWeight::BOLD),
            ..HighlightStyle::default()
        },
    )];
    if show_replacement {
        if let Some(replacement) = item.replacement_preview.as_ref() {
            // Flutter keeps the original match visible with a red
            // strikethrough and appends the replacement in green. Replacing
            // the range outright hides the data-loss preview the user needs
            // before confirming Replace All.
            let mut preview = String::with_capacity(
                text.len()
                    .saturating_sub(end.saturating_sub(start))
                    .saturating_add(replacement.len())
                    .saturating_add(end.saturating_sub(start)),
            );
            preview.push_str(&text[..start]);
            let old_start = preview.len();
            preview.push_str(&text[start..end]);
            let old_end = preview.len();
            let replacement_start = preview.len();
            preview.push_str(replacement);
            let replacement_end = preview.len();
            preview.push_str(&text[end..]);
            highlights = vec![
                (
                    old_start..old_end,
                    HighlightStyle {
                        color: Some(theme::danger().into()),
                        strikethrough: Some(StrikethroughStyle {
                            thickness: px(1.0),
                            color: Some(theme::danger().into()),
                        }),
                        ..HighlightStyle::default()
                    },
                ),
                (
                    replacement_start..replacement_end,
                    HighlightStyle {
                        color: Some(theme::success().into()),
                        font_weight: Some(FontWeight::BOLD),
                        ..HighlightStyle::default()
                    },
                ),
            ];
            return StyledText::new(SharedString::from(preview)).with_highlights(highlights);
        }
    }
    StyledText::new(SharedString::from(text)).with_highlights(highlights)
}

fn char_to_byte(text: &str, char_offset: usize) -> usize {
    text.char_indices()
        .nth(char_offset)
        .map_or(text.len(), |(offset, _)| offset)
}
