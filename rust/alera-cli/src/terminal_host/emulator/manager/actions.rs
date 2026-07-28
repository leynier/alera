use serde_json::Value;

use super::{
    android, android_serial, ios, AttachedDevice, EmulatorFailure, EmulatorManager, EmulatorResult,
    StreamHelper,
};
use crate::terminal_host::emulator::contract::{require_normalized, GesturePoint};

impl EmulatorManager {
    pub async fn tap(
        &mut self,
        tab_id: &str,
        snapshot_id: Option<&str>,
        x: f64,
        y: f64,
    ) -> EmulatorResult<()> {
        self.validate_snapshot_state(tab_id, snapshot_id).await?;
        validate_coordinates(x, y)?;
        self.invalidate_snapshots(tab_id)?;
        self.ensure_helper(tab_id).await?;
        match self.session(tab_id)?.helper.as_ref() {
            Some(StreamHelper::Android(stream)) => android::tap(stream, x, y).await,
            Some(StreamHelper::Ios(helper)) => ios::tap(helper, x, y).await,
            None => unreachable!(),
        }
    }

    pub async fn pointer(
        &mut self,
        tab_id: &str,
        client_id: u64,
        kind: &str,
        x: f64,
        y: f64,
    ) -> EmulatorResult<()> {
        self.require_interactive_lease(tab_id, client_id)?;
        validate_coordinates(x, y)?;
        self.ensure_helper(tab_id).await?;
        match kind {
            "begin" if self.session(tab_id)?.active_pointer.is_some() => {
                return Err(EmulatorFailure::new(
                    "pointer_busy",
                    "Another pointer gesture is already active for this emulator.",
                    ["Finish or cancel the active gesture before starting another one."],
                ));
            }
            "move" | "end"
                if self
                    .session(tab_id)?
                    .active_pointer
                    .is_none_or(|pointer| pointer.client_id != client_id) =>
            {
                return Err(EmulatorFailure::new(
                    "pointer_not_active",
                    "This client does not own an active pointer gesture.",
                    ["Start the gesture with a pointer begin event and retry."],
                ));
            }
            "begin" | "move" | "end" => {}
            _ => return Err(EmulatorFailure::invalid("Unknown pointer event type.")),
        }
        self.invalidate_snapshots(tab_id)?;
        match self.session(tab_id)?.helper.as_ref() {
            Some(StreamHelper::Android(stream)) => android::pointer(stream, kind, x, y).await,
            Some(StreamHelper::Ios(helper)) => ios::pointer(helper, kind, x, y).await,
            None => unreachable!(),
        }?;
        let session = self.session_mut(tab_id)?;
        if kind == "end" {
            session.active_pointer = None;
        } else {
            session.active_pointer = Some(super::ActivePointer { client_id, x, y });
        }
        Ok(())
    }

    pub async fn gesture(
        &mut self,
        tab_id: &str,
        snapshot_id: Option<&str>,
        points: &[GesturePoint],
        duration_ms: u64,
    ) -> EmulatorResult<()> {
        self.validate_snapshot_state(tab_id, snapshot_id).await?;
        for point in points {
            validate_coordinates(point.x, point.y)?;
        }
        self.invalidate_snapshots(tab_id)?;
        self.ensure_helper(tab_id).await?;
        match self.session(tab_id)?.helper.as_ref() {
            Some(StreamHelper::Android(stream)) => {
                android::gesture(stream, points, duration_ms).await
            }
            Some(StreamHelper::Ios(helper)) => ios::gesture(helper, points, duration_ms).await,
            None => unreachable!(),
        }
    }

    pub async fn type_text(
        &mut self,
        tab_id: &str,
        snapshot_id: Option<&str>,
        text: &str,
    ) -> EmulatorResult<()> {
        self.validate_snapshot_state(tab_id, snapshot_id).await?;
        self.invalidate_snapshots(tab_id)?;
        self.ensure_helper(tab_id).await?;
        match self.session(tab_id)?.helper.as_ref() {
            Some(StreamHelper::Android(stream)) => android::type_text(stream, text).await,
            Some(StreamHelper::Ios(helper)) => ios::type_text(helper, text).await,
            None => unreachable!(),
        }
    }

    pub async fn type_text_interactive(
        &mut self,
        tab_id: &str,
        client_id: u64,
        text: &str,
    ) -> EmulatorResult<()> {
        self.require_interactive_lease(tab_id, client_id)?;
        self.invalidate_snapshots(tab_id)?;
        self.ensure_helper(tab_id).await?;
        match self.session(tab_id)?.helper.as_ref() {
            Some(StreamHelper::Android(stream)) => android::type_text(stream, text).await,
            Some(StreamHelper::Ios(helper)) => ios::type_text(helper, text).await,
            None => unreachable!(),
        }
    }

    pub async fn key_interactive(
        &mut self,
        tab_id: &str,
        client_id: u64,
        name: &str,
    ) -> EmulatorResult<()> {
        self.require_interactive_lease(tab_id, client_id)?;
        self.invalidate_snapshots(tab_id)?;
        self.ensure_helper(tab_id).await?;
        match self.session(tab_id)?.helper.as_ref() {
            Some(StreamHelper::Android(stream)) => android::key(stream, name).await,
            Some(StreamHelper::Ios(helper)) => ios::key(helper, name).await,
            None => unreachable!(),
        }
    }

    pub async fn button(
        &mut self,
        tab_id: &str,
        snapshot_id: Option<&str>,
        name: &str,
    ) -> EmulatorResult<()> {
        self.validate_snapshot_state(tab_id, snapshot_id).await?;
        self.invalidate_snapshots(tab_id)?;
        self.ensure_helper(tab_id).await?;
        match self.session(tab_id)?.helper.as_ref() {
            Some(StreamHelper::Android(stream)) => android::button(stream, name).await,
            Some(StreamHelper::Ios(helper)) => ios::button(helper, name).await,
            None => unreachable!(),
        }
    }

    pub async fn rotate(
        &mut self,
        tab_id: &str,
        snapshot_id: Option<&str>,
        orientation: &str,
    ) -> EmulatorResult<()> {
        self.validate_snapshot_state(tab_id, snapshot_id).await?;
        self.invalidate_snapshots(tab_id)?;
        self.ensure_helper(tab_id).await?;
        match self.session(tab_id)?.helper.as_ref() {
            Some(StreamHelper::Android(_)) => {
                let serial = android_serial(self.session(tab_id)?)?;
                self.android.rotate(serial, orientation).await
            }
            Some(StreamHelper::Ios(helper)) => ios::rotate(helper, orientation).await,
            None => unreachable!(),
        }
    }

    pub async fn install(&mut self, tab_id: &str, path: &str) -> EmulatorResult<()> {
        self.invalidate_snapshots(tab_id)?;
        match &self.session(tab_id)?.attached {
            AttachedDevice::Android(attached) => {
                android::validate_app_path(path)?;
                android::install(&self.android, &attached.serial, path, true).await
            }
            AttachedDevice::Ios(attached) => self.ios.install(&attached.udid, path).await,
        }
    }

    pub async fn launch(
        &mut self,
        tab_id: &str,
        bundle_id: &str,
        activity: Option<&str>,
    ) -> EmulatorResult<Value> {
        self.invalidate_snapshots(tab_id)?;
        let value = match &self.session(tab_id)?.attached {
            AttachedDevice::Android(attached) => {
                android::launch(&self.android, &attached.serial, bundle_id, activity).await
            }
            AttachedDevice::Ios(attached) => {
                if activity.is_some() {
                    return Err(EmulatorFailure::unsupported(
                        "An explicit activity is available only for Android applications.",
                    ));
                }
                self.ios.launch(&attached.udid, bundle_id).await
            }
        }?;
        Ok(value)
    }

    pub async fn permission(
        &mut self,
        tab_id: &str,
        operation: &str,
        bundle_id: &str,
        permission: &str,
    ) -> EmulatorResult<()> {
        self.invalidate_snapshots(tab_id)?;
        match &self.session(tab_id)?.attached {
            AttachedDevice::Android(attached) => {
                android::permission(
                    &self.android,
                    &attached.serial,
                    operation,
                    bundle_id,
                    permission,
                )
                .await
            }
            AttachedDevice::Ios(_) => Err(EmulatorFailure::unsupported(
                "Application permission automation is Android-only in this version.",
            )),
        }
    }

    pub async fn logcat(
        &self,
        tab_id: &str,
        query: &android::AndroidLogcatQuery<'_>,
    ) -> EmulatorResult<String> {
        match &self.session(tab_id)?.attached {
            AttachedDevice::Android(attached) => {
                android::logcat(&self.android, &attached.serial, query).await
            }
            AttachedDevice::Ios(_) => Err(EmulatorFailure::unsupported(
                "Logcat is available only for Android virtual devices.",
            )),
        }
    }

    fn require_interactive_lease(&self, tab_id: &str, client_id: u64) -> EmulatorResult<()> {
        if self.session(tab_id)?.leases.contains(&client_id) {
            return Ok(());
        }
        Err(EmulatorFailure::new(
            "interactive_lease_required",
            "Interactive emulator input requires an acquired stream lease.",
            ["Acquire the emulator stream before sending interactive input."],
        ))
    }
}

fn validate_coordinates(x: f64, y: f64) -> EmulatorResult<()> {
    require_normalized(x, "x")?;
    require_normalized(y, "y")?;
    Ok(())
}
