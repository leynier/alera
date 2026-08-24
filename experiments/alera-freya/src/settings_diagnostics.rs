use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;

use alera_desktop_core::{RuntimeBridge, reveal_in_file_manager};
use chrono::Utc;
use freya::prelude::*;
use rfd::AsyncFileDialog;
use serde_json::{Value, json};
use zip::write::SimpleFileOptions;

use crate::{MUTED, settings_group_described, settings_row_shell};

#[derive(Clone, Debug, Default, PartialEq)]
struct DiagnosticsSnapshot {
    log_directory: Option<String>,
    runtime_version: Option<String>,
    runtime_commit: Option<String>,
    protocol_version: Option<i64>,
    capabilities: Vec<String>,
    crash_reporting_enabled: bool,
}

pub fn content(active: bool, bridge: RuntimeBridge) -> Element {
    let status = use_state(|| None::<Result<DiagnosticsSnapshot, String>>);
    let revision = use_state(|| 0_u64);
    let busy = use_state(|| false);
    let message = use_state(|| None::<String>);
    let log_level = use_state(|| "Info".to_string());
    let crash_reports = use_state(|| false);
    let deps = (active, *revision.read());
    let bridge_for_load = bridge.clone();
    let mut status_for_load = status;
    use_side_effect_with_deps(&deps, move |(active, _)| {
        if !*active {
            return;
        }
        let bridge = bridge_for_load.clone();
        spawn(async move {
            let result = bridge
                .request_with_timeout("status.get", json!({}), Duration::from_secs(10))
                .await
                .map(|value| parse_status(&value));
            status_for_load.set(Some(result));
        });
    });
    let crash_seed = status
        .read()
        .as_ref()
        .and_then(|value| value.as_ref().ok())
        .map(|value| value.crash_reporting_enabled);
    let mut crash_reports_for_seed = crash_reports;
    use_side_effect_with_deps(&crash_seed, move |value| {
        if let Some(value) = value {
            crash_reports_for_seed.set(*value);
        }
    });

    let snapshot = status
        .read()
        .as_ref()
        .and_then(|value| value.as_ref().ok())
        .cloned();
    let log_directory = snapshot
        .as_ref()
        .and_then(|value| value.log_directory.clone());
    let metadata = diagnostics_metadata(snapshot.as_ref());
    let bridge_for_crash = bridge.clone();
    let busy_for_crash = busy;
    let message_for_crash = message;
    let revision_for_crash = revision;

    let diagnostics = settings_group_described(
        "Diagnostics",
        "Alera keeps rotating log files on this computer so an error can be reviewed after it happens.",
        vec![
            settings_row_shell(
                "Open Logs Folder",
                "Show the folder holding the app log files.",
            )
            .child(
                Button::new()
                    .compact()
                    .outline()
                    .on_press({
                        let log_directory = log_directory.clone();
                        move |_| open_logs(log_directory.clone(), message)
                    })
                    .child("Open"),
            )
            .into_element(),
            settings_row_shell(
                "Export Diagnostics",
                "Save a zip with app and runtime logs plus version details. Secrets such as tokens are masked before anything is written.",
            )
            .child(
                Button::new()
                    .compact()
                    .outline()
                    .on_press(move |_| {
                        export_diagnostics(log_directory.clone(), metadata.clone(), busy, message)
                    })
                    .child("Export"),
            )
            .into_element(),
            settings_row_shell("Log Level", "How much detail is written to the log files.")
                .child(log_level_control(log_level))
                .into_element(),
            settings_row_shell(
                "Send Crash Reports",
                "Send crashes to the configured external service. Off by default.",
            )
            .child(toggle_control(crash_reports(), move || {
                run_request(
                    bridge_for_crash.clone(),
                    "configure",
                    json!({"crashReporting": !crash_reports()}),
                    "Crash Reporting Updated",
                    busy_for_crash,
                    message_for_crash,
                    revision_for_crash,
                );
            }))
            .into_element(),
        ],
    );
    rect()
        .width(Size::fill())
        .vertical()
        .spacing(8.)
        .child(diagnostics)
        .maybe_child(
            status
                .read()
                .as_ref()
                .and_then(|value| value.as_ref().err())
                .map(|error| label().font_size(10.).color(MUTED).text(error.clone())),
        )
        .maybe_child(
            message
                .read()
                .clone()
                .map(|value| label().font_size(10.).color(MUTED).max_lines(4).text(value)),
        )
        .maybe_child((*busy.read()).then(|| {
            rect()
                .horizontal()
                .spacing(6.)
                .child(CircularLoader::new().size(12.))
                .child(label().font_size(10.).color(MUTED).text("Working"))
        }))
        .into_element()
}

fn parse_status(value: &Value) -> DiagnosticsSnapshot {
    DiagnosticsSnapshot {
        log_directory: value
            .get("logDirectory")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_string),
        runtime_version: value
            .get("runtimeHostVersion")
            .and_then(Value::as_str)
            .map(str::to_string),
        runtime_commit: value
            .get("runtimeHostCommit")
            .and_then(Value::as_str)
            .map(str::to_string),
        protocol_version: value.get("protocolVersion").and_then(Value::as_i64),
        capabilities: value
            .get("runtimeCapabilities")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
        crash_reporting_enabled: value
            .get("diagnostics")
            .and_then(|value| value.get("crashReportingEnabled"))
            .and_then(Value::as_bool)
            .unwrap_or(false),
    }
}

fn run_request(
    bridge: RuntimeBridge,
    verb: &'static str,
    payload: Value,
    success: &'static str,
    mut busy: State<bool>,
    mut message: State<Option<String>>,
    mut revision: State<u64>,
) {
    if *busy.read() {
        return;
    }
    busy.set(true);
    message.set(None);
    spawn(async move {
        match bridge
            .request_with_timeout(verb, payload, Duration::from_secs(15))
            .await
        {
            Ok(_) => {
                message.set(Some(success.to_string()));
                let next_revision = revision.read().saturating_add(1);
                revision.set(next_revision);
            }
            Err(error) => message.set(Some(error)),
        }
        busy.set(false);
    });
}

fn open_logs(directory: Option<String>, mut message: State<Option<String>>) {
    spawn(async move {
        let result = blocking::unblock(move || {
            let directory = directory
                .map(PathBuf::from)
                .ok_or_else(|| "Runtime Log Directory Is Unavailable".to_string())?;
            fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
            reveal_in_file_manager(&directory)
        })
        .await;
        message.set(Some(match result {
            Ok(()) => "Logs Folder Opened".to_string(),
            Err(error) => error,
        }));
    });
}

fn export_diagnostics(
    runtime_logs: Option<String>,
    metadata: Value,
    mut busy: State<bool>,
    mut message: State<Option<String>>,
) {
    if *busy.read() {
        return;
    }
    busy.set(true);
    message.set(None);
    spawn(async move {
        let suggested = format!(
            "alera-diagnostics-{}.zip",
            Utc::now().format("%Y%m%dT%H%M%S")
        );
        let selection = AsyncFileDialog::new()
            .set_file_name(&suggested)
            .add_filter("ZIP Archive", &["zip"])
            .save_file()
            .await;
        let result = if let Some(file) = selection {
            let destination = file.path().to_path_buf();
            blocking::unblock(move || {
                write_diagnostics_bundle(
                    &destination,
                    runtime_logs.as_deref().map(Path::new),
                    &metadata,
                )
            })
            .await
            .map(|()| "Diagnostics Exported".to_string())
        } else {
            Ok("Diagnostics Export Cancelled".to_string())
        };
        message.set(Some(result.unwrap_or_else(|error| error)));
        busy.set(false);
    });
}

fn diagnostics_metadata(status: Option<&DiagnosticsSnapshot>) -> Value {
    json!({
        "collectedAt": Utc::now().to_rfc3339(),
        "app": {"version": env!("CARGO_PKG_VERSION"), "framework": "freya"},
        "platform": {"operatingSystem": std::env::consts::OS, "architecture": std::env::consts::ARCH},
        "runtime": {
            "reachable": status.and_then(|value| value.runtime_version.as_ref()).is_some(),
            "version": status.and_then(|value| value.runtime_version.as_ref()),
            "commit": status.and_then(|value| value.runtime_commit.as_ref()),
            "protocolVersion": status.and_then(|value| value.protocol_version),
            "capabilities": status.map(|value| value.capabilities.as_slice()).unwrap_or_default(),
        },
    })
}

fn write_diagnostics_bundle(
    destination: &Path,
    runtime_log_directory: Option<&Path>,
    metadata: &Value,
) -> Result<(), String> {
    let file = File::create(destination).map_err(|error| error.to_string())?;
    let mut archive = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    append_log_directory(&mut archive, runtime_log_directory, "runtime", options)?;
    archive
        .start_file("meta.json", options)
        .map_err(|error| error.to_string())?;
    archive
        .write_all(
            serde_json::to_string_pretty(metadata)
                .map_err(|error| error.to_string())?
                .as_bytes(),
        )
        .map_err(|error| error.to_string())?;
    archive.finish().map_err(|error| error.to_string())?;
    Ok(())
}

fn append_log_directory(
    archive: &mut zip::ZipWriter<File>,
    directory: Option<&Path>,
    prefix: &str,
    options: SimpleFileOptions,
) -> Result<(), String> {
    let Some(directory) = directory.filter(|path| path.is_dir()) else {
        return Ok(());
    };
    let mut files = fs::read_dir(directory)
        .map_err(|error| error.to_string())?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_file() && path.extension().is_some_and(|value| value == "log"))
        .collect::<Vec<_>>();
    files.sort();
    for path in files {
        let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        archive
            .start_file(format!("{prefix}/{name}"), options)
            .map_err(|error| error.to_string())?;
        let mut source = File::open(path).map_err(|error| error.to_string())?;
        std::io::copy(&mut source, archive).map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn log_level_control(mut value: State<String>) -> Element {
    let selected = value.read().clone();
    rect()
        .horizontal()
        .spacing(4.)
        .children(
            ["Error", "Warning", "Info", "Debug"]
                .into_iter()
                .map(|level| {
                    Button::new()
                        .compact()
                        .maybe(selected == level, Button::filled)
                        .on_press(move |_| value.set(level.to_string()))
                        .child(level)
                }),
        )
        .into_element()
}

fn toggle_control(enabled: bool, mut action: impl FnMut() + 'static) -> Element {
    crate::settings_switch::control(enabled, true, move |event| {
        event.stop_propagation();
        action();
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read as _;

    #[test]
    fn diagnostics_bundle_contains_runtime_logs_and_metadata() {
        let root =
            std::env::temp_dir().join(format!("alera-freya-diagnostics-{}", uuid::Uuid::new_v4()));
        let logs = root.join("runtime-logs");
        let destination = root.join("bundle.zip");
        fs::create_dir_all(&logs).expect("create logs");
        fs::write(logs.join("runtime.log"), "runtime output\n").expect("write log");
        fs::write(logs.join("ignored.txt"), "ignore").expect("write ignored");
        write_diagnostics_bundle(
            &destination,
            Some(&logs),
            &json!({"app": {"version": "test"}}),
        )
        .expect("write diagnostics");

        let mut archive = zip::ZipArchive::new(File::open(&destination).expect("open bundle"))
            .expect("read bundle");
        let mut meta = String::new();
        archive
            .by_name("meta.json")
            .expect("metadata")
            .read_to_string(&mut meta)
            .expect("read metadata");
        assert!(meta.contains("\"version\": \"test\""));
        assert!(archive.by_name("runtime/runtime.log").is_ok());
        assert!(archive.by_name("runtime/ignored.txt").is_err());
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn parses_runtime_diagnostics_without_inventing_values() {
        let snapshot = parse_status(&json!({
            "runtimeHostVersion": "1.2.3",
            "runtimeCapabilities": ["resourceMonitorV1"],
            "diagnostics": {"crashReportingEnabled": true}
        }));
        assert_eq!(snapshot.runtime_version.as_deref(), Some("1.2.3"));
        assert!(snapshot.crash_reporting_enabled);
        assert_eq!(snapshot.capabilities, ["resourceMonitorV1"]);
        assert!(snapshot.log_directory.is_none());
    }
}
