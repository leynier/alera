use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, StatefulInteractiveElement as _,
    Styled as _,
};

use super::AleraApp;
use crate::file_icons::file_icon;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::model::WorkspaceTab;
use crate::theme;
use crate::workspace_git::{GitDiffFile, GitDiffLine};

impl AleraApp {
    pub(super) fn render_git_diff_surface(
        &self,
        tab: &WorkspaceTab,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let loading = self.git_diff_loading_tab.as_deref() == Some(tab.id.as_str());
        let loaded = self.git_diff_loaded_tab.as_deref() == Some(tab.id.as_str());
        let refresh_id = tab.id.clone();
        let refresh_payload = tab.payload.clone();
        let open_path = tab
            .payload
            .get("filePath")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let source_scope = self.source_control_scope_for_root(
            tab.payload
                .get("gitDiffRoot")
                .and_then(serde_json::Value::as_str),
        );
        let source_open_path = open_path.as_deref().and_then(|path| {
            source_scope
                .as_ref()
                .and_then(|scope| scope.to_source_relative_path(path))
        });
        let commit_diff = tab
            .payload
            .get("gitDiffSource")
            .and_then(serde_json::Value::as_str)
            == Some("commit");
        let openable_path = (!commit_diff)
            .then_some(source_open_path.as_deref())
            .flatten()
            .and_then(|path| {
                self.git_diff
                    .files
                    .iter()
                    .find(|file| file.path == path)
                    .filter(|file| {
                        !(file.is_gitlink
                            || file.status.eq_ignore_ascii_case("deleted")
                            || file.status.eq_ignore_ascii_case("renamed")
                                && file.old_path.as_deref() == Some(file.path.as_str()))
                    })
                    .map(|_| ())
            })
            .and_then(|()| open_path.clone());
        let can_open_file = openable_path.is_some();
        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .min_h_0()
            .overflow_hidden()
            .bg(theme::app_background())
            .child(
                div()
                    .flex()
                    .items_center()
                    .h(px(44.0))
                    .px_3()
                    .gap_2()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(
                        div()
                            .w_0()
                            .flex_1()
                            .overflow_hidden()
                            .text_ellipsis()
                            .whitespace_nowrap()
                            .text_size(px(12.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child(tab.title.clone()),
                    )
                    .child(
                        div()
                            .id("git-diff-open-file")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .text_color(if can_open_file {
                                theme::text_muted()
                            } else {
                                theme::text_faint()
                            })
                            .when(can_open_file, |button| {
                                let path = openable_path
                                    .clone()
                                    .expect("openable path should exist when enabled");
                                button
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .on_mouse_down(
                                        gpui::MouseButton::Left,
                                        cx.listener(move |this, _, _, cx| {
                                            this.open_editor_tab(path.clone(), cx);
                                        }),
                                    )
                            })
                            .child(icon(
                                AleraIcon::External,
                                16.0,
                                if can_open_file {
                                    theme::text_muted()
                                } else {
                                    theme::text_faint()
                                },
                            )),
                    )
                    .child(
                        div()
                            .id("git-diff-refresh")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    this.load_git_diff_tab(
                                        refresh_id.clone(),
                                        refresh_payload.clone(),
                                        cx,
                                    );
                                }),
                            )
                            .child(icon(
                                if loading {
                                    AleraIcon::Loading
                                } else {
                                    AleraIcon::GitRefresh
                                },
                                16.0,
                                theme::text_muted(),
                            )),
                    ),
            )
            .child(
                div()
                    .id("git-diff-content")
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .when(loading && !loaded, |content| {
                        content
                            .items_center()
                            .justify_center()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap_2()
                                    .child(loading_indicator(15.0, theme::text_muted()))
                                    .child("Loading Diff"),
                            )
                    })
                    .when(
                        !loading && loaded && self.git_diff.files.is_empty(),
                        |content| {
                            content
                                .items_center()
                                .justify_center()
                                .text_sm()
                                .text_color(theme::text_muted())
                                .child("No Diff Available.")
                        },
                    )
                    .when(loaded && !self.git_diff.files.is_empty(), |content| {
                        content
                            .when(self.git_diff.truncated, |content| {
                                content.child(diff_banner("Diff Truncated For Preview"))
                            })
                            .children(
                                self.git_diff.files.iter().enumerate().map(|(index, file)| {
                                    render_diff_file(index, file, commit_diff)
                                }),
                            )
                    }),
            )
            .into_any_element()
    }
}

fn render_diff_file(index: usize, file: &GitDiffFile, commit_diff: bool) -> AnyElement {
    div()
        .flex()
        .flex_col()
        .child(
            div()
                .id(("git-diff-file", index))
                .flex()
                .items_center()
                .h(px(32.0))
                .px_3()
                .gap_2()
                .border_b_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_raised())
                .child(file_icon(
                    &file.path,
                    false,
                    false,
                    false,
                    16.0,
                    theme::text_muted(),
                ))
                .child(
                    div()
                        .w_0()
                        .flex_1()
                        .overflow_hidden()
                        .text_ellipsis()
                        .whitespace_nowrap()
                        .font_family("JetBrains Mono")
                        .text_size(px(12.0))
                        .text_color(theme::text())
                        .child(format!(
                            "{} · {}",
                            if commit_diff {
                                "Commit"
                            } else {
                                title_case_area(&file.area)
                            },
                            file.path
                        )),
                )
                .child(diff_stats(file)),
        )
        .when(file.is_binary, |content| {
            content.child(diff_banner("Binary File Diff Is Not Shown"))
        })
        .when(!file.is_binary && file.is_large, |content| {
            content.child(diff_banner("Large Untracked File Diff Is Not Shown"))
        })
        .when(
            !file.is_binary && !file.is_large && file.lines.is_empty(),
            |content| content.child(diff_banner("No Text Diff For This File")),
        )
        .when(!file.is_binary && !file.is_large, |content| {
            content.children(
                file.lines
                    .iter()
                    .filter(|line| !commit_diff || !line.kind.eq_ignore_ascii_case("header"))
                    .map(render_diff_line),
            )
        })
        .when(file.line_preview_truncated, |content| {
            content.child(diff_banner("Diff Line Preview Truncated"))
        })
        .when(file.truncated, |content| {
            content.child(diff_banner("File Diff Truncated For Preview"))
        })
        .into_any_element()
}

fn render_diff_line(line: &GitDiffLine) -> AnyElement {
    let kind = line.kind.to_ascii_lowercase();
    let (foreground, background) = match kind.as_str() {
        "addition" => (theme::success(), theme::diff_add_background()),
        "deletion" => (theme::danger(), theme::diff_delete_background()),
        "hunk" => (theme::warning(), theme::surface_raised()),
        _ => (theme::text_muted(), theme::transparent()),
    };
    div()
        .min_h(px(20.0))
        .px_3()
        .py(px(2.0))
        .bg(background)
        .font_family("JetBrains Mono")
        .text_size(px(12.0))
        .text_color(foreground)
        .whitespace_nowrap()
        .child(line.text.clone())
        .into_any_element()
}

fn diff_stats(file: &GitDiffFile) -> AnyElement {
    div()
        .flex()
        .items_center()
        .gap(px(6.0))
        .when(file.added.unwrap_or_default() > 0, |stats| {
            stats.child(
                div()
                    .text_xs()
                    .text_color(theme::success())
                    .child(format!("+{}", file.added.unwrap_or_default())),
            )
        })
        .when(file.removed.unwrap_or_default() > 0, |stats| {
            stats.child(
                div()
                    .text_xs()
                    .text_color(theme::danger())
                    .child(format!("-{}", file.removed.unwrap_or_default())),
            )
        })
        .into_any_element()
}

fn diff_banner(message: &'static str) -> AnyElement {
    div()
        .p_3()
        .text_sm()
        .text_color(theme::text_muted())
        .child(message)
        .into_any_element()
}

fn title_case_area(area: &str) -> &'static str {
    match area.to_ascii_lowercase().as_str() {
        "staged" => "Staged",
        "untracked" => "Untracked",
        _ => "Unstaged",
    }
}
