use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use gpui::{
    div, px, AnyElement, Context, InteractiveElement as _, IntoElement as _, ParentElement as _,
    Role, StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::scroll::ScrollableElement as _;

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::model::WorkspaceTab;
use crate::reading_diff_service::{
    ReadingDiffProgress, ReadingDiffRequest, ReadingDiffResult, ReadingDiffStage,
};
use crate::theme;

impl AleraApp {
    pub(super) fn request_git_reading_diff(
        &mut self,
        tab: &WorkspaceTab,
        ignore_cache: bool,
        cx: &mut Context<Self>,
    ) {
        let Some(scope) = self.source_control_scope_for_root(
            tab.payload
                .get("gitDiffRoot")
                .and_then(serde_json::Value::as_str),
        ) else {
            return;
        };
        let key = tab.id.clone();
        let workspace_path = scope.path.clone();
        let file_path = tab
            .payload
            .get("filePath")
            .and_then(serde_json::Value::as_str)
            .and_then(|path| scope.to_source_relative_path(path));
        let old_path = tab
            .payload
            .get("gitDiffOldPath")
            .and_then(serde_json::Value::as_str)
            .and_then(|path| scope.to_source_relative_path(path));
        let area = tab
            .payload
            .get("gitDiffArea")
            .and_then(serde_json::Value::as_str)
            .and_then(reading_diff_area);
        let commit_oid = tab
            .payload
            .get("gitDiffCommitOid")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let parent_oid = tab
            .payload
            .get("gitDiffParentOid")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let base_ref = tab
            .payload
            .get("baseRef")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        self.reading_diff_busy_key = Some(key.clone());
        self.reading_diff_progress = Some(ReadingDiffProgress {
            stage: ReadingDiffStage::Preparing,
            completed_chunks: 0,
            total_chunks: 0,
            current_chunk: None,
        });
        self.reading_diff_errors.remove(&key);
        let task = cx.background_executor().spawn(async move {
            alera_native::api::reading_diff::git_reading_diff_patch(
                workspace_path.clone(),
                file_path,
                old_path,
                area,
                commit_oid,
                parent_oid,
                base_ref,
            )
            .map(|raw_diff| (raw_diff, workspace_path))
            .map_err(|error| error.context)
        });
        cx.spawn(async move |this, cx| {
            let result = task.await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if this.reading_diff_busy_key.as_deref() != Some(&key) {
                    return;
                }
                this.reading_diff_busy_key = None;
                this.reading_diff_progress = None;
                match result {
                    Ok((raw_diff, workspace_path)) if !raw_diff.is_empty() => {
                        this.reading_diff_confirmation = Some(this.build_reading_diff_request(
                            key.clone(),
                            raw_diff,
                            workspace_path,
                            ignore_cache,
                        ));
                    }
                    Ok(_) => {
                        this.reading_diff_errors
                            .insert(key.clone(), "No Diff Is Available To Read.".into());
                    }
                    Err(error) => {
                        this.reading_diff_errors.insert(key.clone(), error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn build_reading_diff_request(
        &self,
        key: String,
        raw_diff: Vec<u8>,
        working_directory: String,
        ignore_cache: bool,
    ) -> ReadingDiffRequest {
        let prompt = self
            .settings_state
            .ai_assist_prompt_settings_by_operation
            .get("readingDiff");
        let configured_agent = prompt
            .and_then(|prompt| prompt.agent.as_deref())
            .unwrap_or(&self.settings_state.ai_assist_agent);
        let agent = match configured_agent {
            "codex" | "claude" | "copilot" | "pi" | "grok" => configured_agent,
            _ => "codex",
        }
        .to_string();
        let model = prompt
            .and_then(|prompt| prompt.model.clone())
            .filter(|model| !model.trim().is_empty())
            .or_else(|| {
                self.settings_state
                    .ai_assist_selected_model_by_agent
                    .get(&agent)
                    .cloned()
            })
            .unwrap_or_else(|| {
                super::ai_assist_settings_catalog::default_model(&agent).to_string()
            });
        let effort = self
            .settings_state
            .ai_assist_selected_thinking_by_operation
            .get("readingDiff")
            .and_then(|values| values.get(&model))
            .cloned()
            .or_else(|| {
                self.settings_state
                    .ai_assist_selected_thinking_by_model
                    .get(&model)
                    .cloned()
            });
        ReadingDiffRequest {
            key,
            raw_diff,
            working_directory,
            agent,
            model,
            effort,
            instructions: self
                .settings_state
                .ai_assist_instructions_by_operation
                .get("readingDiff")
                .cloned()
                .unwrap_or_default(),
            timeout_seconds: self.settings_state.ai_assist_timeout_seconds.max(1) as u64,
            ignore_cache,
        }
    }

    pub(super) fn confirm_reading_diff(&mut self, cx: &mut Context<Self>) {
        let Some(request) = self.reading_diff_confirmation.take() else {
            return;
        };
        if !self.settings_state.ai_assist_enabled {
            self.reading_diff_errors
                .insert(request.key, "AI Assist is disabled.".into());
            cx.notify();
            return;
        }
        let key = request.key.clone();
        let service = self.reading_diff_service.clone();
        let cancel = Arc::new(AtomicBool::new(false));
        let (progress_tx, progress_rx) = async_channel::unbounded();
        self.reading_diff_busy_key = Some(key.clone());
        self.reading_diff_progress = Some(ReadingDiffProgress {
            stage: ReadingDiffStage::Preparing,
            completed_chunks: 0,
            total_chunks: 0,
            current_chunk: None,
        });
        self.reading_diff_cancel = Some(cancel.clone());
        self.reading_diff_errors.remove(&key);
        self.reading_diff_show_original.remove(&key);
        let progress_key = key.clone();
        cx.spawn(async move |this, cx| {
            while let Ok(progress) = progress_rx.recv().await {
                let Some(this) = this.upgrade() else {
                    return;
                };
                this.update(cx, |this, cx| {
                    if this.reading_diff_busy_key.as_deref() == Some(&progress_key) {
                        this.reading_diff_progress = Some(progress);
                        cx.notify();
                    }
                });
            }
        })
        .detach();
        cx.spawn(async move |this, cx| {
            let result = service.generate(request, cancel, progress_tx).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if this.reading_diff_busy_key.as_deref() != Some(&key) {
                    return;
                }
                this.reading_diff_busy_key = None;
                this.reading_diff_progress = None;
                this.reading_diff_cancel = None;
                match result {
                    Ok(result) => {
                        this.reading_diff_results.insert(key.clone(), result);
                        this.reading_diff_errors.remove(&key);
                    }
                    Err(error) if error.contains("Canceled") => {
                        this.local_message = Some("Reading Diff Generation Canceled".into());
                    }
                    Err(error) => {
                        this.reading_diff_errors.insert(key.clone(), error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn cancel_reading_diff(&mut self, cx: &mut Context<Self>) {
        if let Some(cancel) = self.reading_diff_cancel.take() {
            cancel.store(true, Ordering::Relaxed);
        }
        cx.notify();
    }

    pub(super) fn dismiss_reading_diff_confirmation(&mut self, cx: &mut Context<Self>) {
        self.reading_diff_confirmation = None;
        cx.notify();
    }

    pub(super) fn toggle_reading_diff_original(&mut self, key: String, cx: &mut Context<Self>) {
        if !self.reading_diff_show_original.remove(&key) {
            self.reading_diff_show_original.insert(key);
        }
        cx.notify();
    }

    pub(super) fn reading_diff_visible(&self, key: &str) -> bool {
        (self.reading_diff_busy_key.as_deref() == Some(key)
            || self.reading_diff_results.contains_key(key)
            || self.reading_diff_errors.contains_key(key))
            && !self.reading_diff_show_original.contains(key)
    }

    pub(super) fn render_reading_diff_content(
        &self,
        key: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        if self.reading_diff_busy_key.as_deref() == Some(key) {
            let progress = self.reading_diff_progress.as_ref();
            let label = progress.map_or_else(
                || "Preparing Reading Diff".to_string(),
                reading_diff_progress_label,
            );
            return div()
                .flex()
                .flex_col()
                .flex_1()
                .items_center()
                .justify_center()
                .gap_3()
                .child(loading_indicator(22.0, theme::text_muted()))
                .child(div().text_size(crate::theme::body_size()).text_color(theme::text_muted()).child(label))
                .child(
                    design_system::button(
                        "cancel-reading-diff",
                        "Cancel",
                        ButtonKind::Outlined,
                        false,
                    )
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.cancel_reading_diff(cx);
                    })),
                )
                .into_any_element();
        }
        if let Some(error) = self.reading_diff_errors.get(key) {
            return div()
                .flex()
                .flex_col()
                .flex_1()
                .items_center()
                .justify_center()
                .gap_2()
                .px_5()
                .child(icon(AleraIcon::Error, 22.0, theme::danger()))
                .child(
                    div()
                        .text_size(crate::theme::body_size())
                        .text_color(theme::text_muted())
                        .child(error.clone()),
                )
                .into_any_element();
        }
        let Some(result) = self.reading_diff_results.get(key) else {
            return div().into_any_element();
        };
        render_reading_diff_result(result)
    }

    pub(super) fn render_reading_diff_confirmation(
        &self,
        key: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let Some(request) = self
            .reading_diff_confirmation
            .as_ref()
            .filter(|request| request.key == key)
        else {
            return div().into_any_element();
        };
        let bytes = request.raw_diff.len();
        div()
            .absolute()
            .inset_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.dismiss_reading_diff_confirmation(cx);
                }),
            )
            .child(
                div()
                    .id("reading-diff-confirmation")
                    .role(Role::Dialog)
                    .aria_label("Generate AI Reading Diff")
                    .w(px(440.0))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .p_5()
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| cx.stop_propagation())
                    .child(
                        div()
                            .text_size(px(15.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Generate AI Reading Diff?"),
                    )
                    .child(
                        div()
                            .mt_3()
                            .text_size(crate::theme::body_size())
                            .text_color(theme::text_muted())
                            .child(format!(
                                "{} will receive only this {} diff through a restricted, tool-free execution policy. The result cannot be applied to the repository.",
                                reading_diff_agent_label(&request.agent),
                                format_bytes(bytes),
                            )),
                    )
                    .child(
                        div()
                            .mt_5()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .child(
                                design_system::button(
                                    "cancel-reading-diff-confirmation",
                                    "Cancel",
                                    ButtonKind::Text,
                                    false,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.dismiss_reading_diff_confirmation(cx);
                                })),
                            )
                            .child(
                                design_system::button(
                                    "confirm-reading-diff",
                                    "Generate",
                                    ButtonKind::Filled,
                                    false,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.confirm_reading_diff(cx);
                                })),
                            ),
                    ),
            )
            .into_any_element()
    }
}

fn reading_diff_area(area: &str) -> Option<alera_native::api::git::GitChangeArea> {
    match area {
        "untracked" => Some(alera_native::api::git::GitChangeArea::Untracked),
        "unstaged" => Some(alera_native::api::git::GitChangeArea::Unstaged),
        "staged" => Some(alera_native::api::git::GitChangeArea::Staged),
        _ => None,
    }
}

fn render_reading_diff_result(result: &ReadingDiffResult) -> AnyElement {
    let retained = result
        .retained_changed_lines
        .saturating_mul(100)
        .checked_div(result.changed_lines)
        .unwrap_or(100);
    div()
        .flex()
        .flex_col()
        .flex_1()
        .min_h_0()
        .child(
            div()
                .p_3()
                .border_b_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_selected())
                .child(
                    div()
                        .text_size(crate::theme::body_size())
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(result.summary.clone()),
                )
                .child(
                    div()
                        .mt_1()
                        .text_size(crate::theme::caption_size())
                        .text_color(theme::text_muted())
                        .child(format!(
                            "{} · {}{} · {retained}% of changed lines retained · {} chunk{}{}",
                            result.agent_label,
                            result.model,
                            result
                                .effort
                                .as_deref()
                                .map(|effort| format!(" · {effort}"))
                                .unwrap_or_default(),
                            result.chunk_count,
                            if result.chunk_count == 1 { "" } else { "s" },
                            if result.from_cache { " · Cached" } else { "" },
                        )),
                ),
        )
        .child(
            div().flex_1().min_h_0().overflow_y_scrollbar().children(
                String::from_utf8_lossy(&result.diff)
                    .lines()
                    .map(render_reading_diff_line),
            ),
        )
        .into_any_element()
}

fn render_reading_diff_line(line: &str) -> gpui::Div {
    let color = if line.starts_with('+') && !line.starts_with("+++") {
        theme::success()
    } else if line.starts_with('-') && !line.starts_with("---") {
        theme::danger()
    } else if line.starts_with("@@") {
        theme::info()
    } else {
        theme::text_muted()
    };
    div()
        .px_3()
        .min_h(px(18.0))
        .font_family("JetBrains Mono")
        .text_size(px(12.0))
        .text_color(color)
        .child(line.to_string())
}

fn reading_diff_progress_label(progress: &ReadingDiffProgress) -> String {
    match progress.stage {
        ReadingDiffStage::Preparing => "Preparing Reading Diff".to_string(),
        ReadingDiffStage::Generating => format!(
            "Generating Chunk {} of {}",
            progress.current_chunk.unwrap_or(1),
            progress.total_chunks
        ),
        ReadingDiffStage::Repairing => format!(
            "Repairing Chunk {} of {}",
            progress.current_chunk.unwrap_or(1),
            progress.total_chunks
        ),
        ReadingDiffStage::Combining => format!(
            "Combining {} Reading Diff Chunk{}",
            progress.completed_chunks,
            if progress.completed_chunks == 1 {
                ""
            } else {
                "s"
            },
        ),
        ReadingDiffStage::Cached => "Loading Cached Reading Diff".to_string(),
    }
}

fn reading_diff_agent_label(agent: &str) -> &'static str {
    match agent {
        "claude" => "Claude Code",
        "copilot" => "GitHub Copilot",
        "pi" => "Pi",
        "grok" => "Grok Build",
        _ => "Codex",
    }
}

fn format_bytes(bytes: usize) -> String {
    if bytes >= 1024 * 1024 {
        format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
    } else if bytes >= 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else {
        format!("{bytes} B")
    }
}
