use objc2_application_services::AXUIElement;
use objc2_core_foundation::CFRetained;

use crate::computer_use::contract::AppInfo;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::macos::ax_attributes::{
    action_names, attribute, bool_attribute, element_children, element_frame, number_as_string,
    screen_rect, string_attribute,
};
use crate::computer_use::snapshot_contract::{RawNode, Rect, WindowInfo};

/// Reads the accessibility tree of one application.
pub struct AxApplication {
    element: CFRetained<AXUIElement>,
    pid: i32,
}

impl AxApplication {
    /// The accessibility element for a running process.
    pub fn for_pid(pid: u32) -> ComputerResult<Self> {
        let pid = i32::try_from(pid).map_err(|_| {
            ComputerError::invalid_argument(format!("`{pid}` is not a valid process id."))
        })?;
        // SAFETY: takes a pid by value and returns an owned element or null.
        let element = unsafe { AXUIElement::new_application(pid) };
        Ok(AxApplication { element, pid })
    }

    /// The application's windows, in the order agents address by index.
    pub fn windows(&self) -> Vec<CFRetained<AXUIElement>> {
        match attribute(&self.element, "AXWindows") {
            Some(_) => window_children(&self.element),
            // An application that has not finished launching answers nothing.
            None => Vec::new(),
        }
    }

    pub fn window_info(&self, window: &AXUIElement, index: usize) -> WindowInfo {
        WindowInfo {
            // macOS exposes no accessibility window handle an agent could reuse,
            // so the index is the address here too.
            id: None,
            index,
            title: string_attribute(window, "AXTitle").unwrap_or_default(),
            bounds: screen_rect(window),
            is_active: bool_attribute(window, "AXMain").unwrap_or(false),
        }
    }

    /// Read one window into the platform-independent node form.
    pub fn read_window(
        &self,
        app: &AppInfo,
        window_index: usize,
        max_nodes: usize,
    ) -> ComputerResult<(RawNode, WindowInfo)> {
        let windows = self.windows();
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
        let node = read_node(window, info.bounds, &mut budget);
        Ok((node, info))
    }

    /// The window an agent means when it named none: the main one, else the first.
    pub fn default_window_index(&self, app: &AppInfo) -> ComputerResult<usize> {
        let windows = self.windows();
        if windows.is_empty() {
            return Err(ComputerError::new(
                ComputerErrorCode::WindowNotFound,
                format!("`{}` has no windows to observe.", app.name),
            ));
        }
        Ok(windows
            .iter()
            .position(|window| bool_attribute(window, "AXMain").unwrap_or(false))
            .unwrap_or(0))
    }

    pub fn window_element(
        &self,
        app: &AppInfo,
        window_index: usize,
    ) -> ComputerResult<CFRetained<AXUIElement>> {
        let windows = self.windows();
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

    pub fn pid(&self) -> i32 {
        self.pid
    }
}

/// Walk a path of child indexes from a node.
pub fn node_at_path(root: &AXUIElement, path: &[usize]) -> ComputerResult<CFRetained<AXUIElement>> {
    // SAFETY: retaining the borrowed root so the walk owns every step uniformly.
    let mut current = unsafe { CFRetained::retain(std::ptr::NonNull::from(root)) };
    for step in path {
        let children = element_children(&current);
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

/// The role in the words the shared role rules expect.
///
/// macOS prefixes every role with `AX` and camel-cases it, so `AXCheckBox`
/// becomes `check box`, matching the AT-SPI spelling one set of lists serves.
pub fn role_of(element: &AXUIElement) -> String {
    normalize_role(&string_attribute(element, "AXRole").unwrap_or_default())
}

/// `AXCheckBox` becomes `check box`.
pub fn normalize_role(raw: &str) -> String {
    let trimmed = raw.strip_prefix("AX").unwrap_or(raw);
    if trimmed.is_empty() {
        return "unknown".to_string();
    }
    let mut out = String::with_capacity(trimmed.len() + 4);
    for (index, character) in trimmed.chars().enumerate() {
        if character.is_uppercase() && index > 0 {
            out.push(' ');
        }
        out.extend(character.to_lowercase());
    }
    out
}

fn read_node(element: &AXUIElement, window_bounds: Option<Rect>, budget: &mut usize) -> RawNode {
    let role = role_of(element);
    let mut node = RawNode {
        name: element_name(element),
        description: string_attribute(element, "AXDescription")
            .filter(|text| !text.trim().is_empty()),
        focused: bool_attribute(element, "AXFocused").unwrap_or(false),
        selected: bool_attribute(element, "AXSelected").unwrap_or(false),
        // macOS marks a secure field by its role rather than a flag, and the
        // shared rules already recognise `password text` through the role name.
        frame: element_frame(element, window_bounds),
        actions: action_names(element),
        value: element_value(element),
        role,
        ..RawNode::default()
    };
    for child in element_children(element) {
        if *budget == 0 {
            break;
        }
        *budget -= 1;
        node.children.push(read_node(&child, window_bounds, budget));
    }
    node
}

/// The best label an element has.
///
/// `AXTitle` is the usual one, but toolbar buttons and images often carry only a
/// description, and leaving those unnamed would give the agent a row of
/// indistinguishable buttons.
fn element_name(element: &AXUIElement) -> String {
    for attribute_name in ["AXTitle", "AXLabel", "AXDescription"] {
        if let Some(text) = string_attribute(element, attribute_name) {
            if !text.trim().is_empty() {
                return text;
            }
        }
    }
    String::new()
}

fn element_value(element: &AXUIElement) -> Option<String> {
    if let Some(text) = string_attribute(element, "AXValue") {
        return (!text.trim().is_empty()).then_some(text);
    }
    number_as_string(element, "AXValue")
}

/// Windows reported by the application element.
fn window_children(application: &AXUIElement) -> Vec<CFRetained<AXUIElement>> {
    use objc2_core_foundation::{CFArray, CFRetained as Retained};
    let Some(value) = attribute(application, "AXWindows") else {
        return Vec::new();
    };
    let Some(array) = value.downcast_ref::<CFArray>() else {
        return Vec::new();
    };
    let mut windows = Vec::new();
    for index in 0..array.count() {
        // SAFETY: index is bounded by the array's own count.
        let raw = unsafe { array.value_at_index(index) };
        if raw.is_null() {
            continue;
        }
        let Some(pointer) = std::ptr::NonNull::new(raw.cast::<AXUIElement>().cast_mut()) else {
            continue;
        };
        // SAFETY: CFArray lends its elements, so retain before handing out.
        windows.push(unsafe { Retained::retain(pointer) });
    }
    windows
}

#[cfg(test)]
mod tests {
    use super::normalize_role;

    /// The role has to arrive in the same shape AT-SPI uses, because one set of
    /// role lists decides elision and redaction for every platform.
    #[test]
    fn ax_roles_are_spelled_the_way_the_shared_lists_expect() {
        assert_eq!(normalize_role("AXCheckBox"), "check box");
        assert_eq!(normalize_role("AXButton"), "button");
        assert_eq!(normalize_role("AXTextField"), "text field");
        assert_eq!(normalize_role("AXStaticText"), "static text");
        assert_eq!(normalize_role("AXWindow"), "window");
    }

    #[test]
    fn an_unknown_role_is_named_rather_than_left_blank() {
        assert_eq!(normalize_role("AX"), "unknown");
        assert_eq!(normalize_role(""), "unknown");
    }
}
