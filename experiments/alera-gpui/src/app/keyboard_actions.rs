use gpui::{actions, Action, App, Context, KeyBinding, Window};

use super::keyboard_settings::{defaults, KEYBOARD_BINDINGS};
use super::AleraApp;
use crate::activity::ContextPanel;
use crate::model::WorkbenchSplitDirection;

actions!(
    alera,
    [
        OpenSettings,
        OpenExecutionPlans,
        AddProject,
        ToggleSidebar,
        CreateWorkspace,
        FindInFiles,
        ReplaceInFiles,
        SaveFile,
        NewTerminalTab,
        CloseTab,
        NextTab,
        PreviousTab,
        GoToTab1,
        GoToTab2,
        GoToTab3,
        GoToTab4,
        GoToTab5,
        GoToTab6,
        GoToTab7,
        GoToTab8,
        GoToTab9,
        SplitRight,
        SplitDown,
        CloseSplit,
        MinimizeWindow,
        ZoomWindow,
        ToggleFullScreen,
        QuitApp,
    ]
);

macro_rules! tab_action_handler {
    ($name:ident, $action:ty, $id:literal, $number:expr) => {
        pub(super) fn $name(&mut self, _: &$action, window: &mut Window, cx: &mut Context<Self>) {
            if !self.keyboard_shortcut_allowed($id, window) {
                cx.propagate();
                return;
            }
            self.select_tab_number($number, cx);
        }
    };
}

pub fn register(cx: &mut App) {
    cx.bind_keys(KEYBOARD_BINDINGS.iter().flat_map(|definition| {
        defaults(definition)
            .into_iter()
            .filter_map(move |canonical| {
                let keystroke = canonical_to_gpui(&canonical)?;
                key_binding_for_action(definition.id, &keystroke)
            })
    }));
    super::terminal_input::register(cx);
}

pub(super) fn key_binding_for_action(id: &str, keystroke: &str) -> Option<KeyBinding> {
    let action: Box<dyn Action> = match id {
        "openSettings" => Box::new(OpenSettings),
        "addProject" => Box::new(AddProject),
        "toggleSidebar" => Box::new(ToggleSidebar),
        "createWorkspace" => Box::new(CreateWorkspace),
        "findInFiles" => Box::new(FindInFiles),
        "replaceInFiles" => Box::new(ReplaceInFiles),
        "saveFile" => Box::new(SaveFile),
        "newTerminalTab" => Box::new(NewTerminalTab),
        "closeTab" => Box::new(CloseTab),
        "nextTab" => Box::new(NextTab),
        "previousTab" => Box::new(PreviousTab),
        "goToTab1" => Box::new(GoToTab1),
        "goToTab2" => Box::new(GoToTab2),
        "goToTab3" => Box::new(GoToTab3),
        "goToTab4" => Box::new(GoToTab4),
        "goToTab5" => Box::new(GoToTab5),
        "goToTab6" => Box::new(GoToTab6),
        "goToTab7" => Box::new(GoToTab7),
        "goToTab8" => Box::new(GoToTab8),
        "goToTab9" => Box::new(GoToTab9),
        "splitRight" => Box::new(SplitRight),
        "splitDown" => Box::new(SplitDown),
        "closeSplit" => Box::new(CloseSplit),
        _ => return None,
    };
    KeyBinding::load(
        keystroke,
        action,
        None,
        false,
        None,
        &gpui::DummyKeyboardMapper,
    )
    .ok()
}

pub(super) fn canonical_to_gpui(canonical: &str) -> Option<String> {
    let mut parts = Vec::new();
    let tokens = canonical.split('+').collect::<Vec<_>>();
    let (trigger, modifiers) = tokens.split_last()?;
    for modifier in modifiers {
        match modifier.to_ascii_lowercase().as_str() {
            "mod" => parts.push(if cfg!(target_os = "macos") {
                "cmd".to_string()
            } else {
                "ctrl".to_string()
            }),
            "cmd" => parts.push("cmd".to_string()),
            "ctrl" => parts.push("ctrl".to_string()),
            "alt" => parts.push("alt".to_string()),
            "shift" => parts.push("shift".to_string()),
            _ => return None,
        }
    }
    parts.push(match trigger.to_ascii_lowercase().as_str() {
        "comma" => ",".to_string(),
        "period" => ".".to_string(),
        "slash" => "/".to_string(),
        "backslash" => "\\".to_string(),
        "bracketleft" => "[".to_string(),
        "bracketright" => "]".to_string(),
        "minus" => "-".to_string(),
        "equal" => "=".to_string(),
        "semicolon" => ";".to_string(),
        "quote" => "'".to_string(),
        "backquote" => "`".to_string(),
        key => key.to_string(),
    });
    Some(parts.join("-"))
}

impl AleraApp {
    tab_action_handler!(on_go_to_tab_1, GoToTab1, "goToTab1", 1);
    tab_action_handler!(on_go_to_tab_2, GoToTab2, "goToTab2", 2);
    tab_action_handler!(on_go_to_tab_3, GoToTab3, "goToTab3", 3);
    tab_action_handler!(on_go_to_tab_4, GoToTab4, "goToTab4", 4);
    tab_action_handler!(on_go_to_tab_5, GoToTab5, "goToTab5", 5);
    tab_action_handler!(on_go_to_tab_6, GoToTab6, "goToTab6", 6);
    tab_action_handler!(on_go_to_tab_7, GoToTab7, "goToTab7", 7);
    tab_action_handler!(on_go_to_tab_8, GoToTab8, "goToTab8", 8);
    tab_action_handler!(on_go_to_tab_9, GoToTab9, "goToTab9", 9);

    pub(super) fn on_open_settings(
        &mut self,
        _: &OpenSettings,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("openSettings", window) {
            cx.propagate();
            return;
        }
        self.open_settings_dialog(window, cx);
    }

    pub(super) fn on_minimize_window(
        &mut self,
        _: &MinimizeWindow,
        window: &mut Window,
        _: &mut Context<Self>,
    ) {
        window.minimize_window();
    }

    pub(super) fn on_zoom_window(
        &mut self,
        _: &ZoomWindow,
        window: &mut Window,
        _: &mut Context<Self>,
    ) {
        window.zoom_window();
    }

    pub(super) fn on_toggle_full_screen(
        &mut self,
        _: &ToggleFullScreen,
        window: &mut Window,
        _: &mut Context<Self>,
    ) {
        window.toggle_fullscreen();
    }

    pub(super) fn on_quit_app(&mut self, _: &QuitApp, _: &mut Window, cx: &mut Context<Self>) {
        cx.quit();
    }

    pub(super) fn on_add_project(
        &mut self,
        _: &AddProject,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("addProject", window) {
            cx.propagate();
            return;
        }
        self.add_project(window, cx);
    }

    pub(super) fn on_toggle_sidebar(
        &mut self,
        _: &ToggleSidebar,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("toggleSidebar", window) {
            cx.propagate();
            return;
        }
        self.sidebar_collapsed = !self.sidebar_collapsed;
        cx.notify();
    }

    pub(super) fn on_create_workspace(
        &mut self,
        _: &CreateWorkspace,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("createWorkspace", window) {
            cx.propagate();
            return;
        }
        self.open_new_workspace_dialog(cx);
    }

    pub(super) fn on_find_in_files(
        &mut self,
        _: &FindInFiles,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("findInFiles", window) {
            cx.propagate();
            return;
        }
        self.context_sidebar_collapsed = false;
        self.select_context_panel(ContextPanel::Search, cx);
    }

    pub(super) fn on_replace_in_files(
        &mut self,
        _: &ReplaceInFiles,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("replaceInFiles", window) {
            cx.propagate();
            return;
        }
        self.context_sidebar_collapsed = false;
        self.search_replace_expanded = true;
        self.select_context_panel(ContextPanel::Search, cx);
    }

    pub(super) fn on_save_file(
        &mut self,
        _: &SaveFile,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("saveFile", window) {
            cx.propagate();
            return;
        }
        self.save_editor(false, cx);
    }

    pub(super) fn on_new_terminal(
        &mut self,
        _: &NewTerminalTab,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("newTerminalTab", window) {
            cx.propagate();
            return;
        }
        self.create_terminal_tab(cx);
    }

    pub(super) fn on_close_tab(
        &mut self,
        _: &CloseTab,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("closeTab", window) {
            cx.propagate();
            return;
        }
        if let Some(tab_id) = self.selected_tab_id.clone() {
            self.request_close_tab(tab_id, cx);
        }
    }

    pub(super) fn on_next_tab(&mut self, _: &NextTab, window: &mut Window, cx: &mut Context<Self>) {
        if !self.keyboard_shortcut_allowed("nextTab", window) {
            cx.propagate();
            return;
        }
        self.select_relative_tab(1, cx);
    }

    pub(super) fn on_previous_tab(
        &mut self,
        _: &PreviousTab,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("previousTab", window) {
            cx.propagate();
            return;
        }
        self.select_relative_tab(-1, cx);
    }

    pub(super) fn on_split_right(
        &mut self,
        _: &SplitRight,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("splitRight", window) {
            cx.propagate();
            return;
        }
        self.split_active_group(WorkbenchSplitDirection::Right, cx);
    }

    pub(super) fn on_split_down(
        &mut self,
        _: &SplitDown,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("splitDown", window) {
            cx.propagate();
            return;
        }
        self.split_active_group(WorkbenchSplitDirection::Down, cx);
    }

    pub(super) fn on_close_split(
        &mut self,
        _: &CloseSplit,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.keyboard_shortcut_allowed("closeSplit", window) {
            cx.propagate();
            return;
        }
        if let Some(group_id) = self
            .snapshot
            .layout
            .as_ref()
            .map(|layout| layout.active_group_id.clone())
        {
            self.merge_pane_group(group_id, cx);
        }
    }

    fn split_active_group(&mut self, direction: WorkbenchSplitDirection, cx: &mut Context<Self>) {
        if let Some(group_id) = self
            .snapshot
            .layout
            .as_ref()
            .map(|layout| layout.active_group_id.clone())
        {
            self.split_pane_with_terminal(group_id, direction, cx);
        }
    }

    fn keyboard_shortcut_allowed(&self, id: &str, window: &Window) -> bool {
        self.settings_state.keyboard_terminal_policy != "terminalFirst"
            || !self.terminal_focus.is_focused(window)
            || KEYBOARD_BINDINGS
                .iter()
                .find(|definition| definition.id == id)
                .is_some_and(|definition| definition.allow_in_terminal)
    }

    fn active_group_tab_ids(&self) -> Vec<String> {
        self.snapshot
            .layout
            .as_ref()
            .and_then(|layout| layout.groups.get(&layout.active_group_id))
            .map(|group| group.tab_ids.clone())
            .unwrap_or_else(|| {
                self.snapshot
                    .tabs
                    .iter()
                    .map(|tab| tab.id.clone())
                    .collect()
            })
    }

    fn select_relative_tab(&mut self, delta: isize, cx: &mut Context<Self>) {
        let tab_ids = self.active_group_tab_ids();
        if tab_ids.is_empty() {
            return;
        }
        let current = self
            .selected_tab_id
            .as_ref()
            .and_then(|selected| tab_ids.iter().position(|tab_id| tab_id == selected))
            .unwrap_or(0);
        let next = (current as isize + delta).rem_euclid(tab_ids.len() as isize) as usize;
        self.activate_workspace_tab(tab_ids[next].clone(), cx);
    }

    pub(super) fn select_tab_number(&mut self, number: usize, cx: &mut Context<Self>) {
        let tab_ids = self.active_group_tab_ids();
        let index = if number == 9 {
            tab_ids.len().saturating_sub(1)
        } else {
            number.saturating_sub(1)
        };
        if let Some(tab_id) = tab_ids.get(index) {
            self.activate_workspace_tab(tab_id.clone(), cx);
        }
    }
}
