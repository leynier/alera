use gpui::{
    div, px, AnyElement, Context, CursorStyle, InteractiveElement as _, IntoElement,
    ParentElement as _, SharedString, StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::text::TextView;

use super::forge_surface::resolve_forge_identity;
use super::AleraApp;
use crate::design_system;
use crate::forge_api::{ForgeAction, ForgeComment};

impl AleraApp {
    pub(super) fn render_review_comment_body(
        &self,
        comment: &ForgeComment,
        comment_id: &str,
        editable: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let tasks = find_review_comment_tasks(&comment.body);
        if tasks.is_empty() {
            return TextView::markdown(
                SharedString::from(format!("context-pr-comment-body-{comment_id}")),
                super::context_pull_request::normalize_review_comment_markdown(&comment.body),
            )
            .selectable(true)
            .into_any_element();
        }
        let lines = comment.body.split('\n').collect::<Vec<_>>();
        let mut task_by_line = std::collections::BTreeMap::new();
        for (index, task) in tasks.iter().cloned().enumerate() {
            task_by_line.insert(task.line_index, (index, task));
        }
        let mut rendered_lines = Vec::with_capacity(lines.len());
        for (line_index, line) in lines.into_iter().enumerate() {
            let rendered = if let Some((task_index, task)) = task_by_line.get(&line_index) {
                let task_index = *task_index;
                let task = task.clone();
                let comment_id = comment_id.to_owned();
                let enabled =
                    editable && !self.forge_comment_saving_ids.contains(comment_id.as_str());
                let line_text = line
                    .get(task.label_offset..)
                    .unwrap_or_default()
                    .trim()
                    .to_owned();
                let item_id = format!("context-pr-comment-task-{comment_id}-{task_index}");
                let comment_id_for_click = comment_id.clone();
                div()
                    .id(SharedString::from(item_id))
                    .flex()
                    .items_start()
                    .gap_1()
                    .child(
                        design_system::checkbox(task.checked, enabled, None)
                            .id(SharedString::from(format!(
                                "context-pr-comment-task-checkbox-{comment_id}-{task_index}"
                            )))
                            .cursor(if enabled {
                                CursorStyle::PointingHand
                            } else {
                                CursorStyle::Arrow
                            })
                            .on_click(cx.listener(move |this, _, window, cx| {
                                if enabled {
                                    this.toggle_pull_request_comment_task(
                                        comment_id_for_click.clone(),
                                        task_index,
                                        window,
                                        cx,
                                    );
                                }
                                cx.stop_propagation();
                            })),
                    )
                    .child(
                        TextView::markdown(
                            SharedString::from(format!(
                                "context-pr-comment-task-text-{comment_id}-{task_index}"
                            )),
                            line_text,
                        )
                        .selectable(true),
                    )
                    .into_any_element()
            } else if line.trim().is_empty() {
                div().h(px(6.0)).into_any_element()
            } else {
                TextView::markdown(
                    SharedString::from(format!(
                        "context-pr-comment-line-{comment_id}-{line_index}"
                    )),
                    super::context_pull_request::normalize_review_comment_markdown(line),
                )
                .selectable(true)
                .into_any_element()
            };
            rendered_lines.push(rendered);
        }
        div()
            .id(SharedString::from(format!(
                "context-pr-comment-body-{comment_id}"
            )))
            .flex()
            .flex_col()
            .gap_1()
            .children(rendered_lines)
            .into_any_element()
    }

    pub(super) fn toggle_pull_request_comment_task(
        &mut self,
        comment_id: String,
        task_index: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.forge_busy || self.forge_comment_saving_ids.contains(&comment_id) {
            return;
        }
        let Some(review) = self.forge_snapshot.review.clone() else {
            return;
        };
        if !review.state.eq_ignore_ascii_case("open") {
            return;
        }
        let Some(comment_index) = self
            .forge_snapshot
            .comments
            .iter()
            .position(|comment| comment._id == comment_id)
        else {
            return;
        };
        let original_body = self.forge_snapshot.comments[comment_index].body.clone();
        let Some(changed_body) = toggle_review_comment_task_list_item(&original_body, task_index)
        else {
            return;
        };
        let source = self.forge_snapshot.comments[comment_index].source;
        let workspace_path = self.selected_source_control_path();
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let project_id = self
            .snapshot
            .project_for_workspace(&workspace_id)
            .map(|project| project.id.clone());
        let Some(workspace_path) = workspace_path else {
            return;
        };
        self.forge_snapshot.comments[comment_index].body = changed_body.clone();
        self.forge_comment_saving_ids.insert(comment_id.clone());
        self.forge_generation = self.forge_generation.wrapping_add(1);
        let generation = self.forge_generation;
        let bridge = self.bridge.clone();
        let service = self.forge_service.clone();
        let comments_workspace = self.workspace_service.clone();
        let action = ForgeAction::UpdateComment {
            number: review.number,
            comment_id: comment_id.clone(),
            source,
            body: changed_body,
        };
        cx.spawn_in(window, async move |this, cx| {
            let result = async {
                let identity = resolve_forge_identity(
                    &bridge,
                    &comments_workspace,
                    &workspace_id,
                    &workspace_path,
                    project_id.as_deref(),
                )
                .await
                .map_err(|reason| format!("Forge unavailable: {reason:?}"))?;
                service.action(workspace_path, identity, action).await
            }
            .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, move |this, _, cx| {
                this.forge_comment_saving_ids.remove(&comment_id);
                if generation != this.forge_generation {
                    return;
                }
                match result {
                    Ok(message) => {
                        this.local_message = Some(message.into());
                        this.refresh_forge(cx);
                    }
                    Err(error) => {
                        if let Some(comment) = this
                            .forge_snapshot
                            .comments
                            .iter_mut()
                            .find(|comment| comment._id == comment_id)
                        {
                            comment.body = original_body;
                        }
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
        cx.notify();
    }
}

#[derive(Clone, Debug)]
pub(super) struct ReviewCommentTaskItem {
    pub(super) line_index: usize,
    pub(super) marker_offset: usize,
    pub(super) label_offset: usize,
    pub(super) checked: bool,
}

fn find_review_comment_tasks(body: &str) -> Vec<ReviewCommentTaskItem> {
    let mut result = Vec::new();
    let mut offset = 0usize;
    let mut fence: Option<(u8, usize)> = None;
    for (line_index, raw_line) in body.split('\n').enumerate() {
        let line = raw_line.strip_suffix('\r').unwrap_or(raw_line);
        if let Some((character, length)) = fence {
            if let Some((close_character, close_length)) = fenced_line(line) {
                if close_character == character
                    && close_length >= length
                    && line[close_length..].trim().is_empty()
                {
                    fence = None;
                }
            }
            offset += raw_line.len() + 1;
            continue;
        }
        if let Some(marker) = fenced_line(line) {
            fence = Some(marker);
            offset += raw_line.len() + 1;
            continue;
        }
        if let Some((marker_offset, label_offset, checked)) = task_line(line) {
            result.push(ReviewCommentTaskItem {
                line_index,
                marker_offset: offset + marker_offset,
                label_offset,
                checked,
            });
        }
        offset += raw_line.len() + 1;
    }
    result
}

fn task_line(line: &str) -> Option<(usize, usize, bool)> {
    let bytes = line.as_bytes();
    let mut index = 0usize;
    while index < bytes.len() && bytes[index] == b' ' && index < 3 {
        index += 1;
    }
    loop {
        if bytes.get(index) == Some(&b'>') {
            index += 1;
            while bytes.get(index) == Some(&b' ') || bytes.get(index) == Some(&b'\t') {
                index += 1;
            }
        } else {
            break;
        }
    }
    if matches!(bytes.get(index), Some(b'-' | b'*' | b'+')) {
        index += 1;
        if !matches!(bytes.get(index), Some(b' ' | b'\t')) {
            return None;
        }
        while matches!(bytes.get(index), Some(b' ' | b'\t')) {
            index += 1;
        }
    } else {
        let start = index;
        while bytes.get(index).is_some_and(u8::is_ascii_digit) {
            index += 1;
        }
        if index > start && matches!(bytes.get(index), Some(b'.' | b')')) {
            index += 1;
            if !matches!(bytes.get(index), Some(b' ' | b'\t')) {
                return None;
            }
            while matches!(bytes.get(index), Some(b' ' | b'\t')) {
                index += 1;
            }
        } else {
            index = start;
        }
    }
    if bytes.get(index) != Some(&b'[') || bytes.get(index + 2) != Some(&b']') {
        return None;
    }
    let checked = matches!(bytes.get(index + 1), Some(b'x' | b'X'));
    if !checked && bytes.get(index + 1) != Some(&b' ') {
        return None;
    }
    let label_offset = index + 3;
    if !matches!(bytes.get(label_offset), Some(b' ' | b'\t')) {
        return None;
    }
    let mut label_offset = label_offset;
    while matches!(bytes.get(label_offset), Some(b' ' | b'\t')) {
        label_offset += 1;
    }
    (label_offset < bytes.len()).then_some((index + 1, label_offset, checked))
}

fn fenced_line(line: &str) -> Option<(u8, usize)> {
    let trimmed = line.trim_start_matches([' ', '\t']);
    let bytes = trimmed.as_bytes();
    let character = *bytes.first()?;
    if character != b'`' && character != b'~' {
        return None;
    }
    let length = bytes
        .iter()
        .take_while(|value| **value == character)
        .count();
    (length >= 3).then_some((character, length))
}

fn toggle_review_comment_task_list_item(body: &str, item_index: usize) -> Option<String> {
    let items = find_review_comment_tasks(body);
    let item = items.get(item_index)?;
    let mut bytes = body.as_bytes().to_vec();
    bytes[item.marker_offset] = if item.checked { b' ' } else { b'x' };
    String::from_utf8(bytes).ok()
}

#[cfg(test)]
mod tests {
    use super::{find_review_comment_tasks, toggle_review_comment_task_list_item};

    #[test]
    fn finds_and_toggles_tasks_outside_fences() {
        let body = "- [ ] first\n```\n- [ ] ignored\n```\n> 1. [x] second";
        let items = find_review_comment_tasks(body);
        assert_eq!(items.len(), 2);
        assert_eq!(
            toggle_review_comment_task_list_item(body, 0).unwrap(),
            "- [x] first\n```\n- [ ] ignored\n```\n> 1. [x] second"
        );
    }
}
