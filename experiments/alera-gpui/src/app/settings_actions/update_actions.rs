use serde::Deserialize;
use std::process::Stdio;

use alera_core::child_process::windowless_command;

const UPDATE_INDEX_URL: &str =
    "https://updates.alera.build/updates/stable/app-archive.json";

#[derive(Debug, Deserialize)]
struct UpdateIndex {
    #[serde(default)]
    items: Vec<UpdateIndexItem>,
}

#[derive(Debug, Deserialize)]
struct UpdateIndexItem {
    version: String,
    platform: String,
    channel: String,
    release: String,
}

#[derive(Debug, Deserialize)]
struct ReleaseDescriptor {
    version: String,
    #[serde(rename = "buildNumber")]
    build_number: Option<i64>,
    platform: String,
    channel: String,
    #[serde(rename = "packageId")]
    package_id: String,
    #[serde(rename = "appName")]
    app_name: String,
}

struct UpdateCheckResult {
    status: String,
    message: String,
    current_version: String,
    current_build_number: Option<String>,
    latest_version: Option<String>,
    latest_build_number: Option<String>,
    upgrade_command: Option<String>,
    upgrade_manager: Option<String>,
}

impl AleraApp {
    pub(super) fn check_for_updates(&mut self, cx: &mut Context<Self>) {
        self.start_update_check(false, cx);
    }

    /// The application menu uses the same updater as Settings, but Flutter
    /// surfaces the result as a toast when the request did not originate in
    /// the Settings pane. Keep that presentation decision outside the worker
    /// so opening Settings never emits an unexpected notification.
    pub(crate) fn check_for_updates_from_menu(&mut self, cx: &mut Context<Self>) {
        self.start_update_check(true, cx);
    }

    pub(super) fn require_update_restart(&mut self, cx: &mut Context<Self>) {
        if self.settings_state.update_latest_version.is_none() || self.settings_state.update_busy {
            return;
        }
        self.settings_state.update_restart_required = true;
        self.settings_state.update_status = "Restart Alera".to_owned();
        self.settings_state.update_message =
            Some("Restart Alera To Load Any Update Installed By The Command.".to_owned());
        cx.notify();
    }

    pub(super) fn restart_app(&mut self, cx: &mut Context<Self>) {
        if self.settings_state.update_busy {
            return;
        }
        let Ok(executable) = std::env::current_exe() else {
            self.settings_state.update_status = "Update Failed".to_owned();
            self.settings_state.update_message = Some("Alera Could Not Locate Its Executable.".to_owned());
            cx.notify();
            return;
        };
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(250));
            let mut command = windowless_command(executable);
            command
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null());
            let _ = command.spawn();
        });
        cx.quit();
    }

    pub(super) fn run_update_command(&mut self, cx: &mut Context<Self>) {
        let Some(command) = self.settings_state.update_upgrade_command.clone() else {
            return;
        };
        let manager = self
            .settings_state
            .update_upgrade_manager
            .clone()
            .unwrap_or_else(|| "Package Manager".to_owned());
        self.open_command_terminal_with_follow_up(
            super::command_terminal::CommandTerminalRequest {
                title: "Update Alera".to_owned(),
                command,
                description: Some(format!(
                    "The {manager} Update Runs Here. Answer Any Prompt In The Terminal."
                )),
                working_directory: None,
            },
            false,
            true,
            cx,
        );
    }

    fn start_update_check(&mut self, show_feedback: bool, cx: &mut Context<Self>) {
        if self.settings_state.update_busy {
            return;
        }
        self.settings_state.update_busy = true;
        self.settings_state.update_status = "Checking for Updates".to_string();
        self.settings_state.update_message = None;
        let (sender, receiver) = async_channel::bounded(1);
        std::thread::Builder::new()
            .name("alera-gpui-update-check".to_string())
            .spawn(move || {
                let _ = sender.send_blocking(fetch_update_status());
            })
            .expect("failed to start update check");
        cx.spawn(async move |this, cx| {
            let result = receiver
                .recv()
                .await
                .unwrap_or_else(|error| Err(format!("Update check stopped: {error}")));
            let _ = this.update(cx, |this, cx| {
                this.settings_state.update_busy = false;
                match result {
            Ok(result) => {
                this.settings_state.update_status = result.status;
                this.settings_state.update_message = Some(result.message.clone());
                this.settings_state.update_current_version = Some(result.current_version);
                this.settings_state.update_current_build_number = result.current_build_number;
                this.settings_state.update_latest_version = result.latest_version;
                this.settings_state.update_latest_build_number = result.latest_build_number;
                this.settings_state.update_upgrade_command = result.upgrade_command;
                this.settings_state.update_upgrade_manager = result.upgrade_manager;
                this.settings_state.update_restart_required = false;
                        if show_feedback {
                            this.local_message = Some(result.message.into());
                        }
                    }
                    Err(error) => {
                        this.settings_state.update_status = "Update Failed".to_string();
                        let message = if error.starts_with("The release descriptor") {
                            format!("Update check failed: FormatException: {error}")
                        } else {
                            format!("Update check failed: {error}")
                        };
                this.settings_state.update_message = Some(message.clone());
                this.settings_state.update_latest_version = None;
                this.settings_state.update_latest_build_number = None;
                this.settings_state.update_upgrade_command = None;
                this.settings_state.update_upgrade_manager = None;
                this.settings_state.update_restart_required = false;
                        if show_feedback {
                            this.local_message = Some(message.into());
                        }
                    }
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }
}

fn fetch_update_status() -> Result<UpdateCheckResult, String> {
    let platform = std::env::consts::OS;
    let current_version = env!("CARGO_PKG_VERSION").to_string();
    let response = reqwest::blocking::get(UPDATE_INDEX_URL)
        .map_err(|error| format!("Update metadata request failed: {error}"))?;
    let status = response.status();
    if !status.is_success() {
        return Err(format!(
            "Update metadata request failed with HTTP {status}."
        ));
    }
    let index = response
        .json::<UpdateIndex>()
        .map_err(|error| format!("Could Not Read Update Index: {error}"))?;
    let Some(item) = index
        .items
        .into_iter()
        .find(|item| item.platform == platform && item.channel == "stable")
    else {
        return Ok(UpdateCheckResult {
            status: "No Update Available".to_string(),
            message: "Alera is up to date.".to_string(),
            current_version,
            current_build_number: None,
            latest_version: None,
            latest_build_number: None,
            upgrade_command: None,
            upgrade_manager: None,
        });
    };
    let descriptor_response = reqwest::blocking::get(&item.release)
        .map_err(|error| format!("Release metadata request failed: {error}"))?;
    let descriptor_status = descriptor_response.status();
    if !descriptor_status.is_success() {
        return Err(format!(
            "Release metadata request failed with HTTP {descriptor_status}."
        ));
    }
    let descriptor = descriptor_response
        .json::<ReleaseDescriptor>()
        .map_err(|error| format!("Could Not Read Release Descriptor: {error}"))?;
    if descriptor.version != item.version
        || descriptor.platform != item.platform
        || descriptor.channel != item.channel
        || descriptor.package_id != "dev.leynier.alera"
        || descriptor.app_name != "Alera"
    {
        return Err(
            "The release descriptor does not match its update index entry.".to_string(),
        );
    }
    if !version_is_newer(&descriptor.version, env!("CARGO_PKG_VERSION")) {
        return Ok(UpdateCheckResult {
            status: "No Update Available".to_string(),
            message: "Alera is up to date.".to_string(),
            current_version,
            current_build_number: None,
            latest_version: Some(descriptor.version),
            latest_build_number: descriptor.build_number.map(|build| build.to_string()),
            upgrade_command: None,
            upgrade_manager: None,
        });
    }
    let build = descriptor
        .build_number
        .map(|build| format!(" - Build {build}"))
        .unwrap_or_default();
    Ok(UpdateCheckResult {
        status: "Update Available".to_string(),
        message: format!("Version {}{build}", descriptor.version),
        current_version,
        current_build_number: None,
        latest_version: Some(descriptor.version),
        latest_build_number: descriptor.build_number.map(|build| build.to_string()),
        upgrade_command: package_manager_upgrade_command(),
        upgrade_manager: package_manager_upgrade_manager(),
    })
}

fn package_manager_upgrade_command() -> Option<String> {
    let executable = std::env::current_exe().ok()?.to_string_lossy().to_ascii_lowercase();
    if cfg!(target_os = "macos") && executable.contains("/caskroom/alera/") {
        return Some("brew upgrade --cask alera".to_owned());
    }
    if cfg!(target_os = "windows") && executable.replace('\\', "/").contains("/apps/alera/current/") {
        return Some("scoop update alera".to_owned());
    }
    if cfg!(target_os = "linux") && executable.contains("/usr/bin/") {
        return Some("sudo apt-get update && sudo apt-get install --only-upgrade alera".to_owned());
    }
    None
}

fn package_manager_upgrade_manager() -> Option<String> {
    let command = package_manager_upgrade_command()?;
    if command.starts_with("brew ") {
        Some("Homebrew".to_owned())
    } else if command.starts_with("scoop ") {
        Some("Scoop".to_owned())
    } else {
        Some("Package Manager".to_owned())
    }
}

fn version_is_newer(candidate: &str, current: &str) -> bool {
    let candidate = version_parts(candidate);
    let current = version_parts(current);
    candidate > current
}

fn version_parts(value: &str) -> Vec<u64> {
    value
        .trim()
        .trim_start_matches('v')
        .split(['.', '-', '+'])
        .map(|part| part.parse::<u64>().unwrap_or(0))
        .collect()
}
