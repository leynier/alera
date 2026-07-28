mod accessibility;
mod accessibility_command;
mod command_arguments;
mod control;
mod sdk_discovery;
mod shutdown;
mod stream;

use std::collections::HashMap;
use std::net::{Ipv4Addr, TcpListener};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use serde_json::Value;
use tokio::process::Child;

use super::contract::{EmulatorDevice, EmulatorFailure, EmulatorResult, GesturePoint};
use super::process;
use super::EmulatorPlatform;

pub use command_arguments::AndroidLogcatQuery;
pub use stream::AndroidStream;

pub struct AndroidAttached {
    pub device_name: String,
    pub serial: String,
    pub owned: bool,
    pub process: Option<Child>,
}

#[derive(Clone)]
pub struct AndroidSdk {
    pub adb: PathBuf,
    emulator: PathBuf,
}

impl AndroidSdk {
    pub fn discover() -> Self {
        let paths = sdk_discovery::discover();
        Self {
            adb: paths.adb,
            emulator: paths.emulator,
        }
    }

    pub async fn list_devices(&self) -> EmulatorResult<Vec<EmulatorDevice>> {
        let avds = process::output(
            &self.emulator,
            &process::strings(&["-list-avds"]),
            "Android virtual device discovery",
        )
        .await?;
        let running = self.running_devices().await?;
        Ok(String::from_utf8_lossy(&avds.stdout)
            .lines()
            .map(str::trim)
            .filter(|name| !name.is_empty())
            .map(|name| EmulatorDevice {
                id: format!("android:{name}"),
                platform: EmulatorPlatform::Android,
                name: name.to_string(),
                state: if running.values().any(|avd| avd == name) {
                    "booted".into()
                } else {
                    "shutdown".into()
                },
                available: true,
                runtime: None,
            })
            .collect())
    }

    pub fn validate_stream_dependency(&self) -> EmulatorResult<()> {
        stream::bundled_server_path().map(drop)
    }

    pub async fn attach(&self, device_id: &str) -> EmulatorResult<AndroidAttached> {
        let name = device_id.strip_prefix("android:").unwrap_or(device_id);
        let devices = self.list_devices().await?;
        if !devices.iter().any(|device| device.name == name) {
            return Err(EmulatorFailure::new(
                "device_not_found",
                format!("Android virtual device `{name}` was not found."),
                ["Create the AVD in Android Studio, then refresh the device list."],
            ));
        }
        let running = self.running_devices().await?;
        if let Some((serial, _)) = running.iter().find(|(_, avd)| avd.as_str() == name) {
            self.wait_for_boot(serial).await?;
            return Ok(AndroidAttached {
                device_name: name.to_string(),
                serial: serial.clone(),
                owned: false,
                process: None,
            });
        }
        let port = reserve_emulator_port(&running)?;
        let serial = format!("emulator-{port}");
        let mut command = windowless_async_command(&self.emulator);
        command
            .args(command_arguments::boot(name, port))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        let mut process = command.spawn().map_err(|error| {
            EmulatorFailure::new(
                "device_unavailable",
                format!("Could not start Android virtual device `{name}`: {error}"),
                ["Open Android Studio Device Manager and verify the AVD."],
            )
        })?;
        let deadline = tokio::time::Instant::now() + Duration::from_secs(180);
        while tokio::time::Instant::now() < deadline {
            if let Some(status) = process.try_wait().map_err(|error| {
                EmulatorFailure::new(
                    "device_unavailable",
                    format!("Could not monitor Android virtual device `{name}`: {error}"),
                    ["Open Android Studio Device Manager and retry the AVD."],
                )
            })? {
                return Err(EmulatorFailure::new(
                    "device_unavailable",
                    format!(
                        "Android virtual device `{name}` exited during boot with status {status}."
                    ),
                    ["Open Android Studio Device Manager and inspect the AVD boot error."],
                ));
            }
            let is_ours = self
                .running_devices()
                .await
                .unwrap_or_default()
                .get(&serial)
                .is_some_and(|avd| avd == name);
            if is_ours {
                if let Err(error) = self.wait_for_boot(&serial).await {
                    let _ = process.kill().await;
                    let _ = process::output(
                        &self.adb,
                        &["-s".into(), serial.clone(), "emu".into(), "kill".into()],
                        "Android emulator boot rollback",
                    )
                    .await;
                    return Err(error);
                }
                if process.try_wait().ok().flatten().is_some() {
                    return Err(EmulatorFailure::new(
                        "device_unavailable",
                        format!("Android virtual device `{name}` exited after boot."),
                        ["Open Android Studio Device Manager and retry the AVD."],
                    ));
                }
                return Ok(AndroidAttached {
                    device_name: name.to_string(),
                    serial,
                    owned: true,
                    process: Some(process),
                });
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
        let _ = process.kill().await;
        Err(EmulatorFailure::new(
            "boot_timeout",
            format!("Android virtual device `{name}` did not boot within 180 seconds."),
            ["Open the AVD in Android Studio, inspect its boot error, and retry."],
        ))
    }

    pub async fn start_stream(&self, serial: &str) -> EmulatorResult<AndroidStream> {
        AndroidStream::start(&self.adb, serial, &stream::bundled_server_path()?).await
    }

    pub async fn shutdown(&self, attached: &mut AndroidAttached) -> EmulatorResult<()> {
        shutdown::owned_device(&self.adb, attached).await
    }

    pub async fn screenshot(&self, serial: &str) -> EmulatorResult<Vec<u8>> {
        let result = process::output(
            &self.adb,
            &[
                "-s".into(),
                serial.into(),
                "exec-out".into(),
                "screencap".into(),
                "-p".into(),
            ],
            "Android screenshot",
        )
        .await?;
        Ok(result.stdout)
    }

    pub async fn accessibility_tree(&self, serial: &str) -> EmulatorResult<String> {
        let xml = accessibility_command::dump(&self.adb, serial).await?;
        accessibility::normalize_uiautomator_tree(&xml)
    }

    pub async fn rotate(&self, serial: &str, orientation: &str) -> EmulatorResult<()> {
        let rotation = match orientation {
            "portrait" => "0",
            "landscapeLeft" | "landscape_left" => "1",
            "portraitUpsideDown" | "portrait_upside_down" => "2",
            "landscapeRight" | "landscape_right" => "3",
            _ => return Err(EmulatorFailure::invalid("Unknown Android orientation.")),
        };
        for args in [
            vec![
                "shell",
                "settings",
                "put",
                "system",
                "accelerometer_rotation",
                "0",
            ],
            vec![
                "shell",
                "settings",
                "put",
                "system",
                "user_rotation",
                rotation,
            ],
        ] {
            let mut scoped = vec!["-s".to_string(), serial.to_string()];
            scoped.extend(args.into_iter().map(str::to_string));
            process::output(&self.adb, &scoped, "Android rotation").await?;
        }
        Ok(())
    }

    async fn running_devices(&self) -> EmulatorResult<HashMap<String, String>> {
        let output = process::output(
            &self.adb,
            &process::strings(&["devices"]),
            "Android device discovery",
        )
        .await?;
        let mut devices = HashMap::new();
        for line in String::from_utf8_lossy(&output.stdout).lines().skip(1) {
            let Some((serial, state)) = line.split_once('\t') else {
                continue;
            };
            if !serial.starts_with("emulator-") || state.trim() != "device" {
                continue;
            }
            let name = process::output(
                &self.adb,
                &[
                    "-s".into(),
                    serial.into(),
                    "emu".into(),
                    "avd".into(),
                    "name".into(),
                ],
                "Android AVD identity",
            )
            .await?;
            if let Some(name) = String::from_utf8_lossy(&name.stdout)
                .lines()
                .map(str::trim)
                .find(|line| !line.is_empty() && *line != "OK")
            {
                devices.insert(serial.to_string(), name.to_string());
            }
        }
        Ok(devices)
    }

    async fn wait_for_boot(&self, serial: &str) -> EmulatorResult<()> {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(180);
        while tokio::time::Instant::now() < deadline {
            let value = process::output_with_timeout(
                &self.adb,
                &[
                    "-s".into(),
                    serial.into(),
                    "shell".into(),
                    "getprop".into(),
                    "sys.boot_completed".into(),
                ],
                "Android boot status",
                Duration::from_secs(5),
            )
            .await;
            if value
                .ok()
                .is_some_and(|output| String::from_utf8_lossy(&output.stdout).trim() == "1")
            {
                return Ok(());
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
        Err(EmulatorFailure::new(
            "boot_timeout",
            "Android did not finish booting within 180 seconds.",
            ["Inspect the AVD in Android Studio and retry."],
        ))
    }
}

fn reserve_emulator_port(running: &HashMap<String, String>) -> EmulatorResult<u16> {
    for port in (5554_u16..=5682).step_by(2) {
        let serial = format!("emulator-{port}");
        if running.contains_key(&serial) {
            continue;
        }
        let Ok(console) = TcpListener::bind((Ipv4Addr::LOCALHOST, port)) else {
            continue;
        };
        let Ok(adb) = TcpListener::bind((Ipv4Addr::LOCALHOST, port + 1)) else {
            continue;
        };
        drop((console, adb));
        return Ok(port);
    }
    Err(EmulatorFailure::new(
        "device_unavailable",
        "No Android emulator console port is available.",
        ["Close an unused Android emulator and retry."],
    ))
}

pub async fn tap(stream: &AndroidStream, x: f64, y: f64) -> EmulatorResult<()> {
    let (width, height) = stream.dimensions();
    stream
        .write_control(&control::touch("begin", x, y, width, height)?)
        .await?;
    tokio::time::sleep(Duration::from_millis(40)).await;
    let (width, height) = stream.dimensions();
    stream
        .write_control(&control::touch("end", x, y, width, height)?)
        .await
}

pub async fn pointer(stream: &AndroidStream, kind: &str, x: f64, y: f64) -> EmulatorResult<()> {
    let (width, height) = stream.dimensions();
    stream
        .write_control(&control::touch(kind, x, y, width, height)?)
        .await
}

pub async fn gesture(
    stream: &AndroidStream,
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
        let kind = point.kind.as_deref().unwrap_or(if index == 0 {
            "begin"
        } else if index + 1 == points.len() {
            "end"
        } else {
            "move"
        });
        pointer(stream, kind, point.x, point.y).await?;
        if index + 1 < points.len() {
            tokio::time::sleep(delay).await;
        }
    }
    Ok(())
}

pub async fn type_text(stream: &AndroidStream, text: &str) -> EmulatorResult<()> {
    stream.write_control(&control::text(text)?).await
}

pub async fn button(stream: &AndroidStream, name: &str) -> EmulatorResult<()> {
    stream.write_control(&control::key(name, true)?).await?;
    stream.write_control(&control::key(name, false)?).await
}

pub async fn key(stream: &AndroidStream, name: &str) -> EmulatorResult<()> {
    button(stream, name).await
}

pub async fn install(
    sdk: &AndroidSdk,
    serial: &str,
    app_path: &str,
    reinstall: bool,
) -> EmulatorResult<()> {
    if !Path::new(app_path).is_file() {
        return Err(EmulatorFailure::invalid(
            "Android installation requires an APK file.",
        ));
    }
    let mut args = vec!["-s".into(), serial.into(), "install".into()];
    if reinstall {
        args.push("-r".into());
    }
    args.push(app_path.into());
    process::output(&sdk.adb, &args, "Android app installation")
        .await
        .map(drop)
}

pub async fn launch(
    sdk: &AndroidSdk,
    serial: &str,
    bundle_id: &str,
    activity: Option<&str>,
) -> EmulatorResult<Value> {
    let args = command_arguments::launch(serial, bundle_id, activity)?;
    let output = process::output(&sdk.adb, &args, "Android app launch").await?;
    Ok(serde_json::json!({
        "stdout": String::from_utf8_lossy(&output.stdout).trim(),
    }))
}

pub async fn permission(
    sdk: &AndroidSdk,
    serial: &str,
    operation: &str,
    bundle_id: &str,
    permission: &str,
) -> EmulatorResult<()> {
    let args = command_arguments::permission(serial, operation, bundle_id, permission)?;
    process::output(&sdk.adb, &args, "Android permission update")
        .await
        .map(drop)
}

pub async fn logcat(
    sdk: &AndroidSdk,
    serial: &str,
    query: &AndroidLogcatQuery<'_>,
) -> EmulatorResult<String> {
    let args = command_arguments::logcat(serial, query)?;
    let output = process::output(&sdk.adb, &args, "Android logcat").await?;
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub async fn stop_stream(sdk: &AndroidSdk, serial: &str, stream: AndroidStream) {
    stream.stop(&sdk.adb, serial).await;
}

pub fn validate_app_path(path: &str) -> EmulatorResult<()> {
    if Path::new(path).exists() {
        Ok(())
    } else {
        Err(EmulatorFailure::invalid(format!(
            "App artifact does not exist: {path}"
        )))
    }
}
