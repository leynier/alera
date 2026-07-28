mod accessibility;
mod control;
mod helper_runtime;
mod http_body;
mod shutdown;

use std::net::Ipv6Addr;
use std::path::Path;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use serde_json::Value;
use tokio::net::TcpListener;
use tokio::process::Child;
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;

use super::contract::{EmulatorDevice, EmulatorFailure, EmulatorResult, GesturePoint};
use super::process;
use super::EmulatorPlatform;

#[derive(Debug)]
pub struct IosAttached {
    pub udid: String,
    pub name: String,
    pub owned: bool,
}

pub struct IosHelper {
    pub stream_url: String,
    pub ax_url: String,
    control_tx: mpsc::Sender<helper_runtime::ControlRequest>,
    stream_healthy: Arc<AtomicBool>,
    width: Arc<AtomicU32>,
    height: Arc<AtomicU32>,
    child: Child,
    control_task: JoinHandle<()>,
}

impl IosHelper {
    pub async fn send(&self, frame: Vec<u8>) -> EmulatorResult<()> {
        let (completion, result) = oneshot::channel();
        self.control_tx
            .send(helper_runtime::ControlRequest { frame, completion })
            .await
            .map_err(|_| {
                helper_runtime::helper_failure("The iOS control channel is no longer available.")
            })?;
        tokio::time::timeout(Duration::from_secs(5), result)
            .await
            .map_err(|_| helper_runtime::helper_failure("iOS input delivery timed out."))?
            .map_err(|_| {
                helper_runtime::helper_failure("The iOS control worker stopped unexpectedly.")
            })?
    }

    pub fn dimensions(&self) -> (u32, u32) {
        (
            self.width.load(Ordering::Relaxed),
            self.height.load(Ordering::Relaxed),
        )
    }

    pub fn is_healthy(&mut self) -> bool {
        self.stream_healthy.load(Ordering::Relaxed)
            && !self.control_task.is_finished()
            && self.child.try_wait().is_ok_and(|status| status.is_none())
    }

    pub fn stream_health(&self) -> Arc<AtomicBool> {
        self.stream_healthy.clone()
    }

    async fn refresh_dimensions(&self) -> EmulatorResult<(u32, u32)> {
        let dimensions = helper_runtime::read_dimensions(&self.stream_url).await?;
        self.width.store(dimensions.0, Ordering::Relaxed);
        self.height.store(dimensions.1, Ordering::Relaxed);
        Ok(dimensions)
    }

    pub async fn stop(mut self) {
        self.control_task.abort();
        let _ = self.child.kill().await;
    }
}

pub struct IosBackend;

impl IosBackend {
    pub fn supported() -> bool {
        cfg!(target_os = "macos") && cfg!(target_arch = "aarch64")
    }

    pub fn validate_stream_dependency(&self) -> EmulatorResult<()> {
        helper_runtime::serve_sim_path().map(drop)
    }

    pub async fn list_devices(&self) -> EmulatorResult<Vec<EmulatorDevice>> {
        if !Self::supported() {
            return Ok(Vec::new());
        }
        Ok(simctl_devices()
            .await?
            .into_iter()
            .map(|device| EmulatorDevice {
                id: format!("ios:{}", device.udid),
                platform: EmulatorPlatform::Ios,
                name: device.name,
                state: if device.state == "Booted" {
                    "booted".into()
                } else {
                    "shutdown".into()
                },
                available: device.available,
                runtime: Some(device.runtime),
            })
            .collect())
    }

    pub async fn attach(&self, device_id: &str) -> EmulatorResult<IosAttached> {
        if !Self::supported() {
            return Err(EmulatorFailure::unsupported(
                "iOS emulation requires an Apple Silicon macOS host.",
            ));
        }
        let needle = device_id.strip_prefix("ios:").unwrap_or(device_id);
        let devices = simctl_devices().await?;
        let device = devices
            .into_iter()
            .find(|candidate| candidate.udid == needle)
            .ok_or_else(|| {
                EmulatorFailure::new(
                    "device_not_found",
                    format!("iOS Simulator `{needle}` was not found."),
                    ["Create the simulator in Xcode and refresh the device list."],
                )
            })?;
        if !device.available {
            return Err(EmulatorFailure::new(
                "device_unavailable",
                format!("iOS Simulator `{}` is unavailable.", device.name),
                ["Install its platform runtime in Xcode Settings."],
            ));
        }
        let mut owned = false;
        if device.state != "Booted" {
            let boot = process::output_with_timeout(
                Path::new("xcrun"),
                &process::strings(&["simctl", "boot", &device.udid]),
                "iOS Simulator boot",
                Duration::from_secs(45),
            )
            .await;
            if boot.is_ok() {
                owned = true;
            } else {
                let raced_boot = simctl_devices()
                    .await?
                    .into_iter()
                    .any(|candidate| candidate.udid == device.udid && candidate.state == "Booted");
                if !raced_boot {
                    return Err(boot.expect_err("the failed boot result was checked"));
                }
            }
        }
        let ready = process::output_with_timeout(
            Path::new("xcrun"),
            &process::strings(&["simctl", "bootstatus", &device.udid, "-b"]),
            "iOS Simulator boot status",
            Duration::from_secs(180),
        )
        .await;
        if let Err(error) = ready {
            if owned {
                let _ = process::output_with_timeout(
                    Path::new("xcrun"),
                    &shutdown::command(&device.udid),
                    "iOS Simulator boot rollback",
                    Duration::from_secs(45),
                )
                .await;
            }
            return Err(error);
        }
        Ok(IosAttached {
            udid: device.udid,
            name: device.name,
            owned,
        })
    }

    pub async fn start_helper(&self, udid: &str) -> EmulatorResult<IosHelper> {
        let listener = TcpListener::bind((Ipv6Addr::LOCALHOST, 0))
            .await
            .map_err(|error| {
                helper_runtime::helper_failure(format!("Could not reserve a port: {error}"))
            })?;
        let port = listener
            .local_addr()
            .map_err(|error| {
                helper_runtime::helper_failure(format!(
                    "Could not inspect the reserved port: {error}"
                ))
            })?
            .port();
        drop(listener);
        let executable = helper_runtime::serve_sim_path()?;
        let mut command = windowless_async_command(executable);
        command
            .args([udid, "--port", &port.to_string()])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        let mut child = command.spawn().map_err(|error| {
            helper_runtime::helper_failure(format!("Could not start the serve-sim helper: {error}"))
        })?;
        let (width, height) = match helper_runtime::wait_until_ready(&mut child, port).await {
            Ok(dimensions) => dimensions,
            Err(error) => {
                let _ = child.kill().await;
                return Err(error);
            }
        };
        let stream_url = format!("http://[::1]:{port}/stream.mjpeg");
        let ax_url = format!("http://[::1]:{port}/ax");
        let ws_url = format!("ws://[::1]:{port}/ws");
        let (control_tx, control_rx) = mpsc::channel(128);
        let control_task = tokio::spawn(helper_runtime::control_worker(ws_url, control_rx));
        Ok(IosHelper {
            stream_url,
            ax_url,
            control_tx,
            stream_healthy: Arc::new(AtomicBool::new(true)),
            width: Arc::new(AtomicU32::new(width)),
            height: Arc::new(AtomicU32::new(height)),
            child,
            control_task,
        })
    }

    pub async fn shutdown(&self, attached: &IosAttached) -> EmulatorResult<()> {
        if !attached.owned {
            return Ok(());
        }
        let result = process::output(
            Path::new("xcrun"),
            &shutdown::command(&attached.udid),
            "iOS Simulator shutdown",
        )
        .await;
        if result.is_ok() {
            return Ok(());
        }
        if simctl_devices()
            .await
            .ok()
            .is_some_and(|devices| shutdown::failure_is_complete(&devices, &attached.udid))
        {
            return Ok(());
        }
        result.map(drop)
    }

    pub async fn screenshot(&self, udid: &str, path: &Path) -> EmulatorResult<()> {
        process::output(
            Path::new("xcrun"),
            &[
                "simctl".into(),
                "io".into(),
                udid.into(),
                "screenshot".into(),
                path.to_string_lossy().into_owned(),
            ],
            "iOS Simulator screenshot",
        )
        .await
        .map(drop)
    }

    pub async fn accessibility_tree(&self, helper: &IosHelper) -> EmulatorResult<Value> {
        accessibility::request_tree(&helper.ax_url).await
    }

    pub async fn install(&self, udid: &str, app_path: &str) -> EmulatorResult<()> {
        super::android::validate_app_path(app_path)?;
        if !Path::new(app_path).is_dir() {
            return Err(EmulatorFailure::invalid(
                "iOS Simulator installation requires an unarchived .app bundle.",
            ));
        }
        process::output(
            Path::new("xcrun"),
            &process::strings(&["simctl", "install", udid, app_path]),
            "iOS app installation",
        )
        .await
        .map(drop)
    }

    pub async fn launch(&self, udid: &str, bundle_id: &str) -> EmulatorResult<Value> {
        let output = process::output(
            Path::new("xcrun"),
            &process::strings(&["simctl", "launch", udid, bundle_id]),
            "iOS app launch",
        )
        .await?;
        Ok(serde_json::json!({
            "stdout": String::from_utf8_lossy(&output.stdout).trim(),
        }))
    }
}

pub async fn tap(helper: &IosHelper, x: f64, y: f64) -> EmulatorResult<()> {
    helper.send(control::pointer("begin", x, y)?).await?;
    tokio::time::sleep(Duration::from_millis(40)).await;
    helper.send(control::pointer("end", x, y)?).await
}

pub async fn pointer(helper: &IosHelper, kind: &str, x: f64, y: f64) -> EmulatorResult<()> {
    helper.send(control::pointer(kind, x, y)?).await
}

pub async fn gesture(
    helper: &IosHelper,
    points: &[GesturePoint],
    duration_ms: u64,
) -> EmulatorResult<()> {
    if points.is_empty() {
        return Err(EmulatorFailure::invalid("Gesture points cannot be empty."));
    }
    let delay = Duration::from_millis(
        duration_ms
            .checked_div(points.len().saturating_sub(1).max(1) as u64)
            .unwrap_or(0),
    );
    for (index, point) in points.iter().enumerate() {
        let fallback = if index == 0 {
            "begin"
        } else if index + 1 == points.len() {
            "end"
        } else {
            "move"
        };
        helper.send(control::touch(point, fallback)?).await?;
        if index + 1 < points.len() {
            tokio::time::sleep(delay).await;
        }
    }
    Ok(())
}

pub async fn type_text(helper: &IosHelper, text: &str) -> EmulatorResult<()> {
    for frame in control::text(text)? {
        helper.send(frame).await?;
        tokio::time::sleep(Duration::from_millis(4)).await;
    }
    Ok(())
}

pub async fn button(helper: &IosHelper, name: &str) -> EmulatorResult<()> {
    helper.send(control::button(name)?).await
}

pub async fn key(helper: &IosHelper, name: &str) -> EmulatorResult<()> {
    helper.send(control::key(name, true)?).await?;
    helper.send(control::key(name, false)?).await
}

pub async fn rotate(helper: &IosHelper, orientation: &str) -> EmulatorResult<()> {
    let previous = helper.dimensions();
    helper.send(control::rotate(orientation)?).await?;
    for _ in 0..20 {
        tokio::time::sleep(Duration::from_millis(100)).await;
        let dimensions = helper.refresh_dimensions().await?;
        if dimensions != previous {
            break;
        }
    }
    Ok(())
}

#[derive(serde::Deserialize)]
struct SimctlList {
    #[serde(default)]
    devices: std::collections::HashMap<String, Vec<SimctlDevice>>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct SimctlDevice {
    name: String,
    udid: String,
    state: String,
    #[serde(default = "default_available")]
    is_available: bool,
}

struct ListedDevice {
    name: String,
    udid: String,
    state: String,
    runtime: String,
    available: bool,
}

async fn simctl_devices() -> EmulatorResult<Vec<ListedDevice>> {
    let output = process::output(
        Path::new("xcrun"),
        &process::strings(&["simctl", "list", "devices", "-j"]),
        "iOS Simulator discovery",
    )
    .await?;
    let parsed: SimctlList = serde_json::from_slice(&output.stdout).map_err(|error| {
        EmulatorFailure::new(
            "provider_incompatible",
            format!("xcrun simctl returned invalid JSON: {error}"),
            ["Update Xcode command line tools and retry."],
        )
    })?;
    Ok(parsed
        .devices
        .into_iter()
        .flat_map(|(runtime, devices)| {
            devices.into_iter().map(move |device| ListedDevice {
                name: device.name,
                udid: device.udid,
                state: device.state,
                runtime: runtime.clone(),
                available: device.is_available,
            })
        })
        .collect())
}

const fn default_available() -> bool {
    true
}
