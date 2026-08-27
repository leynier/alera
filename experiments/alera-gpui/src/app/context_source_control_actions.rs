use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Styled as _, Window,
};

use super::context_source_control_dialog::SourceControlDialog;
use super::AleraApp;
use crate::icons::{icon, AleraIcon};
use crate::theme;
use crate::workspace_git::GitAction;
use super::git_surface::friendly_git_error;

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
            .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                this.source_control_menu_open = false;
                cx.notify();
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
                            .when(entry.enabled, |row| {
                                row.cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_selected()))
                                    .on_mouse_down(
                                        gpui::MouseButton::Left,
                                        cx.listener(move |this, _, window, cx| {
                                            this.source_control_menu_open = false;
                                            this.run_source_control_action(
                                                entry.action,
                                                window,
                                                cx,
                                            );
                                        }),
                                    )
                            })
                            .child(icon(source_action_icon(entry.action), 16.0, icon_color))
                            .child(entry.label),
                    )
            }))
            .into_any_element()
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
        let has_snapshot = !self.git_busy
            && !self.git_snapshot_loading
            && self.git_snapshot_error.is_none();
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
            (SourceControlAction::StageAll, has_snapshot && has_stageable, true),
            (SourceControlAction::UnstageAll, has_snapshot && has_staged, false),
            (SourceControlAction::DiscardAll, has_snapshot && has_discardable, false),
            (SourceControlAction::Fetch, has_snapshot, true),
            (SourceControlAction::Pull, has_snapshot, false),
            (SourceControlAction::Push, has_snapshot && !has_conflicts, false),
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
            SourceControlAction::Commit => self.commit(false, cx),
            SourceControlAction::CommitPush => self.commit_with_follow_up(GitAction::Push, cx),
            SourceControlAction::CommitSync => self.commit_with_follow_up(GitAction::Sync, cx),
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
            SourceControlAction::Push | SourceControlAction::PublishBranch => {
                self.run_git_action(GitAction::Push, cx);
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

    fn commit_with_follow_up(&mut self, follow_up: GitAction, cx: &mut Context<Self>) {
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
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = match service
                .git_action(workspace_path.clone(), GitAction::Commit(message))
                .await
            {
                Ok(_) => service.git_action(workspace_path.clone(), follow_up).await,
                Err(error) => Err(error),
            };
            let snapshot = service.git_snapshot(workspace_path).await.ok();
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.git_generation {
                    return;
                }
                this.git_busy = false;
                match result {
                    Ok(message) => {
                        this.local_message = Some(message.into());
                        if let Some(snapshot) = snapshot {
                            this.git_snapshot = snapshot;
                        }
                    }
                    Err(error) => {
                        this.local_message = Some(friendly_git_error(&error).into())
                    }
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
        .flex()
        .items_center()
        .justify_center()
        .w(px(24.0))
        .h(px(24.0))
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
        .child(icon(kind, 14.0, color))
}

pub(super) fn source_row_action(
    id: impl Into<gpui::ElementId>,
    kind: AleraIcon,
    destructive: bool,
) -> gpui::Stateful<gpui::Div> {
    source_icon_button(id, kind, false).text_color(if destructive {
        theme::danger()
    } else {
        theme::text_muted()
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
        parts.push(format!("Ahead {}", app.git_snapshot.ahead));
    }
    if app.git_snapshot.behind > 0 {
        parts.push(format!("Behind {}", app.git_snapshot.behind));
    }
    if app.git_snapshot.has_conflicts {
        parts.push("Conflicts".to_owned());
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
