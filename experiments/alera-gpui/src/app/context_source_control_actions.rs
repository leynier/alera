use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement, KeyDownEvent, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::tooltip::Tooltip;

use super::context_source_control_dialog::SourceControlDialog;
use super::git_surface::friendly_git_error;
use super::AleraApp;
use crate::icons::{icon, AleraIcon};
use crate::theme;
use crate::workspace_git::GitAction;

#[derive(Clone, Copy)]
pub(super) enum SourceControlAction {
    Commit,
    CommitPush,
    CommitSync,
    Amend,
    StageAll,
    UnstageAll,
    DiscardAll,
    Fetch,
    Pull,
    Push,
    Sync,
    PublishBranch,
    Stash,
    StashPop,
}

#[derive(Clone, Copy)]
struct SourceControlMenuEntry {
    action: SourceControlAction,
    label: &'static str,
    enabled: bool,
    separator_before: bool,
}

impl AleraApp {
    pub(super) fn source_control_menu(&self, cx: &mut Context<Self>) -> AnyElement {
        let entries = self.source_control_menu_entries();
        div()
            .id("source-action-menu")
            .track_focus(&self.source_control_menu_focus)
            .role(Role::Menu)
            .aria_label("Source Control Actions")
            .absolute()
            // Anchor the popup to the top edge of the primary action. The
            // panel root starts above the toolbar, so 121 px aligns with
            // Flutter's `showMenu` position instead of floating over the
            // commit field.
            .top(px(121.0))
            .right(px(8.0))
            .w(px(174.0))
            .occlude()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .py_1()
            .on_mouse_down_out(cx.listener(|this, _, window, cx| {
                this.dismiss_source_control_menu(window, cx);
            }))
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                this.handle_source_control_menu_key(event, window, cx);
            }))
            .children(entries.into_iter().enumerate().map(|(index, entry)| {
                let icon_color = if !entry.enabled {
                    theme::text_faint()
                } else if matches!(entry.action, SourceControlAction::DiscardAll) {
                    theme::danger()
                } else {
                    theme::text_muted()
                };
                div()
                    .flex()
                    .flex_col()
                    .when(entry.separator_before, |group| {
                        group.child(
                            div()
                                .h(px(5.0))
                                .mt_1()
                                .border_t_1()
                                .border_color(theme::border_subtle()),
                        )
                    })
                    .child(
                        div()
                            .id(("source-menu-action", index))
                            .focusable()
                            .tab_stop(entry.enabled)
                            .role(Role::MenuItem)
                            .aria_label(entry.label)
                            .aria_selected(
                                entry.enabled && self.source_control_menu_highlighted == index,
                            )
                            .flex()
                            .items_center()
                            .h(px(28.0))
                            .px_2()
                            .gap_2()
                            .text_size(px(13.0))
                            .text_color(if entry.enabled {
                                theme::text()
                            } else {
                                theme::text_faint()
                            })
                            .when(
                                entry.enabled && self.source_control_menu_highlighted == index,
                                |row| row.bg(theme::surface_selected()),
                            )
                            .when(entry.enabled, |row| {
                                row.cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_selected()))
                                    .on_click(cx.listener(move |this, _, window, cx| {
                                        this.dismiss_source_control_menu(window, cx);
                                        this.run_source_control_action(entry.action, window, cx);
                                    }))
                            })
                            .child(icon(source_action_icon(entry.action), 16.0, icon_color))
                            .child(entry.label),
                    )
            }))
            .into_any_element()
    }

    pub(super) fn toggle_source_control_menu(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.source_control_menu_open {
            self.dismiss_source_control_menu(window, cx);
            return;
        }
        self.source_control_menu_open = true;
        self.source_control_menu_previous_focus = window.focused(cx);
        self.source_control_menu_highlighted = self
            .source_control_menu_enabled_indices()
            .first()
            .copied()
            .unwrap_or(0);
        self.source_control_menu_focus.focus(window, cx);
        cx.notify();
    }

    fn dismiss_source_control_menu(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.source_control_menu_open = false;
        if let Some(focus) = self.source_control_menu_previous_focus.take() {
            focus.focus(window, cx);
        }
        cx.notify();
    }

    fn source_control_menu_enabled_indices(&self) -> Vec<usize> {
        self.source_control_menu_entries()
            .into_iter()
            .enumerate()
            .filter_map(|(index, entry)| entry.enabled.then_some(index))
            .collect()
    }

    fn handle_source_control_menu_key(
        &mut self,
        event: &KeyDownEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let key = event.keystroke.key.as_str();
        if key == "escape" {
            self.dismiss_source_control_menu(window, cx);
            cx.stop_propagation();
            return;
        }
        let enabled = self.source_control_menu_enabled_indices();
        if enabled.is_empty() {
            return;
        }
        if matches!(key, "enter" | "space") {
            let Some(entry) = self
                .source_control_menu_entries()
                .get(self.source_control_menu_highlighted)
                .copied()
                .filter(|entry| entry.enabled)
            else {
                return;
            };
            self.dismiss_source_control_menu(window, cx);
            self.run_source_control_action(entry.action, window, cx);
            cx.stop_propagation();
            return;
        }
        let current = enabled
            .iter()
            .position(|index| *index == self.source_control_menu_highlighted)
            .unwrap_or(0);
        let next = match key {
            "down" => (current + 1) % enabled.len(),
            "up" => (current + enabled.len() - 1) % enabled.len(),
            "home" => 0,
            "end" => enabled.len() - 1,
            _ => return,
        };
        self.source_control_menu_highlighted = enabled[next];
        cx.notify();
        cx.stop_propagation();
    }

    fn source_control_menu_entries(&self) -> Vec<SourceControlMenuEntry> {
        let has_staged = self
            .git_snapshot
            .changes
            .iter()
            .any(|change| change.area.eq_ignore_ascii_case("staged"));
        let has_stageable = self.git_snapshot.changes.iter().any(|change| {
            change.area.eq_ignore_ascii_case("unstaged")
                || change.area.eq_ignore_ascii_case("untracked")
        });
        let has_discardable = self
            .git_snapshot
            .changes
            .iter()
            .any(|change| !change.area.eq_ignore_ascii_case("staged"));
        let has_upstream = self.git_snapshot.upstream.is_some();
        let has_conflicts = self.git_snapshot.has_conflicts;
        let can_publish = !has_upstream && self.git_snapshot.branch != "HEAD";
        // Flutter keeps every action disabled until the async provider has
        // produced data. GPUI's default snapshot is empty and has no error,
        // so checking only the error flag briefly enabled Fetch/Pull while a
        // refresh was still in flight.
        let has_snapshot =
            !self.git_busy && !self.git_snapshot_loading && self.git_snapshot_error.is_none();
        [
            (
                SourceControlAction::Commit,
                has_snapshot && has_staged && !has_conflicts,
                false,
            ),
            (
                SourceControlAction::CommitPush,
                has_snapshot && has_staged && !has_conflicts,
                false,
            ),
            (
                SourceControlAction::CommitSync,
                has_snapshot && has_staged && !has_conflicts && has_upstream,
                false,
            ),
            (
                SourceControlAction::Amend,
                has_snapshot
                    && has_staged
                    && !has_conflicts
                    && self.git_snapshot.head_message.is_some(),
                false,
            ),
            (
                SourceControlAction::StageAll,
                has_snapshot && has_stageable,
                true,
            ),
            (
                SourceControlAction::UnstageAll,
                has_snapshot && has_staged,
                false,
            ),
            (
                SourceControlAction::DiscardAll,
                has_snapshot && has_discardable,
                false,
            ),
            (SourceControlAction::Fetch, has_snapshot, true),
            (SourceControlAction::Pull, has_snapshot, false),
            (
                SourceControlAction::Push,
                has_snapshot && !has_conflicts,
                false,
            ),
            (
                SourceControlAction::Sync,
                has_snapshot && !has_conflicts && has_upstream,
                false,
            ),
            (
                SourceControlAction::PublishBranch,
                has_snapshot && can_publish,
                false,
            ),
            (
                SourceControlAction::Stash,
                has_snapshot && has_discardable,
                true,
            ),
            (
                SourceControlAction::StashPop,
                has_snapshot && !self.git_snapshot.stashes.is_empty(),
                false,
            ),
        ]
        .into_iter()
        .map(
            |(action, enabled, separator_before)| SourceControlMenuEntry {
                action,
                label: source_action_label(action),
                enabled,
                separator_before,
            },
        )
        .collect()
    }

    pub(super) fn run_source_control_action(
        &mut self,
        action: SourceControlAction,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match action {
            SourceControlAction::Commit => self.commit_with_follow_up(None, window, cx),
            SourceControlAction::CommitPush => {
                self.commit_with_follow_up(Some(GitAction::Push), window, cx)
            }
            SourceControlAction::CommitSync => {
                self.commit_with_follow_up(Some(GitAction::Sync), window, cx)
            }
            SourceControlAction::Amend => {
                let Some(message) = self
                    .git_snapshot
                    .head_message
                    .clone()
                    .filter(|message| !message.trim().is_empty())
                else {
                    return;
                };
                self.source_amend_input
                    .update(cx, |input, cx| input.set_value(message, window, cx));
                self.source_control_dialog = Some(SourceControlDialog::Amend);
                cx.notify();
            }
            SourceControlAction::StageAll => self.run_git_action(GitAction::StageAll, cx),
            SourceControlAction::UnstageAll => self.run_git_action(GitAction::UnstageAll, cx),
            SourceControlAction::DiscardAll => self.request_discard_all(cx),
            SourceControlAction::Fetch => self.run_git_action(GitAction::Fetch, cx),
            SourceControlAction::Pull => self.run_git_action(GitAction::Pull, cx),
            SourceControlAction::Push => {
                self.run_git_action(GitAction::Push, cx);
            }
            SourceControlAction::PublishBranch => {
                self.run_git_action_with_success(GitAction::Push, "Branch published", cx)
            }
            SourceControlAction::Sync => self.run_git_action(GitAction::Sync, cx),
            SourceControlAction::Stash => self.run_git_action(GitAction::Stash, cx),
            SourceControlAction::StashPop => {
                if self.git_snapshot.stashes.is_empty() {
                    self.local_message = Some("No Stashes Are Available".into());
                    cx.notify();
                } else {
                    self.source_control_dialog = Some(SourceControlDialog::StashPicker);
                    cx.notify();
                }
            }
        }
    }

    fn commit_with_follow_up(
        &mut self,
        follow_up: Option<GitAction>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let message = self.commit_input.read(cx).value().trim().to_owned();
        if message.is_empty() {
            self.local_message = Some("Enter A Commit Message".into());
            cx.notify();
            return;
        }
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        self.git_generation += 1;
        let generation = self.git_generation;
        self.git_busy = true;
        let success_message = match follow_up.as_ref() {
            Some(GitAction::Push) => "Committed and pushed",
            Some(GitAction::Sync) => "Committed and synced",
            _ => "Committed",
        };
        let service = self.workspace_service.clone();
        cx.spawn_in(window, async move |this, cx| {
            let commit_result = service
                .git_action(workspace_path.clone(), GitAction::Commit(message))
                .await;
            let result = match (commit_result, follow_up) {
                (Ok(value), None) => Ok(value),
                (Ok(_), Some(follow_up)) => {
                    service.git_action(workspace_path.clone(), follow_up).await
                }
                (Err(error), _) => Err(error),
            };
            let snapshot = service.git_snapshot(workspace_path).await.ok();
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                if generation != this.git_generation {
                    return;
                }
                this.git_busy = false;
                match result {
                    Ok(_) => {
                        this.local_message = Some(success_message.into());
                        this.commit_input.update(cx, |input, cx| {
                            input.set_value("", window, cx);
                        });
                        if let Some(snapshot) = snapshot {
                            this.git_snapshot = snapshot;
                        }
                    }
                    Err(error) => this.local_message = Some(friendly_git_error(&error).into()),
                }
                cx.notify();
            });
        })
        .detach();
    }
}

pub(super) fn source_icon_button(
    id: impl Into<gpui::ElementId>,
    kind: AleraIcon,
    selected: bool,
) -> gpui::Stateful<gpui::Div> {
    source_icon_button_with_enabled(id, kind, selected, true)
}

pub(super) fn source_icon_button_with_enabled(
    id: impl Into<gpui::ElementId>,
    kind: AleraIcon,
    selected: bool,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    let color = if kind == AleraIcon::Stop {
        theme::danger()
    } else {
        theme::text_muted()
    };
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::Button)
        .flex()
        .items_center()
        .justify_center()
        .w(px(30.0))
        .h(px(30.0))
        .rounded_md()
        .cursor(if enabled {
            CursorStyle::PointingHand
        } else {
            CursorStyle::Arrow
        })
        .when(selected, |button| button.bg(theme::surface_selected()))
        .when(enabled, |button| {
            button.hover(|style| style.bg(theme::surface_selected()))
        })
        .child(icon(kind, 16.0, color))
}

pub(super) fn source_row_action(
    id: impl Into<gpui::ElementId>,
    kind: AleraIcon,
    destructive: bool,
) -> gpui::Stateful<gpui::Div> {
    let tooltip = match kind {
        AleraIcon::GitStage => "Stage",
        AleraIcon::GitUnstage => "Unstage",
        AleraIcon::GitDiscard => "Discard",
        _ if destructive => "Discard",
        _ => "Action",
    };
    source_icon_button(id, kind, false)
        .aria_label(tooltip)
        .text_color(if destructive {
            theme::danger()
        } else {
            theme::text_muted()
        })
        .tooltip(move |_, cx| {
            let tooltip = tooltip.to_owned();
            cx.new(move |_| Tooltip::new(tooltip)).into()
        })
}

pub(super) fn source_summary(app: &AleraApp) -> String {
    let mut parts = app
        .selected_source_control_root()
        .into_iter()
        .collect::<Vec<_>>();
    parts.push(app.git_snapshot.branch.clone());
    if let Some(upstream) = &app.git_snapshot.upstream {
        parts.push(upstream.clone());
    }
    if app.git_snapshot.ahead > 0 {
        parts.push(format!("ahead {}", app.git_snapshot.ahead));
    }
    if app.git_snapshot.behind > 0 {
        parts.push(format!("behind {}", app.git_snapshot.behind));
    }
    if app.git_snapshot.has_conflicts {
        parts.push("conflicts".to_owned());
    }
    parts.join(" · ")
}

pub(super) fn source_action_label(action: SourceControlAction) -> &'static str {
    match action {
        SourceControlAction::Commit => "Commit",
        SourceControlAction::CommitPush => "Commit & Push",
        SourceControlAction::CommitSync => "Commit & Sync",
        SourceControlAction::Amend => "Commit Amend",
        SourceControlAction::StageAll => "Stage All",
        SourceControlAction::UnstageAll => "Unstage All",
        SourceControlAction::DiscardAll => "Discard All",
        SourceControlAction::Fetch => "Fetch",
        SourceControlAction::Pull => "Pull",
        SourceControlAction::Push => "Push",
        SourceControlAction::Sync => "Sync",
        SourceControlAction::PublishBranch => "Publish Branch",
        SourceControlAction::Stash => "Stash",
        SourceControlAction::StashPop => "Stash Pop",
    }
}

pub(super) fn source_action_icon(action: SourceControlAction) -> AleraIcon {
    match action {
        SourceControlAction::Commit | SourceControlAction::Amend => AleraIcon::GitCommit,
        SourceControlAction::CommitPush | SourceControlAction::Push => AleraIcon::GitPush,
        SourceControlAction::CommitSync | SourceControlAction::Sync => AleraIcon::GitSync,
        SourceControlAction::StageAll => AleraIcon::GitStage,
        SourceControlAction::UnstageAll => AleraIcon::GitUnstage,
        SourceControlAction::DiscardAll => AleraIcon::GitDiscard,
        SourceControlAction::Fetch => AleraIcon::GitFetch,
        SourceControlAction::Pull => AleraIcon::GitPull,
        SourceControlAction::PublishBranch => AleraIcon::GitPublish,
        SourceControlAction::Stash => AleraIcon::GitStash,
        SourceControlAction::StashPop => AleraIcon::GitStashPop,
    }
}
