use gpui::{Context, FocusHandle};

use super::AleraApp;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum KeyboardActionGroup {
    Global,
    Workspace,
    Tabs,
    Panes,
}

impl KeyboardActionGroup {
    pub(super) const ALL: [Self; 4] = [Self::Global, Self::Workspace, Self::Tabs, Self::Panes];

    pub(super) const fn label(self) -> &'static str {
        match self {
            Self::Global => "Global",
            Self::Workspace => "Workspace",
            Self::Tabs => "Tabs",
            Self::Panes => "Panes",
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub(super) struct KeyboardBindingDefinition {
    pub id: &'static str,
    pub label: &'static str,
    pub group: KeyboardActionGroup,
    pub description: &'static str,
    pub macos: &'static [&'static str],
    pub other: &'static [&'static str],
    pub allow_in_terminal: bool,
}

macro_rules! binding {
    ($id:literal, $label:literal, $group:ident, $description:literal, $keys:expr, $allow:expr) => {
        KeyboardBindingDefinition {
            id: $id,
            label: $label,
            group: KeyboardActionGroup::$group,
            description: $description,
            macos: $keys,
            other: $keys,
            allow_in_terminal: $allow,
        }
    };
    ($id:literal, $label:literal, $group:ident, $description:literal, $macos:expr, $other:expr, $allow:expr) => {
        KeyboardBindingDefinition {
            id: $id,
            label: $label,
            group: KeyboardActionGroup::$group,
            description: $description,
            macos: $macos,
            other: $other,
            allow_in_terminal: $allow,
        }
    };
}

pub(super) const KEYBOARD_BINDINGS: &[KeyboardBindingDefinition] = &[
    binding!(
        "openSettings",
        "Open Settings",
        Global,
        "Open the settings dialog.",
        &["Mod+Comma"],
        true
    ),
    binding!(
        "openQuickOpen",
        "Quick Open",
        Global,
        "Search and open a file in the active workspace.",
        &["Mod+P"],
        true
    ),
    binding!(
        "openCommandPalette",
        "Command Palette",
        Global,
        "Search and run an Alera command.",
        &["Mod+Shift+P"],
        true
    ),
    binding!(
        "addProject",
        "Add Project",
        Global,
        "Open the add-project dialog.",
        &["Mod+Shift+O"],
        true
    ),
    binding!(
        "toggleSidebar",
        "Toggle Sidebar",
        Global,
        "Collapse or expand the project sidebar.",
        &["Mod+B"],
        true
    ),
    binding!(
        "createWorkspace",
        "New Workspace",
        Workspace,
        "Create a linked workspace for the active Git project.",
        &["Mod+Shift+N"],
        true
    ),
    binding!(
        "goBack",
        "Go Back",
        Workspace,
        "Go to the previously selected workspace.",
        &["Mod+BracketLeft"],
        &["Alt+ArrowLeft"],
        false
    ),
    binding!(
        "goForward",
        "Go Forward",
        Workspace,
        "Go to the next workspace in navigation history.",
        &["Mod+BracketRight"],
        &["Alt+ArrowRight"],
        false
    ),
    binding!(
        "findInFiles",
        "Find in Files",
        Workspace,
        "Open workspace search.",
        &["Mod+Shift+F"],
        true
    ),
    binding!(
        "findInTerminal",
        "Find in Terminal",
        Workspace,
        "Search the active terminal scrollback.",
        &["Mod+F"],
        true
    ),
    binding!(
        "replaceInFiles",
        "Replace in Files",
        Workspace,
        "Open workspace search and replace.",
        &["Mod+Shift+H"],
        true
    ),
    binding!(
        "saveFile",
        "Save File",
        Workspace,
        "Save the active editor file.",
        &["Mod+S"],
        false
    ),
    binding!(
        "newTerminalTab",
        "New Terminal Tab",
        Tabs,
        "Open a terminal tab in the active workspace.",
        &["Mod+T"],
        false
    ),
    binding!(
        "closeTab",
        "Close Tab",
        Tabs,
        "Close the active terminal tab.",
        &["Mod+W"],
        false
    ),
    binding!(
        "nextTab",
        "Next Tab",
        Tabs,
        "Select the next tab in the active pane.",
        &["Mod+Shift+BracketRight", "Ctrl+Tab"],
        &["Ctrl+Tab"],
        false
    ),
    binding!(
        "previousTab",
        "Previous Tab",
        Tabs,
        "Select the previous tab in the active pane.",
        &["Mod+Shift+BracketLeft", "Ctrl+Shift+Tab"],
        &["Ctrl+Shift+Tab"],
        false
    ),
    binding!(
        "goToTab1",
        "Go to Tab 1",
        Tabs,
        "Select the first tab in the active pane.",
        &["Mod+1"],
        false
    ),
    binding!(
        "goToTab2",
        "Go to Tab 2",
        Tabs,
        "Select the second tab in the active pane.",
        &["Mod+2"],
        false
    ),
    binding!(
        "goToTab3",
        "Go to Tab 3",
        Tabs,
        "Select the third tab in the active pane.",
        &["Mod+3"],
        false
    ),
    binding!(
        "goToTab4",
        "Go to Tab 4",
        Tabs,
        "Select the fourth tab in the active pane.",
        &["Mod+4"],
        false
    ),
    binding!(
        "goToTab5",
        "Go to Tab 5",
        Tabs,
        "Select the fifth tab in the active pane.",
        &["Mod+5"],
        false
    ),
    binding!(
        "goToTab6",
        "Go to Tab 6",
        Tabs,
        "Select the sixth tab in the active pane.",
        &["Mod+6"],
        false
    ),
    binding!(
        "goToTab7",
        "Go to Tab 7",
        Tabs,
        "Select the seventh tab in the active pane.",
        &["Mod+7"],
        false
    ),
    binding!(
        "goToTab8",
        "Go to Tab 8",
        Tabs,
        "Select the eighth tab in the active pane.",
        &["Mod+8"],
        false
    ),
    binding!(
        "goToTab9",
        "Go to Last Tab",
        Tabs,
        "Select the last tab in the active pane.",
        &["Mod+9"],
        false
    ),
    binding!(
        "splitRight",
        "Split Right",
        Panes,
        "Split the active pane to the right with a new terminal.",
        &["Mod+D"],
        &["Mod+Shift+D"],
        false
    ),
    binding!(
        "splitDown",
        "Split Down",
        Panes,
        "Split the active pane downward with a new terminal.",
        &["Mod+Shift+D"],
        &["Mod+Alt+D"],
        false
    ),
    binding!(
        "closeSplit",
        "Close Split",
        Panes,
        "Merge the active pane back into its sibling.",
        &["Mod+Shift+W"],
        false
    ),
];

pub(super) struct KeyboardSettingsUiState {
    pub focus: FocusHandle,
    pub recording_id: Option<&'static str>,
    pub error: Option<(&'static str, String)>,
    pub conflict: Option<KeyboardBindingConflict>,
}

pub(super) struct KeyboardBindingConflict {
    pub target_id: &'static str,
    pub owner_id: &'static str,
    pub chord: String,
}

impl KeyboardSettingsUiState {
    pub(super) fn new(cx: &mut Context<AleraApp>) -> Self {
        Self {
            focus: cx.focus_handle().tab_stop(true),
            recording_id: None,
            error: None,
            conflict: None,
        }
    }
}

pub(super) fn definition(id: &str) -> Option<&'static KeyboardBindingDefinition> {
    KEYBOARD_BINDINGS
        .iter()
        .find(|definition| definition.id == id)
}

pub(super) fn defaults(definition: &KeyboardBindingDefinition) -> Vec<String> {
    if cfg!(target_os = "macos") {
        definition.macos
    } else {
        definition.other
    }
    .iter()
    .map(|binding| (*binding).to_string())
    .collect()
}

pub(super) fn effective_bindings(
    settings: &super::settings_state::SettingsState,
    definition: &KeyboardBindingDefinition,
) -> Vec<String> {
    settings
        .keyboard_overrides
        .get(definition.id)
        .cloned()
        .unwrap_or_else(|| defaults(definition))
}
