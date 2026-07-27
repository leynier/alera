use uiautomation::controls::ControlType;
use uiautomation::patterns::{UISelectionItemPattern, UITogglePattern, UIValuePattern};
use uiautomation::{UIAutomation, UIElement, UITreeWalker};

use crate::computer_use::contract::AppInfo;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::snapshot_contract::{RawNode, Rect, WindowInfo};

/// A connection to the UI Automation service.
pub struct UiaSession {
    automation: UIAutomation,
    walker: UITreeWalker,
}

impl UiaSession {
    pub fn connect() -> ComputerResult<Self> {
        let automation = UIAutomation::new().map_err(|error| {
            ComputerError::new(
                ComputerErrorCode::AccessibilityError,
                format!("Could not reach UI Automation: {error}"),
            )
        })?;
        // The control view rather than the raw view: the raw tree is full of
        // layout nodes no agent would ever address, and Windows already knows
        // which of them are controls.
        let walker = automation.get_control_view_walker().map_err(|error| {
            ComputerError::new(
                ComputerErrorCode::AccessibilityError,
                format!("UI Automation would not open a tree walker: {error}"),
            )
        })?;
        Ok(UiaSession { automation, walker })
    }

    /// Applications that own at least one top-level window.
    ///
    /// Grouped by process, because UI Automation reports one node per window
    /// while an agent names an application.
    pub fn list_apps(&self) -> ComputerResult<Vec<AppInfo>> {
        let mut apps: Vec<AppInfo> = Vec::new();
        for window in self.top_level_windows()? {
            let Ok(pid) = window.get_process_id() else {
                continue;
            };
            if apps.iter().any(|app| app.pid == pid) {
                continue;
            }
            apps.push(AppInfo {
                name: process_name(pid).unwrap_or_else(|| window_title(&window)),
                // Windows has no bundle identifier; the executable name is the
                // closest stable thing and it is already the display name.
                bundle_id: None,
                pid,
            });
        }
        apps.sort_by(|left, right| {
            left.name
                .to_lowercase()
                .cmp(&right.name.to_lowercase())
                .then(left.pid.cmp(&right.pid))
        });
        Ok(apps)
    }

    pub fn list_windows(&self, app: &AppInfo) -> ComputerResult<Vec<WindowInfo>> {
        Ok(self
            .windows_of(app)?
            .iter()
            .enumerate()
            .map(|(index, window)| self.window_info(window, index))
            .collect())
    }

    /// Read one window's subtree.
    pub fn read_window(
        &self,
        app: &AppInfo,
        window_index: usize,
        max_nodes: usize,
    ) -> ComputerResult<(RawNode, WindowInfo)> {
        let windows = self.windows_of(app)?;
        let window = windows.get(window_index).ok_or_else(|| {
            ComputerError::new(
                ComputerErrorCode::WindowNotFound,
                format!(
                    "`{}` has {} window(s), so index {window_index} does not exist.",
                    app.name,
                    windows.len()
                ),
            )
        })?;
        let info = self.window_info(window, window_index);
        let mut budget = max_nodes;
        let node = self.read_node(window, info.bounds, &mut budget);
        Ok((node, info))
    }

    /// The window an agent means when it named none: the foreground one, else the
    /// first that is actually on screen.
    pub fn default_window_index(&self, app: &AppInfo) -> ComputerResult<usize> {
        let windows = self.windows_of(app)?;
        if windows.is_empty() {
            return Err(ComputerError::new(
                ComputerErrorCode::WindowNotFound,
                format!("`{}` has no windows to observe.", app.name),
            ));
        }
        let focused = self.automation.get_focused_element().ok();
        if let Some(focused) = focused {
            let focused_pid = focused.get_process_id().unwrap_or(0);
            if focused_pid == app.pid {
                if let Some(index) = windows
                    .iter()
                    .position(|window| self.contains_focus(window, &focused))
                {
                    return Ok(index);
                }
            }
        }
        Ok(windows
            .iter()
            .position(|window| !window.is_offscreen().unwrap_or(false))
            .unwrap_or(0))
    }

    /// The element a cached path points at.
    pub fn node_at_path(&self, root: &UIElement, path: &[usize]) -> ComputerResult<UIElement> {
        let mut current = root.clone();
        for step in path {
            let children = self.children_of(&current);
            let count = children.len();
            current = children.into_iter().nth(*step).ok_or_else(|| {
                ComputerError::new(
                    ComputerErrorCode::ElementNotFound,
                    format!(
                        "The element is gone: its parent now has {count} child(ren), so child \
                         {step} does not exist. Re-read the app state."
                    ),
                )
            })?;
        }
        Ok(current)
    }

    pub fn window_element(&self, app: &AppInfo, window_index: usize) -> ComputerResult<UIElement> {
        let windows = self.windows_of(app)?;
        let count = windows.len();
        windows.into_iter().nth(window_index).ok_or_else(|| {
            ComputerError::new(
                ComputerErrorCode::WindowNotFound,
                format!(
                    "`{}` has {count} window(s), so index {window_index} does not exist.",
                    app.name
                ),
            )
        })
    }

    fn window_info(&self, window: &UIElement, index: usize) -> WindowInfo {
        WindowInfo {
            // The window handle is stable on Windows, so agents may address by it.
            id: window.get_native_window_handle().ok().map(window_handle_id),
            index,
            title: window_title(window),
            bounds: element_rect(window),
            is_active: window.has_keyboard_focus().unwrap_or(false)
                || self
                    .automation
                    .get_focused_element()
                    .ok()
                    .is_some_and(|focused| self.contains_focus(window, &focused)),
        }
    }

    fn top_level_windows(&self) -> ComputerResult<Vec<UIElement>> {
        let root = self.automation.get_root_element().map_err(|error| {
            ComputerError::new(
                ComputerErrorCode::AccessibilityError,
                format!("UI Automation would not return the desktop: {error}"),
            )
        })?;
        Ok(self
            .children_of(&root)
            .into_iter()
            .filter(|element| {
                matches!(
                    element.get_control_type(),
                    Ok(ControlType::Window) | Ok(ControlType::Pane)
                )
            })
            .collect())
    }

    fn windows_of(&self, app: &AppInfo) -> ComputerResult<Vec<UIElement>> {
        let windows: Vec<UIElement> = self
            .top_level_windows()?
            .into_iter()
            .filter(|window| window.get_process_id().unwrap_or(0) == app.pid)
            .collect();
        if windows.is_empty() {
            return Err(ComputerError::new(
                ComputerErrorCode::AppNotFound,
                format!(
                    "`{}` (pid {}) no longer has a window on this desktop.",
                    app.name, app.pid
                ),
            ));
        }
        Ok(windows)
    }

    /// How many children an element has in the control view.
    ///
    /// Counted through the same walker the reader used, so a signature is
    /// computed over the tree shape the agent was actually shown.
    pub fn child_count(&self, element: &UIElement) -> usize {
        self.children_of(element).len()
    }

    /// Siblings in tree order, which is what an element path indexes.
    fn children_of(&self, element: &UIElement) -> Vec<UIElement> {
        let mut children = Vec::new();
        let Ok(mut child) = self.walker.get_first_child(element) else {
            return children;
        };
        loop {
            children.push(child.clone());
            match self.walker.get_next_sibling(&child) {
                Ok(next) => child = next,
                Err(_) => break,
            }
            // A malformed provider could loop forever; the tree budget upstream
            // bounds the whole read, but a sibling chain has its own ceiling.
            if children.len() >= MAX_SIBLINGS {
                break;
            }
        }
        children
    }

    fn read_node(
        &self,
        element: &UIElement,
        window_bounds: Option<Rect>,
        budget: &mut usize,
    ) -> RawNode {
        let mut node = RawNode {
            role: role_of(element),
            name: element.get_name().unwrap_or_default(),
            description: non_empty(element.get_help_text().unwrap_or_default()),
            focused: element.has_keyboard_focus().unwrap_or(false),
            ..RawNode::default()
        };
        node.frame = element_rect(element).map(|rect| match window_bounds {
            Some(bounds) => rect.to_window_local(&bounds),
            None => rect,
        });
        if let Ok(value) = element.get_pattern::<UIValuePattern>() {
            node.value = value.get_value().ok().and_then(non_empty);
        }
        if let Ok(selection) = element.get_pattern::<UISelectionItemPattern>() {
            node.selected = selection.is_selected().unwrap_or(false);
        }
        // Windows says outright whether a field holds protected content, which is
        // better than any word list: a password box is an ordinary `Edit` whose
        // IsPassword property is set.
        node.protected = element.is_password().unwrap_or(false);
        node.actions = available_actions(element);
        for child in self.children_of(element) {
            if *budget == 0 {
                break;
            }
            *budget -= 1;
            node.children
                .push(self.read_node(&child, window_bounds, budget));
        }
        node
    }

    fn contains_focus(&self, window: &UIElement, focused: &UIElement) -> bool {
        if self
            .automation
            .compare_elements(window, focused)
            .unwrap_or(false)
        {
            return true;
        }
        // Walk up from the focused element: comparing subtrees downward would
        // mean reading the whole window just to answer this.
        let mut current = focused.clone();
        for _ in 0..MAX_FOCUS_ANCESTRY {
            let Ok(parent) = self.walker.get_parent(&current) else {
                return false;
            };
            if self
                .automation
                .compare_elements(window, &parent)
                .unwrap_or(false)
            {
                return true;
            }
            current = parent;
        }
        false
    }
}

/// Ceiling on one sibling chain, so a provider that never ends a chain cannot
/// hang the read.
const MAX_SIBLINGS: usize = 2_000;
/// How far up to look for the focused element's window.
const MAX_FOCUS_ANCESTRY: usize = 64;

/// The actions an element offers, named as the skill documents them.
///
/// UI Automation exposes capabilities as patterns rather than a list of action
/// names, so the names are derived from the patterns the element implements.
pub(crate) fn available_actions(element: &UIElement) -> Vec<String> {
    let mut actions = Vec::new();
    if element
        .get_pattern::<uiautomation::patterns::UIInvokePattern>()
        .is_ok()
    {
        actions.push("Invoke".to_string());
    }
    if element.get_pattern::<UITogglePattern>().is_ok() {
        actions.push("Toggle".to_string());
    }
    if let Ok(value) = element.get_pattern::<UIValuePattern>() {
        if !value.is_readonly().unwrap_or(true) {
            actions.push("SetValue".to_string());
        }
    }
    if element.get_pattern::<UISelectionItemPattern>().is_ok() {
        actions.push("Select".to_string());
    }
    if element.is_keyboard_focusable().unwrap_or(false) {
        actions.push("SetFocus".to_string());
    }
    actions
}

/// The control type in the words the shared role rules expect.
///
/// Lowercased with spaces so one set of role lists serves both platforms: UI
/// Automation says `CheckBox` where AT-SPI says `check box`.
pub(crate) fn role_of(element: &UIElement) -> String {
    match element.get_control_type() {
        Ok(control_type) => spaced_lowercase(&format!("{control_type:?}")),
        Err(_) => element
            .get_localized_control_type()
            .unwrap_or_else(|_| "unknown".to_string())
            .to_lowercase(),
    }
}

/// `CheckBox` becomes `check box`, `Edit` becomes `edit`.
fn spaced_lowercase(camel: &str) -> String {
    let mut out = String::with_capacity(camel.len() + 4);
    for (index, character) in camel.chars().enumerate() {
        if character.is_uppercase() && index > 0 {
            out.push(' ');
        }
        out.extend(character.to_lowercase());
    }
    out
}

/// An HWND as the number an agent can pass back.
///
/// The handle is a pointer, so it goes through `isize` rather than being cast
/// straight to `i64`; the value only has to round-trip, not be dereferenced.
fn window_handle_id(handle: uiautomation::types::Handle) -> i64 {
    handle.as_ref().0 as isize as i64
}

fn window_title(window: &UIElement) -> String {
    window.get_name().unwrap_or_default()
}

fn element_rect(element: &UIElement) -> Option<Rect> {
    let rect = element.get_bounding_rectangle().ok()?;
    let width = f64::from(rect.get_right() - rect.get_left());
    let height = f64::from(rect.get_bottom() - rect.get_top());
    let rect = Rect::new(
        f64::from(rect.get_left()),
        f64::from(rect.get_top()),
        width,
        height,
    );
    (!rect.is_empty()).then_some(rect)
}

/// The executable name behind a pid, which is what an agent recognises.
fn process_name(pid: u32) -> Option<String> {
    let mut system = sysinfo::System::new();
    let pid = sysinfo::Pid::from_u32(pid);
    system.refresh_processes_specifics(
        sysinfo::ProcessesToUpdate::Some(&[pid]),
        true,
        sysinfo::ProcessRefreshKind::nothing(),
    );
    let name = system.process(pid)?.name().to_string_lossy().to_string();
    // Trim the extension: an agent asks for "Notepad", not "Notepad.exe".
    Some(
        name.strip_suffix(".exe")
            .or_else(|| name.strip_suffix(".EXE"))
            .unwrap_or(&name)
            .to_string(),
    )
}

fn non_empty(text: String) -> Option<String> {
    (!text.trim().is_empty()).then_some(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One set of role lists serves both platforms, so the control type has to
    /// arrive in the same shape AT-SPI uses.
    #[test]
    fn control_types_are_spelled_the_way_the_shared_role_lists_expect() {
        assert_eq!(spaced_lowercase("CheckBox"), "check box");
        assert_eq!(spaced_lowercase("Button"), "button");
        assert_eq!(spaced_lowercase("Edit"), "edit");
        assert_eq!(spaced_lowercase("TabItem"), "tab item");
        assert_eq!(spaced_lowercase("ListItem"), "list item");
    }

    #[test]
    fn a_single_word_type_is_only_lowercased() {
        assert_eq!(spaced_lowercase("Pane"), "pane");
        assert_eq!(spaced_lowercase(""), "");
    }

    #[test]
    fn blank_text_becomes_absent() {
        assert_eq!(non_empty("   ".to_string()), None);
        assert_eq!(non_empty("Play".to_string()), Some("Play".to_string()));
    }
}
