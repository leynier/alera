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
        "Open The Settings Dialog.",
        &["Mod+Comma"],
        true
    ),
    binding!(
        "addProject",
        "Add Project",
        Global,
        "Open The Add-Project Dialog.",
        &["Mod+Shift+O"],
        true
    ),
    binding!(
        "toggleSidebar",
        "Toggle Sidebar",
        Global,
        "Collapse Or Expand The Project Sidebar.",
        &["Mod+B"],
        true
    ),
    binding!(
        "createWorkspace",
        "New Workspace",
        Workspace,
        "Create A Linked Workspace For The Active Git Project.",
        &["Mod+Shift+N"],
        true
    ),
    binding!(
        "findInFiles",
        "Find In Files",
        Workspace,
        "Open Workspace Search.",
        &["Mod+Shift+F"],
        true
    ),
    binding!(
        "replaceInFiles",
        "Replace In Files",
        Workspace,
        "Open Workspace Search And Replace.",
        &["Mod+Shift+H"],
        true
    ),
    binding!(
        "saveFile",
        "Save File",
        Workspace,
        "Save The Active Editor File.",
        &["Mod+S"],
        false
    ),
    binding!(
        "newTerminalTab",
        "New Terminal Tab",
        Tabs,
        "Open A Terminal Tab In The Active Workspace.",
        &["Mod+T"],
        false
    ),
    binding!(
        "closeTab",
        "Close Tab",
        Tabs,
        "Close The Active Terminal Tab.",
        &["Mod+W"],
        false
    ),
    binding!(
        "nextTab",
        "Next Tab",
        Tabs,
        "Select The Next Tab In The Active Pane.",
        &["Mod+Shift+BracketRight", "Ctrl+Tab"],
        &["Ctrl+Tab"],
        false
    ),
    binding!(
        "previousTab",
        "Previous Tab",
        Tabs,
        "Select The Previous Tab In The Active Pane.",
        &["Mod+Shift+BracketLeft", "Ctrl+Shift+Tab"],
        &["Ctrl+Shift+Tab"],
        false
    ),
    binding!(
        "goToTab1",
        "Go To Tab 1",
        Tabs,
        "Select The First Tab In The Active Pane.",
        &["Mod+1"],
        false
    ),
    binding!(
        "goToTab2",
        "Go To Tab 2",
        Tabs,
        "Select The Second Tab In The Active Pane.",
        &["Mod+2"],
        false
    ),
    binding!(
        "goToTab3",
        "Go To Tab 3",
        Tabs,
        "Select The Third Tab In The Active Pane.",
        &["Mod+3"],
        false
    ),
    binding!(
        "goToTab4",
        "Go To Tab 4",
        Tabs,
        "Select The Fourth Tab In The Active Pane.",
        &["Mod+4"],
        false
    ),
    binding!(
        "goToTab5",
        "Go To Tab 5",
        Tabs,
        "Select The Fifth Tab In The Active Pane.",
        &["Mod+5"],
        false
    ),
    binding!(
        "goToTab6",
        "Go To Tab 6",
        Tabs,
        "Select The Sixth Tab In The Active Pane.",
        &["Mod+6"],
        false
    ),
    binding!(
        "goToTab7",
        "Go To Tab 7",
        Tabs,
        "Select The Seventh Tab In The Active Pane.",
        &["Mod+7"],
        false
    ),
    binding!(
        "goToTab8",
        "Go To Tab 8",
        Tabs,
        "Select The Eighth Tab In The Active Pane.",
        &["Mod+8"],
        false
    ),
    binding!(
        "goToTab9",
        "Go To Last Tab",
        Tabs,
        "Select The Last Tab In The Active Pane.",
        &["Mod+9"],
        false
    ),
    binding!(
        "splitRight",
        "Split Right",
        Panes,
        "Split The Active Pane To The Right With A New Terminal.",
        &["Mod+D"],
        &["Mod+Shift+D"],
        false
    ),
    binding!(
        "splitDown",
        "Split Down",
        Panes,
        "Split The Active Pane Downward With A New Terminal.",
        &["Mod+Shift+D"],
        &["Mod+Alt+D"],
        false
    ),
    binding!(
        "closeSplit",
        "Close Split",
        Panes,
        "Merge The Active Pane Back Into Its Sibling.",
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
