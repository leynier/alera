use std::path::Path;

use serde_json::{json, Value};

use super::{
    android, AndroidSdk, AttachedDevice, EmulatorDevice, EmulatorFailure, EmulatorResult,
    EmulatorSession, StreamHelper,
};

pub(super) fn sweep_snapshot_directory(snapshot_dir: &Path) {
    let Ok(entries) = std::fs::read_dir(snapshot_dir) else {
        return;
    };
    for path in entries.flatten().map(|entry| entry.path()) {
        if path.extension().is_some_and(|extension| extension == "png") {
            let _ = std::fs::remove_file(path);
        }
    }
}

pub(super) fn remove_screenshot(path: Option<&Path>) {
    if let Some(path) = path {
        let _ = std::fs::remove_file(path);
    }
}

pub(super) fn backend_capability(
    devices: Option<&Vec<EmulatorDevice>>,
    error: Option<&str>,
    operations: &[&str],
) -> Value {
    json!({
        "available": devices.is_some(),
        "deviceCount": devices.map_or(0, Vec::len),
        "message": error.unwrap_or("Ready"),
        "operations": operations,
    })
}

pub(super) fn combine_device_results(
    android: EmulatorResult<Vec<EmulatorDevice>>,
    ios: EmulatorResult<Vec<EmulatorDevice>>,
) -> EmulatorResult<Vec<EmulatorDevice>> {
    match (android, ios) {
        (Ok(mut android), Ok(ios)) => {
            android.extend(ios);
            Ok(android)
        }
        (Ok(android), Err(_)) => Ok(android),
        (Err(_), Ok(ios)) => Ok(ios),
        (Err(android), Err(_)) => Err(android),
    }
}

pub(super) fn session_value(session: &EmulatorSession) -> Value {
    let (managed, width, height, codec) = match (&session.attached, &session.helper) {
        (AttachedDevice::Android(attached), Some(StreamHelper::Android(stream))) => {
            let (width, height) = stream.dimensions();
            (attached.owned, Some(width), Some(height), "h264")
        }
        (AttachedDevice::Android(attached), _) => (attached.owned, None, None, "h264"),
        (AttachedDevice::Ios(attached), Some(StreamHelper::Ios(helper))) => {
            let (width, height) = helper.dimensions();
            (attached.owned, Some(width), Some(height), "mjpeg")
        }
        (AttachedDevice::Ios(attached), _) => (attached.owned, None, None, "mjpeg"),
    };
    json!({
        "id": session.tab_id,
        "workspaceId": session.workspace_id,
        "tabId": session.tab_id,
        "deviceId": session.device_id,
        "deviceName": session.device_name,
        "platform": session.platform,
        "state": if session.helper.is_some() { "ready" } else { "parked" },
        "managedDevice": managed,
        "stream": {
            "state": if session.helper.is_some() { "ready" } else { "parked" },
            "codec": codec,
            "url": session.stream_url,
            "width": width,
            "height": height,
        },
    })
}

pub(super) fn android_serial(session: &EmulatorSession) -> EmulatorResult<&str> {
    match &session.attached {
        AttachedDevice::Android(attached) => Ok(&attached.serial),
        AttachedDevice::Ios(_) => Err(EmulatorFailure::unsupported(
            "This operation requires an Android virtual device.",
        )),
    }
}

pub(super) async fn stop_helper(
    android: &AndroidSdk,
    session: &EmulatorSession,
    helper: Option<StreamHelper>,
) {
    match helper {
        Some(StreamHelper::Android(stream)) => {
            if let Ok(serial) = android_serial(session) {
                android::stop_stream(android, serial, stream).await;
            }
        }
        Some(StreamHelper::Ios(helper)) => helper.stop().await,
        None => {}
    }
}
