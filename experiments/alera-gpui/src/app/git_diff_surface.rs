use std::path::Path;
use std::sync::Arc;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle, Image, ImageFormat,
    InteractiveElement as _, IntoElement, ParentElement as _, SharedString,
    StatefulInteractiveElement as _, Styled as _,
};

use super::AleraApp;
use crate::file_icons::file_icon;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::model::WorkspaceTab;
use crate::theme;
use crate::workspace_git::{GitDiffFile, GitDiffLine};

#[derive(Clone, Debug)]
pub(super) struct GitDiffImageSide {
    pub(super) image: Arc<Image>,
    pub(super) bytes_len: usize,
}

#[derive(Clone, Debug, Default)]
pub(super) struct GitDiffImageSides {
    pub(super) old: Option<GitDiffImageSide>,
    pub(super) new: Option<GitDiffImageSide>,
}

impl AleraApp {
    pub(super) fn render_git_diff_surface(
        &self,
        tab: &WorkspaceTab,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let loading = self.git_diff_loading_tab.as_deref() == Some(tab.id.as_str());
        let loaded = self.git_diff_loaded_tab.as_deref() == Some(tab.id.as_str());
        let error = self.git_diff_errors.get(&tab.id).cloned();
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
        let show_reading_diff = self.reading_diff_visible(&tab.id);
        let has_reading_diff = self.reading_diff_results.contains_key(&tab.id)
            || self.reading_diff_errors.contains_key(&tab.id);
        let reading_key = tab.id.clone();
        let reading_tab = tab.clone();
        div()
            .relative()
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
                            .id("git-diff-read-ai")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .cursor(if loading || !loaded || self.git_diff.files.is_empty() {
                                CursorStyle::Arrow
                            } else {
                                CursorStyle::PointingHand
                            })
                            .when(
                                !loading && loaded && !self.git_diff.files.is_empty(),
                                |button| {
                                    button
                                        .hover(|style| style.bg(theme::surface_raised()))
                                        .on_mouse_down(
                                            gpui::MouseButton::Left,
                                            cx.listener(move |this, _, _, cx| {
                                                this.request_git_reading_diff(
                                                    &reading_tab,
                                                    false,
                                                    cx,
                                                );
                                            }),
                                        )
                                },
                            )
                            .child(icon(AleraIcon::Ai, 16.0, theme::text_muted())),
                    )
                    .when(has_reading_diff, |header| {
                        header.child(
                            div()
                                .id("git-diff-toggle-reading")
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
                                        this.toggle_reading_diff_original(reading_key.clone(), cx);
                                    }),
                                )
                                .child(icon(
                                    if show_reading_diff {
                                        AleraIcon::Diff
                                    } else {
                                        AleraIcon::Ai
                                    },
                                    16.0,
                                    theme::text_muted(),
                                )),
                        )
                    })
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
                    .when(show_reading_diff, |content| {
                        content.child(self.render_reading_diff_content(&tab.id, cx))
                    })
                    .when(!show_reading_diff && loading && !loaded, |content| {
                        content
                            .items_center()
                            .justify_center()
                            .text_color(theme::text_muted())
                            .child(loading_indicator(20.0, theme::text_muted()))
                    })
                    .when(
                        !show_reading_diff && !loading && error.is_some(),
                        |content| {
                            content
                                .items_center()
                                .justify_center()
                                .text_size(crate::theme::body_size())
                                .text_color(theme::text_muted())
                                .child("Could not load diff.")
                        },
                    )
                    .when(
                        !show_reading_diff
                            && !loading
                            && error.is_none()
                            && loaded
                            && self.git_diff.files.is_empty(),
                        |content| {
                            content
                                .items_center()
                                .justify_center()
                                .text_size(crate::theme::body_size())
                                .text_color(theme::text_muted())
                                .child("No diff available.")
                        },
                    )
                    .when(
                        !show_reading_diff
                            && !loading
                            && error.is_none()
                            && loaded
                            && !self.git_diff.files.is_empty(),
                        |content| {
                            content
                                .when(self.git_diff.truncated, |content| {
                                    content.child(diff_banner("Diff truncated for preview."))
                                })
                                .children(
                                    self.git_diff.files.iter().map(|file| {
                                        self.render_diff_file(&tab.id, file, commit_diff)
                                    }),
                                )
                        },
                    ),
            )
            .child(self.render_reading_diff_confirmation(&tab.id, cx))
            .into_any_element()
    }
}

impl AleraApp {
    fn render_diff_file(&self, tab_id: &str, file: &GitDiffFile, commit_diff: bool) -> AnyElement {
        let image_key = (tab_id.to_owned(), file.path.clone());
        let image_preview = file.is_binary && is_image_path(&file.path);
        let image_sides = self.git_diff_image_sides.get(&image_key);
        let image_loading = self.git_diff_image_loading.contains(&image_key);
        div()
            .flex()
            .flex_col()
            .child(
                div()
                    .id(SharedString::from(format!(
                        "git-diff-file-{}-{}",
                        file.area, file.path
                    )))
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
            .when(file.is_binary && !image_preview, |content| {
                content.child(diff_banner("Binary file diff is not shown."))
            })
            .when(image_preview, |content| {
                content.child(render_image_diff_row(file, image_sides, image_loading))
            })
            .when(!file.is_binary && file.is_large, |content| {
                content.child(diff_banner("Large untracked file diff is not shown."))
            })
            .when(
                !file.is_binary && !file.is_large && file.lines.is_empty(),
                |content| content.child(diff_banner("No text diff for this file.")),
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
                content.child(diff_banner("Diff line preview truncated."))
            })
            .when(file.truncated, |content| {
                content.child(diff_banner("File diff truncated for preview."))
            })
            .into_any_element()
    }
}

pub(super) fn is_image_path(path: &str) -> bool {
    matches!(
        Path::new(path)
            .extension()
            .and_then(|extension| extension.to_str())
            .map(|extension| extension.to_ascii_lowercase())
            .as_deref(),
        Some("png" | "jpg" | "jpeg" | "webp" | "gif" | "svg" | "bmp" | "tif" | "tiff")
    )
}

fn render_image_diff_row(
    file: &GitDiffFile,
    sides: Option<&GitDiffImageSides>,
    loading: bool,
) -> AnyElement {
    let old_placeholder = if matches!(
        file.status.to_ascii_lowercase().as_str(),
        "added" | "untracked"
    ) {
        "Added"
    } else {
        "Preview Unavailable"
    };
    let new_placeholder = if file.status.eq_ignore_ascii_case("deleted") {
        "Deleted"
    } else {
        "Preview Unavailable"
    };
    div()
        .flex()
        .gap(px(8.0))
        .px_3()
        .py_2()
        .child(render_image_diff_side(
            "Before",
            sides.and_then(|sides| sides.old.as_ref()),
            old_placeholder,
            loading,
        ))
        .child(render_image_diff_side(
            "After",
            sides.and_then(|sides| sides.new.as_ref()),
            new_placeholder,
            loading,
        ))
        .into_any_element()
}

fn render_image_diff_side(
    label: &'static str,
    side: Option<&GitDiffImageSide>,
    placeholder: &'static str,
    loading: bool,
) -> AnyElement {
    let title = side.map_or_else(
        || label.to_owned(),
        |side| format!("{label} · {}", format_image_bytes(side.bytes_len)),
    );
    div()
        .flex_1()
        .min_w_0()
        .child(div().text_size(crate::theme::caption_size()).text_color(theme::text_faint()).child(title))
        .child(
            div()
                .h(px(180.0))
                .w_full()
                .flex()
                .items_center()
                .justify_center()
                .rounded_md()
                .border_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_raised())
                .overflow_hidden()
                .when_some(side.map(|side| side.image.clone()), |cell, image| {
                    cell.child(gpui::img(image).size_full())
                })
                .when(side.is_none() && loading, |cell| {
                    cell.child(crate::icons::loading_indicator(18.0, theme::text_muted()))
                })
                .when(side.is_none() && !loading, |cell| {
                    cell.child(
                        div()
                            .text_size(crate::theme::body_size())
                            .text_color(theme::text_faint())
                            .child(placeholder),
                    )
                }),
        )
        .into_any_element()
}

fn format_image_bytes(bytes: usize) -> String {
    if bytes < 1024 {
        return format!("{bytes} B");
    }
    if bytes < 1024 * 1024 {
        return format!("{:.1} KB", bytes as f64 / 1024.0);
    }
    format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
}

pub(super) fn to_git_diff_image_side(
    image: crate::workspace_service::WorkspaceImage,
) -> Option<GitDiffImageSide> {
    let format = match image.format.to_ascii_lowercase().as_str() {
        "png" => ImageFormat::Png,
        "jpeg" | "jpg" => ImageFormat::Jpeg,
        "webp" => ImageFormat::Webp,
        "gif" => ImageFormat::Gif,
        "svg" => ImageFormat::Svg,
        "bmp" => ImageFormat::Bmp,
        "tiff" | "tif" => ImageFormat::Tiff,
        _ => return None,
    };
    let bytes_len = image.bytes.len();
    Some(GitDiffImageSide {
        image: Arc::new(Image::from_bytes(format, image.bytes)),
        bytes_len,
    })
}

fn render_diff_line(line: &GitDiffLine) -> AnyElement {
    let kind = line.kind.to_ascii_lowercase();
    // Flutter renders every GitDiffLine with maxLines: 1. libgit2 can place
    // several file-header records in one line payload, so showing the raw
    // newlines here exposed mode metadata that the reference clips.
    let visible_text = line.text.lines().next().unwrap_or_default().to_owned();
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
        .child(visible_text)
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
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::success())
                    .child(format!("+{}", file.added.unwrap_or_default())),
            )
        })
        .when(file.removed.unwrap_or_default() > 0, |stats| {
            stats.child(
                div()
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::danger())
                    .child(format!("-{}", file.removed.unwrap_or_default())),
            )
        })
        .into_any_element()
}

fn diff_banner(message: &'static str) -> AnyElement {
    div()
        .p_3()
        .text_size(crate::theme::body_size())
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
