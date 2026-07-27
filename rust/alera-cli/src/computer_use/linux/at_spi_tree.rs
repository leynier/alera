use atspi::connection::AccessibilityConnection;
use atspi::proxy::accessible::{AccessibleProxy, ObjectRefExt as _};
use atspi::proxy::proxy_ext::ProxyExt as _;
use atspi::zbus::Connection;
use atspi::{CoordType, State};

use crate::computer_use::contract::AppInfo;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::snapshot_contract::{RawNode, Rect, WindowInfo};

/// Roles AT-SPI uses for top-level windows.
const WINDOW_ROLES: &[&str] = &["frame", "window", "dialog", "alert", "file chooser"];

/// A live connection to the session's accessibility bus.
pub struct AtSpiSession {
    connection: AccessibilityConnection,
}

impl AtSpiSession {
    pub async fn connect() -> ComputerResult<Self> {
        let connection = AccessibilityConnection::new().await.map_err(|error| {
            ComputerError::new(
                ComputerErrorCode::AccessibilityError,
                format!(
                    "Could not reach the accessibility bus: {error}. \
                     Install and start at-spi2-core, then retry."
                ),
            )
        })?;
        Ok(AtSpiSession { connection })
    }

    /// Applications that own at least one window.
    ///
    /// An application with no window is running but has nothing to drive, and
    /// listing it would only give the agent a name that cannot be observed.
    pub async fn list_apps(&self) -> ComputerResult<Vec<AppInfo>> {
        let root = self.root().await?;
        let mut apps = Vec::new();
        for child in children_of(self.bus(), &root).await {
            let name = text_or_default(child.name().await);
            let pid = process_id(self.bus(), &child).await;
            if pid == 0 {
                continue;
            }
            if children_of(self.bus(), &child).await.is_empty() {
                continue;
            }
            apps.push(AppInfo {
                name,
                // AT-SPI exposes no application identifier, only a display
                // name, so agents match apps by name on Linux.
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

    /// The windows of one application, in the order agents address by index.
    pub async fn list_windows(&self, app: &AppInfo) -> ComputerResult<Vec<WindowInfo>> {
        let windows = self.window_proxies(app).await?;
        let mut infos = Vec::new();
        for (index, window) in windows.iter().enumerate() {
            infos.push(WindowInfo {
                // AT-SPI has no stable window handle; the index is the address.
                id: None,
                index,
                title: text_or_default(window.name().await),
                bounds: window_bounds(window).await,
                is_active: has_state(window, State::Active).await,
            });
        }
        Ok(infos)
    }

    /// Read one window's subtree into the platform-independent node form.
    ///
    /// `max_nodes` bounds the D-Bus round trips, not just the output: every
    /// field of every node is a call, and a file manager with ten thousand rows
    /// would otherwise take minutes to walk.
    pub async fn read_window(
        &self,
        app: &AppInfo,
        window_index: usize,
        max_nodes: usize,
    ) -> ComputerResult<(RawNode, WindowInfo)> {
        let windows = self.window_proxies(app).await?;
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
        let info = WindowInfo {
            id: None,
            index: window_index,
            title: text_or_default(window.name().await),
            bounds: window_bounds(window).await,
            is_active: has_state(window, State::Active).await,
        };
        let mut budget = max_nodes;
        let node = self.read_node(window, info.bounds, &mut budget).await;
        Ok((node, info))
    }

    /// Pick the window an agent means when it named none.
    ///
    /// The active window first, then any window that is actually showing: a
    /// minimised window has geometry and a title but nothing an agent can read.
    pub async fn default_window_index(&self, app: &AppInfo) -> ComputerResult<usize> {
        let windows = self.window_proxies(app).await?;
        if windows.is_empty() {
            return Err(ComputerError::new(
                ComputerErrorCode::WindowNotFound,
                format!("`{}` has no windows to observe.", app.name),
            ));
        }
        for (index, window) in windows.iter().enumerate() {
            if has_state(window, State::Active).await {
                return Ok(index);
            }
        }
        for (index, window) in windows.iter().enumerate() {
            if has_state(window, State::Showing).await {
                return Ok(index);
            }
        }
        Ok(0)
    }

    /// The proxy for one window, so an action can walk down to its target.
    pub async fn window_proxy(
        &self,
        app: &AppInfo,
        window_index: usize,
    ) -> ComputerResult<AccessibleProxy<'_>> {
        let windows = self.window_proxies(app).await?;
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

    /// Walk a path of child indexes down from a node.
    ///
    /// A path that no longer resolves means the tree lost nodes above the target,
    /// which is the same situation as a changed signature and gets the same
    /// answer: re-read.
    pub async fn node_at_path<'a>(
        &'a self,
        root: &AccessibleProxy<'a>,
        path: &[usize],
    ) -> ComputerResult<AccessibleProxy<'a>> {
        let mut current = root.clone();
        for step in path {
            let children = children_of(self.bus(), &current).await;
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

    fn bus(&self) -> &Connection {
        self.connection.connection()
    }

    async fn root(&self) -> ComputerResult<AccessibleProxy<'_>> {
        self.connection
            .root_accessible_on_registry()
            .await
            .map_err(|error| {
                ComputerError::new(
                    ComputerErrorCode::AccessibilityError,
                    format!("The accessibility registry did not answer: {error}"),
                )
            })
    }

    async fn window_proxies(&self, app: &AppInfo) -> ComputerResult<Vec<AccessibleProxy<'_>>> {
        let root = self.root().await?;
        for child in children_of(self.bus(), &root).await {
            if process_id(self.bus(), &child).await != app.pid {
                continue;
            }
            let mut windows = Vec::new();
            for window in children_of(self.bus(), &child).await {
                let role = text_or_default(window.get_role_name().await).to_lowercase();
                if WINDOW_ROLES.contains(&role.as_str()) {
                    windows.push(window);
                }
            }
            return Ok(windows);
        }
        Err(ComputerError::new(
            ComputerErrorCode::AppNotFound,
            format!(
                "`{}` (pid {}) is no longer on the accessibility bus.",
                app.name, app.pid
            ),
        ))
    }

    /// Read one node and its descendants.
    ///
    /// Errors on individual fields are swallowed into defaults on purpose: a
    /// toolkit that refuses one property should cost the agent that property,
    /// not the whole window.
    async fn read_node(
        &self,
        proxy: &AccessibleProxy<'_>,
        window_bounds: Option<Rect>,
        budget: &mut usize,
    ) -> RawNode {
        let mut node = RawNode {
            role: text_or_default(proxy.get_role_name().await),
            name: text_or_default(proxy.name().await),
            description: non_empty(text_or_default(proxy.description().await)),
            ..RawNode::default()
        };
        if let Ok(states) = proxy.get_state().await {
            node.focused = states.contains(State::Focused);
            node.selected = states.contains(State::Selected);
        }
        // AT-SPI has no "protected" state: a concealed field is identified by
        // its `password text` role, which the shared secure-node rules already
        // recognise, so nothing is set here.
        node.frame = node_frame(proxy, window_bounds).await;
        if let Ok(proxies) = proxy.proxies().await {
            if let Ok(action) = proxies.action().await {
                if let Ok(actions) = action.get_actions().await {
                    node.actions =
                        distinct_action_names(actions.into_iter().map(|action| action.name));
                }
            }
            if let Ok(value) = proxies.value().await {
                if let Ok(text) = value.text().await {
                    node.value = non_empty(text);
                }
            }
            if node.value.is_none() {
                if let Ok(text) = proxies.text().await {
                    if let Ok(contents) = text.get_text(0, -1).await {
                        node.value = non_empty(contents);
                    }
                }
            }
        }
        for child in children_of(self.bus(), proxy).await {
            if *budget == 0 {
                break;
            }
            *budget -= 1;
            node.children
                .push(Box::pin(self.read_node(&child, window_bounds, budget)).await);
        }
        node
    }
}

/// The children of a node, tied to the connection rather than to the parent
/// proxy.
///
/// A child borrowed from its parent could not outlive the loop that produced it,
/// which is exactly what walking a tree has to do.
async fn children_of<'c>(
    connection: &'c Connection,
    proxy: &AccessibleProxy<'_>,
) -> Vec<AccessibleProxy<'c>> {
    let Ok(refs) = proxy.get_children().await else {
        return Vec::new();
    };
    let mut children = Vec::new();
    for object in refs {
        if object.is_null() {
            continue;
        }
        if let Ok(child) = object.into_accessible_proxy(connection).await {
            children.push(child);
        }
    }
    children
}

/// The operating-system process id behind an accessible object.
///
/// Asked of the bus rather than of the application: AT-SPI's own
/// `Application.Id` is a registry index, not a pid, and reporting it as one
/// would hand agents a `pid:` selector that names the wrong process, or a
/// process that does not exist.
async fn process_id(connection: &Connection, proxy: &AccessibleProxy<'_>) -> u32 {
    let Ok(dbus) = atspi::zbus::fdo::DBusProxy::new(connection).await else {
        return 0;
    };
    let destination = proxy.inner().destination().to_owned();
    dbus.get_connection_unix_process_id(destination)
        .await
        .unwrap_or(0)
}

/// A window's own rectangle, in screen coordinates.
async fn window_bounds(window: &AccessibleProxy<'_>) -> Option<Rect> {
    let proxies = window.proxies().await.ok()?;
    let component = proxies.component().await.ok()?;
    let (x, y, width, height) = component.get_extents(CoordType::Screen).await.ok()?;
    let rect = Rect::new(
        f64::from(x),
        f64::from(y),
        f64::from(width),
        f64::from(height),
    );
    (!rect.is_empty()).then_some(rect)
}

/// A node's rectangle, already window-local.
///
/// AT-SPI can report window-local extents directly, which avoids a second call
/// for the window rectangle on every node.
async fn node_frame(proxy: &AccessibleProxy<'_>, window_bounds: Option<Rect>) -> Option<Rect> {
    let proxies = proxy.proxies().await.ok()?;
    let component = proxies.component().await.ok()?;
    if let Ok((x, y, width, height)) = component.get_extents(CoordType::Window).await {
        let rect = Rect::new(
            f64::from(x),
            f64::from(y),
            f64::from(width),
            f64::from(height),
        );
        if !rect.is_empty() {
            return Some(rect);
        }
    }
    // Some toolkits only answer for screen coordinates.
    let (x, y, width, height) = component.get_extents(CoordType::Screen).await.ok()?;
    let rect = Rect::new(
        f64::from(x),
        f64::from(y),
        f64::from(width),
        f64::from(height),
    );
    if rect.is_empty() {
        return None;
    }
    Some(match window_bounds {
        Some(bounds) => rect.to_window_local(&bounds),
        None => rect,
    })
}

async fn has_state(proxy: &AccessibleProxy<'_>, state: State) -> bool {
    proxy
        .get_state()
        .await
        .map(|states| states.contains(state))
        .unwrap_or(false)
}

/// Action names with blanks and repeats removed, in the order reported.
///
/// Qt hands the same action back more than once: KRunner's buttons came back as
/// "Press, SetFocus, Press". A repeated name is not a second action an agent can
/// choose, and listing it invites `perform-secondary-action` to be called with
/// an ambiguous target.
pub(crate) fn distinct_action_names(names: impl Iterator<Item = String>) -> Vec<String> {
    let mut distinct: Vec<String> = Vec::new();
    for name in names {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            continue;
        }
        if distinct
            .iter()
            .any(|kept| kept.eq_ignore_ascii_case(trimmed))
        {
            continue;
        }
        distinct.push(trimmed.to_string());
    }
    distinct
}

fn text_or_default<E>(result: Result<String, E>) -> String {
    result.unwrap_or_default()
}

fn non_empty(text: String) -> Option<String> {
    (!text.trim().is_empty()).then_some(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn window_roles_cover_the_shapes_a_desktop_app_opens() {
        for role in ["frame", "dialog", "alert", "window"] {
            assert!(WINDOW_ROLES.contains(&role), "{role}");
        }
        // A menu is not a window: it belongs to one.
        assert!(!WINDOW_ROLES.contains(&"menu"));
        assert!(!WINDOW_ROLES.contains(&"panel"));
    }

    #[test]
    fn blank_text_becomes_absent_rather_than_empty() {
        assert_eq!(non_empty("  ".to_string()), None);
        assert_eq!(non_empty(String::new()), None);
        assert_eq!(non_empty("Play".to_string()), Some("Play".to_string()));
    }

    #[test]
    fn a_refused_property_reads_as_empty_rather_than_failing() {
        let refused: Result<String, ()> = Err(());
        assert_eq!(text_or_default(refused), "");
        assert_eq!(text_or_default(Ok::<_, ()>("Play".to_string())), "Play");
    }

    /// Observed against KRunner, whose buttons report "Press, SetFocus, Press".
    #[test]
    fn repeated_action_names_are_reported_once() {
        let names = ["Press", "SetFocus", "Press", "press", "  ", ""]
            .into_iter()
            .map(str::to_string);
        assert_eq!(
            distinct_action_names(names),
            vec!["Press".to_string(), "SetFocus".to_string()]
        );
    }

    #[test]
    fn action_order_is_preserved_so_the_first_stays_the_primary_one() {
        let names = ["Toggle", "Press", "SetFocus"]
            .into_iter()
            .map(str::to_string);
        assert_eq!(
            distinct_action_names(names),
            vec![
                "Toggle".to_string(),
                "Press".to_string(),
                "SetFocus".to_string()
            ]
        );
    }
}
