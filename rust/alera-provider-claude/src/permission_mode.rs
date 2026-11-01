//! Full Access under Claude settings that forbid it, as T3 Code: a launch
//! that asks for `bypassPermissions` while Claude's settings disable it
//! steps down to `auto`, or to `default` when auto is disabled too, and
//! says so once in a notice. The session is never refused, and the
//! advertised runtime modes do not change, because the settings depend on
//! the cwd and the CLI enforces them anyway.

use super::*;
use crate::claude_settings::bypass_availability;
use crate::skills::SkillEnvironment;

pub(crate) const BYPASS_STEP_DOWN_NOTICE: &str =
    "Alera could not confirm Claude bypass permissions here, so Full Access is running with approval checks.";

const BYPASS: &str = "bypassPermissions";
const DEFAULT: &str = "default";

/// Steps a launch that asks for bypass down when the settings disable it.
/// Returns whether it did.
pub(crate) fn step_down_bypass(options: &mut ClaudeAgentOptions) -> bool {
    if options.permission_mode.as_deref() != Some(BYPASS) {
        return false;
    }
    let environment = SkillEnvironment::new(options, options.cwd.as_deref());
    let availability = bypass_availability(&environment, options.setting_sources.as_deref());
    if !availability.bypass_disabled {
        return false;
    }
    let mode = if availability.auto_disabled {
        DEFAULT
    } else {
        "auto"
    };
    options.permission_mode = Some(mode.into());
    true
}

/// The launch permission mode, which default turns return to after a plan
/// turn, and whether a Full Access step-down still needs its notice.
#[derive(Debug, Default)]
pub(crate) struct LaunchPermission {
    base_mode: Option<String>,
    requested_bypass: bool,
    init_seen: bool,
    notice_pending: bool,
    announced: bool,
}

impl LaunchPermission {
    pub(crate) fn new(
        options: &ClaudeAgentOptions,
        plan_at_start: bool,
        stepped_down: bool,
    ) -> Self {
        let mode = options.permission_mode.clone();
        Self {
            requested_bypass: stepped_down || mode.as_deref() == Some(BYPASS),
            base_mode: if plan_at_start {
                Some(DEFAULT.into())
            } else {
                mode
            },
            notice_pending: stepped_down,
            ..Self::default()
        }
    }

    pub(crate) fn base_mode(&self) -> &str {
        self.base_mode.as_deref().unwrap_or(DEFAULT)
    }

    fn fall_back_to_default(&mut self) {
        self.base_mode = Some(DEFAULT.into());
        self.notice_pending = self.requested_bypass && !self.announced;
    }

    /// Adopts the mode `system/init` reports: the first report, and any
    /// later one that shows the CLI refused bypass. Returns whether a notice
    /// is now due.
    pub(crate) fn adopt_reported(&mut self, reported: &str, plan_active: bool) -> bool {
        let known = matches!(
            reported,
            DEFAULT | "acceptEdits" | BYPASS | "dontAsk" | "auto"
        );
        if plan_active || !known {
            return false;
        }
        let first = !std::mem::replace(&mut self.init_seen, true);
        let refused = self.base_mode() == BYPASS && reported != BYPASS;
        if first || refused {
            self.base_mode = Some(reported.to_owned());
        }
        if refused && self.requested_bypass && !self.announced {
            self.notice_pending = true;
        }
        self.notice_pending
    }

    fn take_notice(&mut self) -> bool {
        let pending = std::mem::take(&mut self.notice_pending);
        if pending {
            self.announced = true;
        }
        pending
    }
}

impl ClaudeProvider {
    fn permission_notice(&mut self) -> Option<ProviderEvent> {
        if !self.permission.take_notice() {
            return None;
        }
        let payload = json!({
            "message": BYPASS_STEP_DOWN_NOTICE,
            "detail": {
                "requestedPermissionMode": BYPASS,
                "permissionMode": self.permission.base_mode(),
            },
        });
        Some(self.event(
            EventKind::RuntimeWarning,
            payload.clone(),
            self.raw_from(PERMISSION_SOURCE, "permission_mode", payload),
        ))
    }

    pub(super) fn queue_permission_notice(&mut self) {
        if let Some(event) = self.permission_notice() {
            self.queue(event);
        }
    }

    /// Returns a default turn to the launch mode. When the CLI refuses a
    /// bypass or auto mode the settings now forbid, the turn runs in
    /// `default` with a notice instead of failing.
    pub(super) async fn restore_launch_permission_mode(&mut self) -> Result<(), ProviderError> {
        let base = self.permission.base_mode().to_owned();
        let client = self
            .client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("session client is unavailable".into()))?;
        match client.set_permission_mode(&base).await {
            Ok(_) => Ok(()),
            Err(_) if matches!(base.as_str(), BYPASS | "auto") => {
                client
                    .set_permission_mode(DEFAULT)
                    .await
                    .map_err(sdk_error)?;
                self.permission.fall_back_to_default();
                Ok(())
            }
            Err(error) => Err(sdk_error(error)),
        }
    }

    pub(super) fn adopt_reported_permission_mode(
        &mut self,
        payload: &Value,
    ) -> Option<ProviderEvent> {
        let reported = payload.get("permissionMode").and_then(Value::as_str)?;
        let plan_active = self.plan_interaction.load(Ordering::SeqCst);
        if !self.permission.adopt_reported(reported, plan_active) {
            return None;
        }
        self.permission_notice()
    }
}

#[cfg(test)]
#[path = "permission_mode_tests.rs"]
mod tests;
