pub mod desktop_session_probe;
pub mod uia_action;
pub mod uia_tree;
pub mod windows_capabilities;

use async_trait::async_trait;
use uuid::Uuid;

use crate::computer_use::action_contract::{
    ActionOutcome, ActionRequest, ActionTarget, UnverifiedReason, Verification,
};
use crate::computer_use::action_gate;
use crate::computer_use::blocked_apps::ensure_app_allowed;
use crate::computer_use::contract::{
    AppInfo, Capabilities, PermissionId, PermissionItem, PermissionState, PermissionsReport,
};
use crate::computer_use::error::ComputerResult;
use crate::computer_use::snapshot_contract::{Snapshot, WindowInfo, WINDOW_COORDINATE_SPACE};
use crate::computer_use::snapshot_registry;
use crate::computer_use::tree_render::{render_window_tree, DEFAULT_BUDGET};
use crate::computer_use::{provider_name, ComputerUseProvider, SnapshotRequest};
use uia_tree::UiaSession;

/// Reads and drives desktop UI through UI Automation.
pub struct WindowsProvider;

impl WindowsProvider {
    pub fn new() -> Self {
        WindowsProvider
    }

    /// Run one UI Automation operation on a blocking thread.
    ///
    /// UI Automation is COM and synchronous, and a tree read is thousands of
    /// cross-process calls. Running it on the async runtime's worker would stall
    /// every other host request for the duration.
    async fn with_session<T, F>(&self, work: F) -> ComputerResult<T>
    where
        T: Send + 'static,
        F: FnOnce(&UiaSession) -> ComputerResult<T> + Send + 'static,
    {
        tokio::task::spawn_blocking(move || {
            let session = UiaSession::connect()?;
            work(&session)
        })
        .await
        .map_err(|error| {
            crate::computer_use::error::ComputerError::new(
                crate::computer_use::error::ComputerErrorCode::AccessibilityError,
                format!("The UI Automation worker did not finish: {error}"),
            )
        })?
    }
}

impl Default for WindowsProvider {
    fn default() -> Self {
        WindowsProvider::new()
    }
}

#[async_trait]
impl ComputerUseProvider for WindowsProvider {
    async fn handshake(&self) -> ComputerResult<Capabilities> {
        // Two separate questions, and only asking the first would mislead: UI
        // Automation connects happily from session 0 and then reports an empty
        // desktop, so a host over SSH would look available and see nothing.
        if !desktop_session_probe::runs_in_interactive_session() {
            return Ok(Capabilities::unsupported(
                std::env::consts::OS,
                provider_name(),
                desktop_session_probe::interactive_session_hint(),
            ));
        }
        let reachable = tokio::task::spawn_blocking(|| UiaSession::connect().is_ok())
            .await
            .unwrap_or(false);
        Ok(windows_capabilities::capabilities(
            reachable,
            provider_name(),
        ))
    }

    async fn permissions(&self) -> ComputerResult<PermissionsReport> {
        let reachable = desktop_session_probe::runs_in_interactive_session()
            && tokio::task::spawn_blocking(|| UiaSession::connect().is_ok())
                .await
                .unwrap_or(false);
        // Windows awards no per-app grant for UI Automation: either the service
        // answered or this session has no desktop.
        let accessibility = PermissionItem {
            id: PermissionId::Accessibility,
            label: "UI Automation".to_string(),
            state: if reachable {
                PermissionState::Granted
            } else {
                PermissionState::Denied
            },
            detail: (!reachable).then(desktop_session_probe::interactive_session_hint),
        };
        let screenshots = PermissionItem {
            id: PermissionId::Screenshots,
            label: "Screen Capture".to_string(),
            state: PermissionState::NotApplicable,
            detail: Some(screenshot_detail()),
        };
        Ok(PermissionsReport {
            platform: std::env::consts::OS.to_string(),
            items: vec![accessibility, screenshots],
        })
    }

    async fn list_apps(&self) -> ComputerResult<Vec<AppInfo>> {
        self.with_session(|session| session.list_apps()).await
    }

    async fn list_windows(&self, app: &AppInfo) -> ComputerResult<Vec<WindowInfo>> {
        ensure_app_allowed(app)?;
        let app = app.clone();
        self.with_session(move |session| session.list_windows(&app))
            .await
    }

    async fn snapshot(&self, request: SnapshotRequest<'_>) -> ComputerResult<Snapshot> {
        ensure_app_allowed(request.app)?;
        let app = request.app.clone();
        let window_id = request.window_id;
        let window_index = request.window_index;
        let include_screenshot = request.include_screenshot;
        self.with_session(move |session| {
            let index = resolve_window_index(session, &app, window_id, window_index)?;
            observe(session, &app, index, include_screenshot)
        })
        .await
    }

    async fn act(&self, request: ActionRequest<'_>) -> ComputerResult<ActionOutcome> {
        ensure_app_allowed(request.app)?;
        let (element, window_index) = snapshot_registry::resolve_element(
            &request.namespace,
            request.app,
            request.element.snapshot_id.as_deref(),
            request.element.index,
        )?;
        // One pointer, one focus, one window stack: actions are serialized so two
        // callers cannot interleave into a sequence neither asked for.
        let _gate = action_gate::hold().await;
        let app = request.app.clone();
        let target = request.target.clone();
        let include_screenshot = request.include_screenshot;
        let performed = self
            .with_session(move |session| {
                let window = session.window_element(&app, window_index)?;
                let node = session.node_at_path(&window, &element.path)?;
                uia_action::ensure_still_matches(session, &node, &element)?;
                let performed = match &target {
                    ActionTarget::Click => uia_action::click(&node)?,
                    ActionTarget::SetValue { value } => uia_action::set_value(&node, value)?,
                    ActionTarget::PerformAction { action } => {
                        uia_action::perform_named(&node, action)?
                    }
                };
                let snapshot = observe(session, &app, window_index, include_screenshot).ok();
                Ok((performed, snapshot))
            })
            .await?;
        let (performed, snapshot) = performed;
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

/// Turn the caller's window selectors into an index into the app's windows.
///
/// A handle is honoured because Windows keeps them stable, which is what lets an
/// agent hold on to one window while another opens.
fn resolve_window_index(
    session: &UiaSession,
    app: &AppInfo,
    window_id: Option<i64>,
    window_index: Option<usize>,
) -> ComputerResult<usize> {
    if let Some(id) = window_id {
        let windows = session.list_windows(app)?;
        return windows
            .iter()
            .position(|window| window.id == Some(id))
            .ok_or_else(|| {
                crate::computer_use::error::ComputerError::new(
                    crate::computer_use::error::ComputerErrorCode::WindowNotFound,
                    format!(
                        "`{}` has no window with handle {id} any more. Run list-windows for a \
                         current one.",
                        app.name
                    ),
                )
            });
    }
    match window_index {
        Some(index) => Ok(index),
        None => session.default_window_index(app),
    }
}

fn observe(
    session: &UiaSession,
    app: &AppInfo,
    window_index: usize,
    include_screenshot: bool,
) -> ComputerResult<Snapshot> {
    let (root, window) = session.read_window(app, window_index, DEFAULT_BUDGET.max_nodes)?;
    // Frames arrive already window-local from the reader, so the renderer is told
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
    "Screen capture is not implemented on Windows yet. Read the accessibility tree instead."
        .to_string()
}
