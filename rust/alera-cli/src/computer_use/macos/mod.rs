pub mod ax_action;
pub mod ax_attributes;
pub mod ax_tree;
pub mod macos_capabilities;
pub mod running_apps;
pub mod tcc_permissions;

use async_trait::async_trait;
use uuid::Uuid;

use crate::computer_use::action_contract::{
    ActionOutcome, ActionRequest, ActionTarget, UnverifiedReason, Verification,
};
use crate::computer_use::action_gate;
use crate::computer_use::blocked_apps::ensure_app_allowed;
use crate::computer_use::contract::{AppInfo, Capabilities, PermissionsReport};
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::snapshot_contract::{Snapshot, WindowInfo, WINDOW_COORDINATE_SPACE};
use crate::computer_use::snapshot_registry;
use crate::computer_use::tree_render::{render_window_tree, DEFAULT_BUDGET};
use crate::computer_use::{provider_name, ComputerUseProvider, SnapshotRequest};
use ax_tree::AxApplication;

/// Reads and drives desktop UI through the macOS accessibility API.
pub struct MacosProvider;

impl MacosProvider {
    pub fn new() -> Self {
        MacosProvider
    }

    /// Refuse early when the grant is missing.
    ///
    /// Without it every attribute read returns an API-disabled error, and the
    /// agent would see an empty tree rather than the one thing it can act on.
    fn require_accessibility(&self) -> ComputerResult<()> {
        if tcc_permissions::accessibility_granted() {
            return Ok(());
        }
        Err(ComputerError::new(
            ComputerErrorCode::PermissionDenied,
            tcc_permissions::accessibility_hint(),
        ))
    }

    /// Run one accessibility operation on a blocking thread.
    ///
    /// The AX API is synchronous and talks to another process per call, so a tree
    /// read would otherwise stall every other host request.
    async fn blocking<T, F>(work: F) -> ComputerResult<T>
    where
        T: Send + 'static,
        F: FnOnce() -> ComputerResult<T> + Send + 'static,
    {
        tokio::task::spawn_blocking(work).await.map_err(|error| {
            ComputerError::new(
                ComputerErrorCode::AccessibilityError,
                format!("The accessibility worker did not finish: {error}"),
            )
        })?
    }
}

impl Default for MacosProvider {
    fn default() -> Self {
        MacosProvider::new()
    }
}

#[async_trait]
impl ComputerUseProvider for MacosProvider {
    async fn handshake(&self) -> ComputerResult<Capabilities> {
        Ok(macos_capabilities::capabilities(
            tcc_permissions::accessibility_granted(),
            provider_name(),
        ))
    }

    async fn permissions(&self) -> ComputerResult<PermissionsReport> {
        Ok(PermissionsReport {
            platform: std::env::consts::OS.to_string(),
            items: tcc_permissions::permission_items(),
        })
    }

    async fn list_apps(&self) -> ComputerResult<Vec<AppInfo>> {
        self.require_accessibility()?;
        Self::blocking(running_apps::list_apps).await
    }

    async fn list_windows(&self, app: &AppInfo) -> ComputerResult<Vec<WindowInfo>> {
        self.require_accessibility()?;
        ensure_app_allowed(app)?;
        let app = app.clone();
        Self::blocking(move || {
            let application = AxApplication::for_pid(app.pid)?;
            Ok(application
                .windows()
                .iter()
                .enumerate()
                .map(|(index, window)| application.window_info(window, index))
                .collect())
        })
        .await
    }

    async fn snapshot(&self, request: SnapshotRequest<'_>) -> ComputerResult<Snapshot> {
        self.require_accessibility()?;
        ensure_app_allowed(request.app)?;
        if request.window_id.is_some() {
            return Err(ComputerError::new(
                ComputerErrorCode::UnsupportedCapability,
                "The macOS accessibility API exposes no reusable window handle. Address windows \
                 by index."
                    .to_string(),
            ));
        }
        let app = request.app.clone();
        let window_index = request.window_index;
        let include_screenshot = request.include_screenshot;
        Self::blocking(move || {
            let application = AxApplication::for_pid(app.pid)?;
            let index = match window_index {
                Some(index) => index,
                None => application.default_window_index(&app)?,
            };
            observe(&application, &app, index, include_screenshot)
        })
        .await
    }

    async fn act(&self, request: ActionRequest<'_>) -> ComputerResult<ActionOutcome> {
        self.require_accessibility()?;
        ensure_app_allowed(request.app)?;
        let (element, window_index) = snapshot_registry::resolve_element(
            &request.namespace,
            request.app,
            request.element.snapshot_id.as_deref(),
            request.element.index,
        )?;
        // One pointer, one focus, one window stack.
        let _gate = action_gate::hold().await;
        let app = request.app.clone();
        let target = request.target.clone();
        let include_screenshot = request.include_screenshot;
        let (performed, snapshot) = Self::blocking(move || {
            let application = AxApplication::for_pid(app.pid)?;
            let window = application.window_element(&app, window_index)?;
            let node = ax_tree::node_at_path(&window, &element.path)?;
            ax_action::ensure_still_matches(&node, &element)?;
            let performed = match &target {
                ActionTarget::Click => ax_action::click(&node)?,
                ActionTarget::SetValue { value } => ax_action::set_value(&node, value)?,
                ActionTarget::PerformAction { action } => ax_action::perform_named(&node, action)?,
            };
            let snapshot = observe(&application, &app, window_index, include_screenshot).ok();
            Ok((performed, snapshot))
        })
        .await?;
        if let Some(snapshot) = &snapshot {
            snapshot_registry::remember(&request.namespace, snapshot);
        }
        let verification = match snapshot {
            Some(_) => performed.verification,
            None => Verification::Unverified {
                reason: UnverifiedReason::WindowChanged,
            },
        };
        Ok(ActionOutcome {
            path: performed.path,
            action_name: performed.action_name,
            fallback_reason: performed.fallback_reason,
            verification,
            snapshot,
        })
    }
}

fn observe(
    application: &AxApplication,
    app: &AppInfo,
    window_index: usize,
    include_screenshot: bool,
) -> ComputerResult<Snapshot> {
    let (root, window) = application.read_window(app, window_index, DEFAULT_BUDGET.max_nodes)?;
    // Frames are converted to window-local by the reader, so the renderer is told
    // not to subtract the window origin a second time.
    let rendered = render_window_tree(&root, None, DEFAULT_BUDGET);
    Ok(Snapshot {
        snapshot_id: Uuid::new_v4().to_string(),
        app: app.clone(),
        window,
        coordinate_space: WINDOW_COORDINATE_SPACE,
        tree_text: rendered.tree_text,
        element_count: rendered.elements.len(),
        focused_element_index: rendered.focused_element_index,
        truncation: rendered.truncation,
        screenshot: None,
        screenshot_error: include_screenshot.then(screenshot_detail),
        elements: rendered.elements,
    })
}

fn screenshot_detail() -> String {
    "Screen capture is not implemented on macOS yet, and its Screen Recording grant is not \
     requested. Read the accessibility tree instead."
        .to_string()
}
