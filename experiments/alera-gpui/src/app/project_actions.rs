use std::path::Path;
use std::time::{Duration, Instant};

use gpui::{Context, Window};
use serde_json::{json, Value};

use super::{AddProjectMode, AleraApp};
#[cfg(test)]
use super::add_project_draft::repository_name;
use crate::runtime_bridge::RuntimeBridge;

impl AleraApp {

    pub(super) fn submit_add_project(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.add_project_busy || !self.show_add_project_dialog || !self.can_submit_add_project(cx) {
            return;
        }
        let display_name = optional_input_value(&self.project_display_name_input, cx);
        let operation = match self.add_project_mode {
            AddProjectMode::LocalFolder => {
                let path = input_value(&self.local_project_path_input, cx);
                if path.is_empty() {
                    self.error = Some("Project path is required.".into());
                    cx.notify();
                    return;
                }
                AddProjectOperation::Register {
                    path,
                    name: display_name,
                }
            }
            AddProjectMode::CloneFromUrl => {
                let url = input_value(&self.clone_project_url_input, cx);
                let destination = input_value(&self.clone_project_destination_input, cx);
                if url.is_empty() || destination.is_empty() {
                    self.error = Some("Git URL and destination folder are required.".into());
                    cx.notify();
                    return;
                }
                let destination = Path::new(&destination);
                let Some(parent) = destination
                    .parent()
                    .filter(|path| !path.as_os_str().is_empty())
                else {
                    self.error = Some("Destination folder must include a parent path.".into());
                    cx.notify();
                    return;
                };
                let Some(directory_name) = destination
                    .file_name()
                    .and_then(|name| name.to_str())
                    .filter(|name| !name.is_empty())
                else {
                    self.error = Some("Destination folder must include a directory name.".into());
                    cx.notify();
                    return;
                };
                AddProjectOperation::Clone {
                    url,
                    parent_path: parent.to_string_lossy().into_owned(),
                    directory_name: directory_name.to_string(),
                    name: display_name,
                }
            }
        };

        let bridge = self.bridge.clone();
        let cloning = self.add_project_mode == AddProjectMode::CloneFromUrl;
        if !cloning { self.close_add_project_dialog(window, cx); }
        self.add_project_busy = true;
        self.error = None;
        cx.notify();
        let this = cx.entity().downgrade();
        window.spawn(cx, async move |cx| {
            let result = run_add_project_operation(&bridge, operation).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                this.add_project_busy = false;
                if this.show_add_project_dialog { this.close_add_project_dialog(window, cx); }
                match result {
                    Ok(()) => {
                        this.local_message = Some(if cloning { "Project cloned" } else { "Project added" }.into());
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                    }
                }
                this.local_message_started_at = Some(Instant::now());
                cx.notify();
            });
        })
        .detach();
    }
}

enum AddProjectOperation {
    Register {
        path: String,
        name: Option<String>,
    },
    Clone {
        url: String,
        parent_path: String,
        directory_name: String,
        name: Option<String>,
    },
}

async fn run_add_project_operation(
    bridge: &RuntimeBridge,
    operation: AddProjectOperation,
) -> Result<(), String> {
    match operation {
        AddProjectOperation::Register { path, name } => {
            let mut payload = json!({ "path": path });
            insert_optional_name(&mut payload, name);
            bridge.request("project.register", payload).await?;
            Ok(())
        }
        AddProjectOperation::Clone {
            url,
            parent_path,
            directory_name,
            name,
        } => {
            let mut payload = json!({
                "url": url,
                "parentPath": parent_path,
                "directoryName": directory_name,
            });
            insert_optional_name(&mut payload, name);
            let started = bridge.request("project.clone.start", payload).await?;
            let job_id = started
                .get("id")
                .and_then(Value::as_str)
                .ok_or_else(|| "Project Clone Did Not Return A Job ID".to_string())?;
            wait_for_clone(bridge, job_id).await
        }
    }
}

async fn wait_for_clone(bridge: &RuntimeBridge, job_id: &str) -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_secs(30 * 60);
    while Instant::now() < deadline {
        let jobs = bridge.request("project.clone.list", json!({})).await?;
        let job = jobs
            .as_array()
            .and_then(|jobs| {
                jobs.iter()
                    .find(|job| job.get("id").and_then(Value::as_str) == Some(job_id))
            })
            .ok_or_else(|| format!("Clone Job Disappeared: {job_id}"))?;
        match job.get("status").and_then(Value::as_str) {
            Some("completed") => return Ok(()),
            Some("failed") => {
                return Err(job
                    .get("error")
                    .and_then(Value::as_str)
                    .unwrap_or("Project Clone Failed")
                    .to_string());
            }
            Some("cancelled") => return Err("Project Clone Was Cancelled".to_string()),
            _ => {
                async_io::Timer::after(Duration::from_millis(300)).await;
            }
        }
    }
    Err("Project Clone Timed Out".to_string())
}

fn insert_optional_name(payload: &mut Value, name: Option<String>) {
    if let (Some(object), Some(name)) = (payload.as_object_mut(), name) {
        object.insert("name".to_string(), Value::String(name));
    }
}

fn input_value(
    input: &gpui::Entity<gpui_component::input::InputState>,
    cx: &Context<AleraApp>,
) -> String {
    input.read(cx).value().trim().to_string()
}

fn optional_input_value(
    input: &gpui::Entity<gpui_component::input::InputState>,
    cx: &Context<AleraApp>,
) -> Option<String> {
    let value = input_value(input, cx);
    (!value.is_empty()).then_some(value)
}


#[cfg(test)]
mod tests {
    use super::repository_name;

    #[test]
    fn derives_repository_names_from_common_git_urls() {
        assert_eq!(
            repository_name("https://github.com/owner/alera.git"),
            Some("alera".to_string())
        );
        assert_eq!(
            repository_name("git@github.com:owner/alera.git"),
            Some("alera".to_string())
        );
        assert_eq!(
            repository_name("https://example.com/owner/alera/?ref=main"),
            Some("alera".to_string())
        );
    }
}
