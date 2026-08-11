use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::Duration;

use super::android::{self, AndroidAttached, AndroidSdk, AndroidStream};
use super::contract::{EmulatorDevice, EmulatorFailure, EmulatorPlatform, EmulatorResult};
use super::ios::{self, IosAttached, IosBackend, IosHelper};
use super::video_server::VideoRegistry;
use serde_json::{json, Value};

mod actions;
mod helper_lifecycle;
mod session_queries;
mod snapshot_proof;
mod support;

use snapshot_proof::SnapshotProof;
use support::*;

enum AttachedDevice {
    Android(Box<AndroidAttached>),
    Ios(IosAttached),
}

enum StreamHelper {
    Android(AndroidStream),
    Ios(IosHelper),
}

struct EmulatorSession {
    workspace_id: String,
    tab_id: String,
    platform: EmulatorPlatform,
    device_id: String,
    device_name: String,
    attached: AttachedDevice,
    helper: Option<StreamHelper>,
    stream_url: Option<String>,
    generation: u64,
    leases: HashSet<u64>,
    active_pointer: Option<ActivePointer>,
}

#[derive(Clone, Copy)]
struct ActivePointer {
    client_id: u64,
    x: f64,
    y: f64,
}

const SNAPSHOT_TTL: Duration = Duration::from_secs(600);

pub struct EmulatorManager {
    android: AndroidSdk,
    ios: IosBackend,
    video: VideoRegistry,
    snapshot_dir: PathBuf,
    sessions: HashMap<String, EmulatorSession>,
    snapshots: HashMap<String, SnapshotProof>,
}

impl EmulatorManager {
    pub async fn new(runtime_dir: &Path) -> EmulatorResult<Self> {
        let snapshot_dir = runtime_dir.join("emulator-snapshots");
        std::fs::create_dir_all(&snapshot_dir).map_err(|error| {
            EmulatorFailure::new(
                "permission_denied",
                format!("Could not create the private screenshot directory: {error}"),
                ["Check permissions for the Alera runtime directory."],
            )
        })?;
        sweep_snapshot_directory(&snapshot_dir);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            let _ = std::fs::set_permissions(&snapshot_dir, std::fs::Permissions::from_mode(0o700));
        }
        Ok(Self {
            android: AndroidSdk::discover(),
            ios: IosBackend,
            video: VideoRegistry::bind().await?,
            snapshot_dir,
            sessions: HashMap::new(),
            snapshots: HashMap::new(),
        })
    }

    pub async fn capabilities(&self) -> Value {
        let android = match self.android.validate_stream_dependency() {
            Ok(()) => self.android.list_devices().await,
            Err(error) => Err(error),
        };
        let ios_supported = IosBackend::supported();
        let ios = if ios_supported {
            match self.ios.validate_stream_dependency() {
                Ok(()) => self.ios.list_devices().await,
                Err(error) => Err(error),
            }
        } else {
            Ok(Vec::new())
        };
        json!({
            "ok": true,
            "kind": "emulatorCapabilities",
            "platforms": {
                "android": backend_capability(
                    android.as_ref().ok(),
                    android.as_ref().err().map(|error| error.message.as_str()),
                    &["stream", "snapshot", "tap", "gesture", "type", "key", "button", "rotate",
                      "install", "launch", "permission", "logcat"],
                ),
                "ios": backend_capability(
                    ios.as_ref().ok().filter(|_| ios_supported),
                    if ios_supported {
                        ios.as_ref().err().map(|error| error.message.as_str())
                    } else {
                        Some("iOS requires an Apple Silicon macOS host.")
                    },
                    &["stream", "snapshot", "tap", "gesture", "type", "key", "button", "rotate",
                      "install", "launch"],
                ),
            },
            "coordinateSpace": "normalized",
            "origin": "topLeft",
        })
    }

    pub async fn devices(
        &self,
        platform: Option<EmulatorPlatform>,
    ) -> EmulatorResult<Vec<EmulatorDevice>> {
        match platform {
            Some(EmulatorPlatform::Android) => self.android.list_devices().await,
            Some(EmulatorPlatform::Ios) => self.ios.list_devices().await,
            None => {
                let android = self.android.list_devices().await;
                let ios = self.ios.list_devices().await;
                combine_device_results(android, ios)
            }
        }
    }

    pub async fn attach(
        &mut self,
        workspace_id: String,
        tab_id: String,
        platform: EmulatorPlatform,
        device_id: String,
    ) -> EmulatorResult<Value> {
        if let Some(session) = self.sessions.get(&tab_id) {
            if session.platform != platform || session.device_id != device_id {
                return Err(EmulatorFailure::new(
                    "invalid_argument",
                    "This workspace already has an emulator tab for another device.",
                    ["Close the existing emulator tab before selecting another device."],
                ));
            }
            return Ok(session_value(session));
        }
        if self
            .sessions
            .values()
            .any(|session| session.platform == platform && session.device_id == device_id)
        {
            return Err(EmulatorFailure::new(
                "device_in_use",
                "This virtual device is already attached to another workspace.",
                ["Close its existing emulator tab before attaching it elsewhere."],
            ));
        }
        let (attached, device_name) = match platform {
            EmulatorPlatform::Android => {
                let attached = self.android.attach(&device_id).await?;
                let name = attached.device_name.clone();
                (AttachedDevice::Android(Box::new(attached)), name)
            }
            EmulatorPlatform::Ios => {
                let attached = self.ios.attach(&device_id).await?;
                let name = attached.name.clone();
                (AttachedDevice::Ios(attached), name)
            }
        };
        let session = EmulatorSession {
            workspace_id,
            tab_id: tab_id.clone(),
            platform,
            device_id,
            device_name,
            attached,
            helper: None,
            stream_url: None,
            generation: 1,
            leases: HashSet::new(),
            active_pointer: None,
        };
        let value = session_value(&session);
        self.sessions.insert(tab_id, session);
        Ok(value)
    }

    pub async fn acquire(&mut self, tab_id: &str, client_id: u64) -> EmulatorResult<(Value, bool)> {
        let helper_restarted = self.ensure_helper(tab_id).await?;
        let session = self.session_mut(tab_id)?;
        session.leases.insert(client_id);
        Ok((session_value(session), helper_restarted))
    }

    pub async fn release(&mut self, tab_id: &str, client_id: u64) -> EmulatorResult<Value> {
        let should_park = {
            let session = self.session_mut(tab_id)?;
            session.leases.remove(&client_id);
            session.leases.is_empty()
        };
        if should_park {
            self.park(tab_id).await
        } else {
            Ok(session_value(self.session(tab_id)?))
        }
    }

    pub async fn release_client(&mut self, client_id: u64, park_all: bool) {
        let active_pointer_tabs = self
            .sessions
            .iter()
            .filter(|(_, session)| {
                session
                    .active_pointer
                    .is_some_and(|pointer| pointer.client_id == client_id)
            })
            .map(|(tab_id, _)| tab_id.clone())
            .collect::<Vec<_>>();
        for tab_id in active_pointer_tabs {
            self.end_active_pointer(&tab_id).await;
        }
        let tab_ids = self
            .sessions
            .iter_mut()
            .filter_map(|(tab_id, session)| {
                session.leases.remove(&client_id).then(|| tab_id.clone())
            })
            .collect::<Vec<_>>();
        if park_all {
            for session in self.sessions.values_mut() {
                session.leases.clear();
            }
            self.park_all().await;
            return;
        }
        for tab_id in tab_ids {
            if self
                .sessions
                .get(&tab_id)
                .is_some_and(|session| session.leases.is_empty())
            {
                let _ = self.park(&tab_id).await;
            }
        }
    }

    pub async fn park(&mut self, tab_id: &str) -> EmulatorResult<Value> {
        self.end_active_pointer(tab_id).await;
        let helper = self.session_mut(tab_id)?.helper.take();
        self.video.remove(tab_id).await;
        stop_helper(&self.android, self.session(tab_id)?, helper).await;
        let session = self.session_mut(tab_id)?;
        session.stream_url = None;
        Ok(session_value(session))
    }

    pub async fn park_if_unleased(&mut self, tab_id: &str) {
        if self
            .sessions
            .get(tab_id)
            .is_some_and(|session| session.leases.is_empty() && session.helper.is_some())
        {
            let _ = self.park(tab_id).await;
        }
    }

    pub async fn cancel_pointer(&mut self, tab_id: &str, client_id: u64) {
        if self
            .sessions
            .get(tab_id)
            .and_then(|session| session.active_pointer)
            .is_some_and(|pointer| pointer.client_id == client_id)
        {
            self.end_active_pointer(tab_id).await;
        }
    }

    pub async fn close_tab(&mut self, tab_id: &str) -> Vec<String> {
        self.end_active_pointer(tab_id).await;
        let Some(mut session) = self.sessions.remove(tab_id) else {
            return Vec::new();
        };
        let result = match &mut session.attached {
            AttachedDevice::Android(attached) => self.android.shutdown(attached).await,
            AttachedDevice::Ios(attached) => self.ios.shutdown(attached).await,
        };
        match result {
            Ok(()) => {
                self.video.remove(tab_id).await;
                let helper = session.helper.take();
                stop_helper(&self.android, &session, helper).await;
                self.remove_snapshot_proofs_for_tab(tab_id);
                Vec::new()
            }
            Err(error) => {
                self.sessions.insert(tab_id.to_string(), session);
                vec![error.message]
            }
        }
    }

    pub async fn close_workspace(&mut self, workspace_id: &str) -> Vec<String> {
        let tab_ids: Vec<String> = self
            .sessions
            .values()
            .filter(|session| session.workspace_id == workspace_id)
            .map(|session| session.tab_id.clone())
            .collect();
        let mut warnings = Vec::new();
        for tab_id in tab_ids {
            warnings.extend(self.close_tab(&tab_id).await);
        }
        warnings
    }

    pub async fn dispose(&mut self) {
        let tab_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for tab_id in tab_ids {
            let _ = self.close_tab(&tab_id).await;
        }
    }

    pub fn active_count(&self) -> usize {
        self.sessions.len()
    }

    pub fn contains(&self, tab_id: &str) -> bool {
        self.sessions.contains_key(tab_id)
    }

    #[cfg(test)]
    pub(crate) fn insert_owned_android_session_for_shutdown_failure_test(
        &mut self,
        workspace_id: &str,
        tab_id: &str,
        missing_adb: PathBuf,
    ) {
        self.android.adb = missing_adb;
        self.sessions.insert(
            tab_id.to_string(),
            EmulatorSession {
                workspace_id: workspace_id.to_string(),
                tab_id: tab_id.to_string(),
                platform: EmulatorPlatform::Android,
                device_id: "android:test-device".to_string(),
                device_name: "Test Device".to_string(),
                attached: AttachedDevice::Android(Box::new(AndroidAttached {
                    device_name: "Test Device".to_string(),
                    serial: "emulator-5554".to_string(),
                    owned: true,
                    process: None,
                })),
                helper: None,
                stream_url: None,
                generation: 1,
                leases: HashSet::new(),
                active_pointer: None,
            },
        );
    }

    pub async fn park_all(&mut self) {
        let tab_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for tab_id in tab_ids {
            let _ = self.park(&tab_id).await;
        }
    }

    pub fn list(&self, workspace_id: Option<&str>) -> Value {
        let items: Vec<Value> = self
            .sessions
            .values()
            .filter(|session| workspace_id.is_none_or(|id| session.workspace_id == id))
            .map(session_value)
            .collect();
        json!({"ok": true, "kind": "emulatorSessions", "items": items})
    }

    async fn end_active_pointer(&mut self, tab_id: &str) {
        let Some(pointer) = self
            .sessions
            .get(tab_id)
            .and_then(|session| session.active_pointer)
        else {
            return;
        };
        let result = match self
            .sessions
            .get(tab_id)
            .and_then(|session| session.helper.as_ref())
        {
            Some(StreamHelper::Android(stream)) => {
                android::pointer(stream, "end", pointer.x, pointer.y).await
            }
            Some(StreamHelper::Ios(helper)) => {
                ios::pointer(helper, "end", pointer.x, pointer.y).await
            }
            None => Ok(()),
        };
        if let Some(session) = self.sessions.get_mut(tab_id) {
            session.active_pointer = None;
        }
        let _ = result;
        let _ = self.invalidate_snapshots(tab_id);
    }

    fn remove_snapshot_proofs_for_tab(&mut self, tab_id: &str) {
        self.snapshots.retain(|_, proof| {
            let keep = proof.tab_id != tab_id;
            if !keep {
                remove_screenshot(proof.screenshot_path.as_deref());
            }
            keep
        });
    }

    fn session(&self, tab_id: &str) -> EmulatorResult<&EmulatorSession> {
        self.sessions.get(tab_id).ok_or_else(|| {
            EmulatorFailure::new(
                "no_active_emulator",
                "No active emulator is attached to that tab.",
                ["Attach the tab to a virtual device and retry."],
            )
        })
    }

    fn session_mut(&mut self, tab_id: &str) -> EmulatorResult<&mut EmulatorSession> {
        self.sessions.get_mut(tab_id).ok_or_else(|| {
            EmulatorFailure::new(
                "no_active_emulator",
                "No active emulator is attached to that tab.",
                ["Attach the tab to a virtual device and retry."],
            )
        })
    }
}

#[cfg(test)]
#[path = "manager_tests.rs"]
mod tests;
