use serde::Serialize;

use crate::computer_use::contract::AppInfo;

/// A rectangle in window-local coordinates.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl Rect {
    pub fn new(x: f64, y: f64, width: f64, height: f64) -> Self {
        Rect {
            x,
            y,
            width,
            height,
        }
    }

    /// The centre point, which is where a synthetic click lands.
    pub fn center(&self) -> (f64, f64) {
        (self.x + self.width / 2.0, self.y + self.height / 2.0)
    }

    pub fn is_empty(&self) -> bool {
        self.width <= 0.0 || self.height <= 0.0
    }

    /// Translate a screen rectangle into the target window's coordinate space.
    ///
    /// Everything the agent receives is window-local: screen coordinates go
    /// stale the moment the user moves the window, and the agent is only ever
    /// looking at one window.
    pub fn to_window_local(self, window: &Rect) -> Rect {
        Rect::new(
            self.x - window.x,
            self.y - window.y,
            self.width,
            self.height,
        )
    }
}

/// One window of a running application.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowInfo {
    /// Absent where the platform exposes no stable handle. AT-SPI is such a
    /// platform, so agents address windows by index there.
    pub id: Option<i64>,
    pub index: usize,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bounds: Option<Rect>,
    pub is_active: bool,
}

/// What a platform provider reports for one accessibility node, before any
/// budget, elision, or redaction is applied.
///
/// Providers build this tree and hand it over; every rule that shapes what the
/// agent finally reads is platform independent and tested on its own.
#[derive(Debug, Clone, Default)]
pub struct RawNode {
    pub role: String,
    pub name: String,
    pub value: Option<String>,
    pub description: Option<String>,
    /// Accessibility action names, in the platform's own words.
    pub actions: Vec<String>,
    /// Window-local frame, absent when the node has no usable geometry.
    pub frame: Option<Rect>,
    pub focused: bool,
    /// The platform marked this node as holding concealed text.
    pub protected: bool,
    pub selected: bool,
    pub children: Vec<RawNode>,
}

impl RawNode {
    /// A node with just a role, for tests and for providers filling in fields.
    pub fn new(role: impl Into<String>) -> Self {
        RawNode {
            role: role.into(),
            ..RawNode::default()
        }
    }

    pub fn named(role: impl Into<String>, name: impl Into<String>) -> Self {
        RawNode {
            role: role.into(),
            name: name.into(),
            ..RawNode::default()
        }
    }

    pub fn with_children(mut self, children: Vec<RawNode>) -> Self {
        self.children = children;
        self
    }
}

/// One element the agent can address, as it appears in the rendered tree.
#[derive(Debug, Clone)]
pub struct ElementRecord {
    /// The number the agent passes back. Short-lived, and sparse: compaction
    /// removes elements after numbering, so gaps are expected.
    pub index: usize,
    pub role: String,
    pub name: String,
    pub value: Option<String>,
    pub actions: Vec<String>,
    pub frame: Option<Rect>,
    /// Child indexes from the window down to this node, which is how the
    /// element is found again in a freshly observed tree.
    pub path: Vec<usize>,
    /// Identity check for that path, so a tree that changed shape is caught
    /// instead of acted on.
    pub signature: String,
    pub redacted: bool,
}

/// How much of the tree had to be left out.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Truncation {
    pub truncated: bool,
    pub max_nodes: usize,
    pub max_depth: usize,
    pub max_depth_reached: bool,
}

/// A captured screenshot, referenced by path.
///
/// The bytes never travel in the payload: a base64 image would dominate the
/// agent's context, and the file is what a human or a vision model opens.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScreenshotInfo {
    pub path: String,
    pub width: u32,
    pub height: u32,
    /// Captured size over original size. The agent divides screenshot pixels by
    /// this to get action coordinates.
    pub scale: f64,
    pub expires_at: String,
}

/// One observation of one window: the tree the agent reads and, unless it asked
/// otherwise, a screenshot to look at.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub snapshot_id: String,
    pub app: AppInfo,
    pub window: WindowInfo,
    /// Always `window`. Present so the agent never has to assume it.
    pub coordinate_space: &'static str,
    pub tree_text: String,
    /// How many elements the tree holds. Not a bound on the indexes: never
    /// derive an index from this.
    pub element_count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub focused_element_index: Option<usize>,
    pub truncation: Truncation,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub screenshot: Option<ScreenshotInfo>,
    /// Why capture failed, when it did. Separate from the error channel because
    /// a snapshot without pixels is still a usable snapshot.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub screenshot_error: Option<String>,
    /// The addressable elements, kept host-side for the next action and never
    /// sent: the agent addresses them through `tree_text`.
    #[serde(skip)]
    pub elements: Vec<ElementRecord>,
}

pub const WINDOW_COORDINATE_SPACE: &str = "window";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_rect_reports_its_center() {
        assert_eq!(Rect::new(10.0, 20.0, 100.0, 50.0).center(), (60.0, 45.0));
    }

    #[test]
    fn degenerate_rects_are_empty() {
        assert!(Rect::new(0.0, 0.0, 0.0, 10.0).is_empty());
        assert!(Rect::new(0.0, 0.0, 10.0, -1.0).is_empty());
        assert!(!Rect::new(0.0, 0.0, 1.0, 1.0).is_empty());
    }

    /// A window-local frame must not move when the window does, which is the
    /// whole reason coordinates are reported this way.
    #[test]
    fn screen_rects_convert_to_window_local_coordinates() {
        let window = Rect::new(100.0, 200.0, 800.0, 600.0);
        let button = Rect::new(150.0, 260.0, 40.0, 20.0);
        let local = button.to_window_local(&window);
        assert_eq!(local, Rect::new(50.0, 60.0, 40.0, 20.0));

        let moved_window = Rect::new(300.0, 400.0, 800.0, 600.0);
        let moved_button = Rect::new(350.0, 460.0, 40.0, 20.0);
        assert_eq!(moved_button.to_window_local(&moved_window), local);
    }

    #[test]
    fn snapshots_serialize_with_camel_case_keys() {
        let snapshot = Snapshot {
            snapshot_id: "s1".to_string(),
            app: AppInfo {
                name: "Spotify".to_string(),
                bundle_id: None,
                pid: 3,
            },
            window: WindowInfo {
                id: None,
                index: 0,
                title: "Spotify".to_string(),
                bounds: Some(Rect::new(0.0, 0.0, 10.0, 10.0)),
                is_active: true,
            },
            coordinate_space: WINDOW_COORDINATE_SPACE,
            tree_text: "0 window Spotify".to_string(),
            element_count: 1,
            focused_element_index: Some(0),
            truncation: Truncation {
                truncated: false,
                max_nodes: 1200,
                max_depth: 64,
                max_depth_reached: false,
            },
            screenshot: None,
            screenshot_error: None,
            elements: Vec::new(),
        };
        let value = serde_json::to_value(&snapshot).unwrap();
        assert_eq!(value["snapshotId"], "s1");
        assert_eq!(value["coordinateSpace"], "window");
        assert_eq!(value["treeText"], "0 window Spotify");
        assert_eq!(value["elementCount"], 1);
        assert_eq!(value["focusedElementIndex"], 0);
        assert!(value["truncation"].get("maxDepthReached").is_some());
    }

    /// The element records are the host's own bookkeeping. Sending them would
    /// duplicate the whole tree in the agent's context for no gain.
    #[test]
    fn element_records_never_reach_the_client() {
        let snapshot = Snapshot {
            snapshot_id: "s1".to_string(),
            app: AppInfo {
                name: "a".to_string(),
                bundle_id: None,
                pid: 1,
            },
            window: WindowInfo {
                id: None,
                index: 0,
                title: String::new(),
                bounds: None,
                is_active: false,
            },
            coordinate_space: WINDOW_COORDINATE_SPACE,
            tree_text: String::new(),
            element_count: 1,
            focused_element_index: None,
            truncation: Truncation {
                truncated: false,
                max_nodes: 1,
                max_depth: 1,
                max_depth_reached: false,
            },
            screenshot: None,
            screenshot_error: None,
            elements: vec![ElementRecord {
                index: 0,
                role: "button".to_string(),
                name: "Play".to_string(),
                value: None,
                actions: Vec::new(),
                frame: None,
                path: vec![0],
                signature: "sig".to_string(),
                redacted: false,
            }],
        };
        let value = serde_json::to_value(&snapshot).unwrap();
        assert!(value.get("elements").is_none());
        assert!(value.get("focusedElementIndex").is_none());
        assert!(value.get("bounds").is_none());
    }
}
