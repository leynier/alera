use serde::Deserialize;

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
        });
    }
    let build = descriptor
        .build_number
        .map(|build| format!(" - Build {build}"))
        .unwrap_or_default();
    Ok(UpdateCheckResult {
        status: "Update Available".to_string(),
        message: format!("Version {}{build}", descriptor.version),
    })
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
