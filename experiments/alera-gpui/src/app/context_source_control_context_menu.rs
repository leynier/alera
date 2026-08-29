use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, KeyDownEvent, MouseButton, ParentElement as _, Role,
    SharedString, StatefulInteractiveElement as _, Styled as _, Window,
};

use super::AleraApp;
use crate::icons::{icon, AleraIcon};
use crate::theme;
use crate::workspace_git::{GitAction, GitChange};

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct SourceChangeContextMenu {
    pub(super) group_area: String,
    pub(super) change_area: Option<String>,
    pub(super) path: String,
    pub(super) directory: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SourceChangeContextAction {
    OpenFile,
    RevealInExplorer,
    Stage,
    Unstage,
    Discard,
}

#[derive(Clone)]
struct SourceChangeContextEntry {
    action: SourceChangeContextAction,
    label: &'static str,
    icon: AleraIcon,
    enabled: bool,
    separator_before: bool,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct SourceChangeCapabilities {
    open_file: bool,
    stage_paths: Vec<String>,
    unstage_paths: Vec<String>,
    discard_paths: Vec<String>,
}

impl AleraApp {
    pub(super) fn open_source_change_context_menu(
        &mut self,
        menu: SourceChangeContextMenu,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.source_change_context_menu = Some(menu);
        self.source_change_menu_previous_focus = window.focused(cx);
        self.source_change_menu_highlighted = self
            .source_change_context_enabled_indices()
            .into_iter()
            .next()
            .unwrap_or(0);
        self.source_change_menu_focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn dismiss_source_change_context_menu(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.source_change_context_menu = None;
        if let Some(focus) = self.source_change_menu_previous_focus.take() {
            focus.focus(window, cx);
        }
        cx.notify();
    }

    pub(super) fn render_source_change_context_menu(&self, cx: &mut Context<Self>) -> AnyElement {
        let entries = self.source_change_context_entries();
        div()
            .id("source-change-context-menu")
            .track_focus(&self.source_change_menu_focus)
            .role(Role::Menu)
            .aria_label("Source Control Actions")
            .absolute()
            .right(px(8.0))
            .top(px(82.0))
            .w(px(200.0))
            .occlude()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .py_1()
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .on_mouse_down_out(cx.listener(|this, _, window, cx| {
                this.dismiss_source_change_context_menu(window, cx);
            }))
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                this.handle_source_change_context_key(event, window, cx);
            }))
            .children(entries.into_iter().enumerate().flat_map(|(index, entry)| {
                let mut rows = Vec::with_capacity(2);
                if entry.separator_before {
                    rows.push(
                        div()
                            .h(px(1.0))
                            .my_1()
                            .bg(theme::border_subtle())
                            .into_any_element(),
                    );
                }
                let action = entry.action;
                let enabled = entry.enabled;
                let selected = self.source_change_menu_highlighted == index;
                let row = source_change_context_row(
                    SharedString::from(format!("source-change-context-{index}")),
                    entry.icon,
                    entry.label,
                    enabled,
                )
                .aria_selected(selected)
                .when(selected && enabled, |row| row.bg(theme::surface_selected()))
                .when(enabled, |row| {
                    row.on_click(cx.listener(move |this, _, window, cx| {
                        cx.stop_propagation();
                        this.execute_source_change_context_action(action, window, cx);
                    }))
                });
                rows.push(row.into_any_element());
                rows
            }))
            .into_any_element()
    }

    fn source_change_context_entries(&self) -> Vec<SourceChangeContextEntry> {
        let Some(menu) = self.source_change_context_menu.as_ref() else {
            return Vec::new();
        };
        let capabilities = source_change_capabilities(&self.git_snapshot.changes, menu);
        let mut entries = Vec::new();
        if capabilities.open_file {
            entries.push(SourceChangeContextEntry {
                action: SourceChangeContextAction::OpenFile,
                label: "Open File",
                icon: AleraIcon::File,
                enabled: true,
                separator_before: false,
            });
        }
        entries.push(SourceChangeContextEntry {
            action: SourceChangeContextAction::RevealInExplorer,
            label: "Reveal in Explorer",
            icon: AleraIcon::Files,
            enabled: true,
            separator_before: false,
        });
        let mut first_git_action = true;
        for (action, label, icon, available) in [
            (
                SourceChangeContextAction::Unstage,
                "Unstage",
                AleraIcon::GitUnstage,
                !capabilities.unstage_paths.is_empty(),
            ),
            (
                SourceChangeContextAction::Stage,
                "Stage",
                AleraIcon::GitStage,
                !capabilities.stage_paths.is_empty(),
            ),
            (
                SourceChangeContextAction::Discard,
                "Discard",
                AleraIcon::GitDiscard,
                !capabilities.discard_paths.is_empty(),
            ),
        ] {
            if !available {
                continue;
            }
            entries.push(SourceChangeContextEntry {
                action,
                label,
                icon,
                enabled: !self.git_busy && !self.git_snapshot_loading,
                separator_before: std::mem::take(&mut first_git_action),
            });
        }
        entries
    }

    fn source_change_context_enabled_indices(&self) -> Vec<usize> {
        self.source_change_context_entries()
            .iter()
            .enumerate()
            .filter_map(|(index, entry)| entry.enabled.then_some(index))
            .collect()
    }

    fn handle_source_change_context_key(
        &mut self,
        event: &KeyDownEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let key = event.keystroke.key.as_str();
        if key.eq_ignore_ascii_case("escape") {
            self.dismiss_source_change_context_menu(window, cx);
            return;
        }
        let enabled = self.source_change_context_enabled_indices();
        if enabled.is_empty() {
            return;
        }
        if key.eq_ignore_ascii_case("enter") || key == " " || key.eq_ignore_ascii_case("space") {
            if let Some(entry) = self
                .source_change_context_entries()
                .get(self.source_change_menu_highlighted)
                .filter(|entry| entry.enabled)
            {
                self.execute_source_change_context_action(entry.action, window, cx);
            }
            return;
        }
        let current = enabled
            .iter()
            .position(|index| *index == self.source_change_menu_highlighted)
            .unwrap_or(0);
        let next = if key.eq_ignore_ascii_case("home") {
            0
        } else if key.eq_ignore_ascii_case("end") {
            enabled.len() - 1
        } else if key.eq_ignore_ascii_case("up") {
            current.checked_sub(1).unwrap_or(enabled.len() - 1)
        } else if key.eq_ignore_ascii_case("down") {
            (current + 1) % enabled.len()
        } else {
            return;
        };
        self.source_change_menu_highlighted = enabled[next];
        cx.notify();
    }

    fn execute_source_change_context_action(
        &mut self,
        action: SourceChangeContextAction,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(menu) = self.source_change_context_menu.clone() else {
            return;
        };
        let capabilities = source_change_capabilities(&self.git_snapshot.changes, &menu);
        self.dismiss_source_change_context_menu(window, cx);
        match action {
            SourceChangeContextAction::OpenFile => {
                if !capabilities.open_file {
                    return;
                }
                let path = self
                    .selected_source_control_scope()
                    .and_then(|scope| scope.to_workspace_relative_path(&menu.path));
                if let Some(path) = path {
                    self.open_file_tab(path, cx);
                }
            }
            SourceChangeContextAction::RevealInExplorer => {
                self.reveal_source_control_path_in_explorer(menu.path, cx);
            }
            SourceChangeContextAction::Stage => self.run_git_path_actions(
                capabilities
                    .stage_paths
                    .into_iter()
                    .map(GitAction::StagePath)
                    .collect(),
                cx,
            ),
            SourceChangeContextAction::Unstage => self.run_git_path_actions(
                capabilities
                    .unstage_paths
                    .into_iter()
                    .map(GitAction::UnstagePath)
                    .collect(),
                cx,
            ),
            SourceChangeContextAction::Discard => {
                self.request_discard_paths(capabilities.discard_paths, cx);
            }
        }
    }
}

fn source_change_capabilities(
    changes: &[GitChange],
    menu: &SourceChangeContextMenu,
) -> SourceChangeCapabilities {
    let path_prefix = format!("{}/", menu.path);
    let relevant = changes.iter().filter(|change| {
        let path_matches = if menu.directory {
            change.path.starts_with(&path_prefix)
        } else {
            change.path == menu.path
        };
        let area_matches = menu.group_area.eq_ignore_ascii_case("unified")
            || change.area.eq_ignore_ascii_case(&menu.group_area);
        let exact_change_matches = menu.directory
            || menu
                .change_area
                .as_deref()
                .is_none_or(|area| change.area.eq_ignore_ascii_case(area));
        path_matches && area_matches && exact_change_matches
    });
    let mut result = SourceChangeCapabilities::default();
    for change in relevant {
        if change.area.eq_ignore_ascii_case("staged") {
            result.unstage_paths.push(change.path.clone());
        } else {
            result.stage_paths.push(change.path.clone());
            result.discard_paths.push(change.path.clone());
        }
        if !menu.directory
            && !matches!(change.status.to_ascii_lowercase().as_str(), "d" | "deleted")
        {
            result.open_file = true;
        }
    }
    result.stage_paths.sort();
    result.stage_paths.dedup();
    result.unstage_paths.sort();
    result.unstage_paths.dedup();
    result.discard_paths.sort();
    result.discard_paths.dedup();
    result
}

fn source_change_context_row(
    id: SharedString,
    kind: AleraIcon,
    label: &'static str,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::MenuItem)
        .aria_label(label)
        .flex()
        .items_center()
        .h(px(30.0))
        .px_2()
        .gap_2()
        .text_size(px(13.0))
        .text_color(if enabled {
            theme::text()
        } else {
            theme::text_faint()
        })
        .when(enabled, |row| {
            row.cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface_selected()))
        })
        .child(icon(
            kind,
            16.0,
            if enabled {
                theme::text_muted()
            } else {
                theme::text_faint()
            },
        ))
        .child(label)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn directory_context_collects_mixed_stage_actions() {
        let changes = vec![
            change("src/staged.rs", "staged", "M"),
            change("src/dirty.rs", "unstaged", "M"),
            change("readme.md", "unstaged", "M"),
        ];
        let menu = SourceChangeContextMenu {
            group_area: "unified".to_owned(),
            change_area: None,
            path: "src".to_owned(),
            directory: true,
        };

        let capabilities = source_change_capabilities(&changes, &menu);

        assert_eq!(capabilities.stage_paths, ["src/dirty.rs"]);
        assert_eq!(capabilities.unstage_paths, ["src/staged.rs"]);
        assert_eq!(capabilities.discard_paths, ["src/dirty.rs"]);
        assert!(!capabilities.open_file);
    }

    #[test]
    fn deleted_file_cannot_open_but_can_reveal_and_unstage() {
        let changes = vec![change("src/deleted.rs", "staged", "D")];
        let menu = SourceChangeContextMenu {
            group_area: "staged".to_owned(),
            change_area: Some("staged".to_owned()),
            path: "src/deleted.rs".to_owned(),
            directory: false,
        };

        let capabilities = source_change_capabilities(&changes, &menu);

        assert!(!capabilities.open_file);
        assert_eq!(capabilities.unstage_paths, ["src/deleted.rs"]);
    }

    fn change(path: &str, area: &str, status: &str) -> GitChange {
        GitChange {
            path: path.to_owned(),
            area: area.to_owned(),
            status: status.to_owned(),
            added: None,
            removed: None,
        }
    }
}
