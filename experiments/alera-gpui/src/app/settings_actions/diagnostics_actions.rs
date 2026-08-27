use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::thread;

use chrono::Utc;
use zip::write::SimpleFileOptions;

impl AleraApp {
    pub(super) fn browse_workspace_directory(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let selection = cx.prompt_for_paths(gpui::PathPromptOptions {
            files: false,
            directories: true,
            multiple: false,
            prompt: Some("Select Workspace Directory".into()),
        });
        let this = cx.entity().downgrade();
        window
            .spawn(cx, async move |cx| {
                let path = match selection.await {
                    Ok(Ok(Some(paths))) => paths.into_iter().next(),
                    Ok(Ok(None)) => None,
                    Ok(Err(error)) => {
                        let _ = this.update(cx, |this, cx| {
                            this.settings_state.error = Some(error.to_string());
                            cx.notify();
                        });
                        None
                    }
                    Err(error) => {
                        let _ = this.update(cx, |this, cx| {
                            this.settings_state.error = Some(error.to_string());
                            cx.notify();
                        });
                        None
                    }
                };
                let Some(path) = path else {
                    return;
                };
                let value = path.to_string_lossy().into_owned();
                let _ = this.update_in(cx, move |this, window, cx| {
                    this.set_workspace_directory(value.clone(), cx);
                    if let Some(input) = this.settings_inputs.get("workspace-directory") {
                        input.update(cx, |input, cx| {
                            input.set_value(value, window, cx);
                        });
                    }
                    cx.notify();
                });
            })
            .detach();
    }

    pub(super) fn open_logs_folder(&mut self, cx: &mut Context<Self>) {
        let directory = crate::app_log::directory()
            .map(Path::to_path_buf)
            .unwrap_or_else(crate::app_log_directory);
        if fs::create_dir_all(&directory).is_err() {
            self.local_message = Some("Could not open the logs folder.".into());
            cx.notify();
            return;
        }
        cx.open_with_system(&directory);
        cx.notify();
    }

    pub(super) fn export_diagnostics(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        crate::app_log::flush();
        let suggested = format!("alera-diagnostics-{}.zip", Utc::now().format("%Y%m%dT%H%M%S"));
        // Flutter's save picker starts in the active workspace when one is
        // mounted. Keep that context for the native GPUI picker and only fall
        // back to the platform download/documents directory without a local
        // workspace.
        let directory = self
            .selected_workspace_path()
            .map(PathBuf::from)
            .filter(|path| path.is_dir())
            .or_else(dirs::download_dir)
            .or_else(dirs::document_dir)
            .unwrap_or_else(|| PathBuf::from("."));
        let selection = cx.prompt_for_new_path(&directory, Some(&suggested));
        let app_logs = crate::app_log::directory()
            .map(Path::to_path_buf)
            .unwrap_or_else(crate::app_log_directory);
        let runtime_logs = self
            .settings_state
            .runtime_log_directory
            .as_deref()
            .map(PathBuf::from);
        let metadata = diagnostics_metadata(&self.settings_state);
        self.diagnostics_export_busy = true;
        self.settings_state.error = None;
        self.settings_state.toast = None;
        self.local_message = None;
        let this = cx.entity().downgrade();
        window
            .spawn(cx, async move |cx| {
                let destination = match selection.await {
                    Ok(Ok(Some(path))) => path,
                    Ok(Ok(None)) => {
                        let _ = this.update(cx, |this, cx| {
                            this.diagnostics_export_busy = false;
                            cx.notify();
                        });
                        return;
                    }
                    Ok(Err(error)) => {
                        let _ = this.update(cx, |this, cx| {
                            this.diagnostics_export_busy = false;
                            this.local_message = Some(error.to_string().into());
                            cx.notify();
                        });
                        return;
                    }
                    Err(error) => {
                        let _ = this.update(cx, |this, cx| {
                            this.diagnostics_export_busy = false;
                            this.local_message = Some(error.to_string().into());
                            cx.notify();
                        });
                        return;
                    }
                };
                let (sender, receiver) = async_channel::bounded(1);
                thread::Builder::new()
                    .name("alera-gpui-diagnostics".to_string())
                    .spawn(move || {
                        let _ = sender.send_blocking(write_diagnostics_bundle(
                            &destination,
                            Some(&app_logs),
                            runtime_logs.as_deref(),
                            &metadata,
                        ));
                    })
                    .expect("failed to start diagnostics exporter");
                let result = receiver.recv().await.unwrap_or_else(|error| Err(error.to_string()));
                let _ = this.update(cx, |this, cx| {
                    this.diagnostics_export_busy = false;
                    match result {
                        Ok(()) => this.local_message = Some("Diagnostics exported.".into()),
                        Err(error) => this.local_message = Some(error.into()),
                    }
                    cx.notify();
                });
            })
            .detach();
        cx.notify();
    }
}

fn diagnostics_metadata(settings: &SettingsState) -> Value {
    let flavor = std::env::var("ALERA_FLAVOR")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| {
            if std::env::var("ALERA_APP_ID").is_ok_and(|value| value.ends_with(".dev")) {
                "dev".to_string()
            } else {
                "release".to_string()
            }
        });
    json!({
        "collectedAt": Utc::now().to_rfc3339(),
        "app": {
            "version": env!("CARGO_PKG_VERSION"),
            "flavor": flavor,
        },
        "platform": {
            "operatingSystem": std::env::consts::OS,
            "operatingSystemVersion":
                sysinfo::System::long_os_version().unwrap_or_else(|| "unknown".to_string()),
        },
        "runtime": {
            "reachable": settings.runtime_host_version.is_some(),
            "version": settings.runtime_host_version,
            "commit": settings.runtime_host_commit,
            "protocolVersion": settings.runtime_protocol_version,
            "capabilities": settings.runtime_capabilities,
        },
    })
}

fn write_diagnostics_bundle(
    destination: &Path,
    app_log_directory: Option<&Path>,
    runtime_log_directory: Option<&Path>,
    metadata: &Value,
) -> Result<(), String> {
    let file = File::create(destination).map_err(|error| error.to_string())?;
    let mut archive = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    append_log_directory(&mut archive, app_log_directory, "app", options)?;
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

#[cfg(test)]
mod diagnostics_tests {
    use super::write_diagnostics_bundle;
    use std::io::Read as _;

    #[test]
    fn diagnostics_bundle_contains_version_and_runtime_logs() {
        let root = std::env::temp_dir().join(format!(
            "alera-gpui-diagnostics-test-{}",
            std::process::id()
        ));
        let app_logs = root.join("app-logs");
        let runtime_logs = root.join("runtime-logs");
        let destination = root.join("bundle.zip");
        std::fs::create_dir_all(&app_logs).expect("create app logs");
        std::fs::create_dir_all(&runtime_logs).expect("create runtime logs");
        std::fs::write(app_logs.join("alera.log"), "{\"source\":\"app\"}\n")
            .expect("write app log");
        std::fs::write(runtime_logs.join("runtime.log"), "{\"source\":\"runtime\"}\n")
            .expect("write runtime log");
        std::fs::write(runtime_logs.join("ignored.txt"), "not a log")
            .expect("write ignored file");
        let metadata = serde_json::json!({
            "app": {"version": "test"},
            "runtime": {"reachable": true},
        });

        write_diagnostics_bundle(
            &destination,
            Some(&app_logs),
            Some(&runtime_logs),
            &metadata,
        )
        .expect("write diagnostics bundle");

        let file = std::fs::File::open(&destination).expect("open diagnostics bundle");
        let mut archive = zip::ZipArchive::new(file).expect("read diagnostics bundle");
        let mut meta = String::new();
        archive
            .by_name("meta.json")
            .expect("metadata entry")
            .read_to_string(&mut meta)
            .expect("read metadata");
        assert!(meta.contains("\"version\": \"test\""));
        assert!(archive.by_name("app/alera.log").is_ok());
        let mut log = String::new();
        archive
            .by_name("runtime/runtime.log")
            .expect("runtime log entry")
            .read_to_string(&mut log)
            .expect("read runtime log");
        assert_eq!(log, "{\"source\":\"runtime\"}\n");
        assert!(archive.by_name("runtime/ignored.txt").is_err());
        let _ = std::fs::remove_dir_all(root);
    }
}
