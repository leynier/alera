use std::path::Path;
use std::time::{Duration, Instant};

use gpui::{Context, PathPromptOptions, Timer, Window};
use serde_json::{json, Value};

use super::{AddProjectMode, AleraApp};
use crate::runtime_bridge::RuntimeBridge;

impl AleraApp {
    pub(super) fn add_project(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.add_project_mode = AddProjectMode::LocalFolder;
        self.show_add_project_dialog = true;
        self.error = None;
        self.local_project_path_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.clone_project_url_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.clone_project_destination_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.project_display_name_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        cx.notify();
    }

    pub(super) fn select_add_project_mode(&mut self, mode: AddProjectMode, cx: &mut Context<Self>) {
        if self.add_project_busy || self.add_project_mode == mode {
            return;
        }
        self.add_project_mode = mode;
        self.error = None;
        cx.notify();
    }

    pub(super) fn close_add_project_dialog(&mut self, cx: &mut Context<Self>) {
        if self.add_project_busy {
            return;
        }
        self.show_add_project_dialog = false;
        self.error = None;
        cx.notify();
    }

    pub(super) fn browse_local_project(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let selection = cx.prompt_for_paths(directory_prompt("Select Project Folder"));
        let this = cx.entity().downgrade();
        window
            .spawn(cx, async move |cx| {
                let path = match selection.await {
                    Ok(Ok(Some(paths))) => paths.into_iter().next(),
                    Ok(Ok(None)) => None,
                    Ok(Err(error)) => {
                        let _ = this.update(cx, |this, cx| {
                            this.error = Some(error.to_string().into());
                            cx.notify();
                        });
                        None
                    }
                    Err(error) => {
                        let _ = this.update(cx, |this, cx| {
                            this.error = Some(error.to_string().into());
                            cx.notify();
                        });
                        None
                    }
                };
                let Some(path) = path else {
                    return;
                };
                let display_name = path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or_default()
                    .to_string();
                let path_value = path.to_string_lossy().into_owned();
                let _ = this.update_in(cx, move |this, window, cx| {
                    this.local_project_path_input
                        .update(cx, |input, cx| input.set_value(path_value, window, cx));
                    if this
                        .project_display_name_input
                        .read(cx)
                        .value()
                        .trim()
                        .is_empty()
                    {
                        this.project_display_name_input
                            .update(cx, |input, cx| input.set_value(display_name, window, cx));
                    }
                    cx.notify();
                });
            })
            .detach();
    }

    pub(super) fn browse_clone_parent(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let repo_name = repository_name(self.clone_project_url_input.read(cx).value().as_ref());
        if repo_name.is_none() {
            self.error = Some("Enter A Git URL Before Choosing The Parent Folder".into());
            cx.notify();
            return;
        }
        let selection = cx.prompt_for_paths(directory_prompt("Select Parent Folder"));
        let this = cx.entity().downgrade();
        window
            .spawn(cx, async move |cx| {
                let parent = match selection.await {
                    Ok(Ok(Some(paths))) => paths.into_iter().next(),
                    Ok(Ok(None)) => None,
                    Ok(Err(error)) => {
                        let _ = this.update(cx, |this, cx| {
                            this.error = Some(error.to_string().into());
                            cx.notify();
                        });
                        None
                    }
                    Err(error) => {
                        let _ = this.update(cx, |this, cx| {
                            this.error = Some(error.to_string().into());
                            cx.notify();
                        });
                        None
                    }
                };
                let Some(parent) = parent else {
                    return;
                };
                let repo_name = repo_name.expect("repository name checked before folder prompt");
                let destination = parent.join(&repo_name).to_string_lossy().into_owned();
                let _ = this.update_in(cx, move |this, window, cx| {
                    this.clone_project_destination_input
                        .update(cx, |input, cx| input.set_value(destination, window, cx));
                    if this
                        .project_display_name_input
                        .read(cx)
                        .value()
                        .trim()
                        .is_empty()
                    {
                        this.project_display_name_input
                            .update(cx, |input, cx| input.set_value(repo_name, window, cx));
                    }
                    this.error = None;
                    cx.notify();
                });
            })
            .detach();
    }

    pub(super) fn submit_add_project(&mut self, cx: &mut Context<Self>) {
        if self.add_project_busy {
            return;
        }
        let display_name = optional_input_value(&self.project_display_name_input, cx);
        let operation = match self.add_project_mode {
            AddProjectMode::LocalFolder => {
                let path = input_value(&self.local_project_path_input, cx);
                if path.is_empty() {
                    self.error = Some("Project Path Is Required".into());
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
                    self.error = Some("Git URL And Destination Folder Are Required".into());
                    cx.notify();
                    return;
                }
                let destination = Path::new(&destination);
                let Some(parent) = destination
                    .parent()
                    .filter(|path| !path.as_os_str().is_empty())
                else {
                    self.error = Some("Destination Folder Must Include A Parent Path".into());
                    cx.notify();
                    return;
                };
                let Some(directory_name) = destination
                    .file_name()
                    .and_then(|name| name.to_str())
                    .filter(|name| !name.is_empty())
                else {
                    self.error = Some("Destination Folder Must Include A Directory Name".into());
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
        self.add_project_busy = true;
        self.error = None;
        cx.notify();
        cx.spawn(async move |this, cx| {
            let result = run_add_project_operation(&bridge, operation).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.add_project_busy = false;
                match result {
                    Ok(()) => {
                        this.show_add_project_dialog = false;
                        this.error = None;
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.error = Some(error.into());
                        cx.notify();
                    }
                }
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
                Timer::after(Duration::from_millis(300)).await;
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

fn repository_name(value: &str) -> Option<String> {
    let without_query = value
        .trim()
        .split('?')
        .next()?
        .trim_end_matches(['/', '\\']);
    let name = without_query
        .rsplit(['/', '\\', ':'])
        .next()?
        .strip_suffix(".git")
        .unwrap_or_else(|| {
            without_query
                .rsplit(['/', '\\', ':'])
                .next()
                .unwrap_or_default()
        })
        .trim();
    (!name.is_empty()).then(|| name.to_string())
}

fn directory_prompt(prompt: &'static str) -> PathPromptOptions {
    PathPromptOptions {
        files: false,
        directories: true,
        multiple: false,
        prompt: Some(prompt.into()),
    }
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
