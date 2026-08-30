use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::{ProjectCloneJob, ProjectCloneJobPhase, ProjectCloneJobStatus};
use regex::Regex;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::oneshot;

use crate::project_management::register_project;
use crate::project_clone_staging::ProjectCloneStaging;
use super::ServerCommand;

pub(super) async fn run_clone_job(
    store: alera_core::runtime::RuntimeStore,
    inbox: tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    job: ProjectCloneJob,
    raw_url: String,
    mut cancel: oneshot::Receiver<()>,
) {
    let _ = store
        .update_project_clone_job(
            &job.id,
            ProjectCloneJobStatus::Running,
            ProjectCloneJobPhase::Cloning,
            None,
            Some("Cloning Repository"),
            None,
            None,
            None,
        )
        .await;
    let _ = inbox.send(ServerCommand::ProjectCloneChanged {
        job_id: job.id.clone(),
    });

    let parent = job.parent_path.clone();
    let job_id = job.id.clone();
    let staging = match tokio::task::spawn_blocking(move || ProjectCloneStaging::create(&parent, &job_id))
        .await.unwrap_or_else(|error| Err(error.into())) {
        Ok(staging) => staging,
        Err(error) => {
            finish_failed_clone(&store, &job, &raw_url, &error.to_string(), None).await;
            return;
        }
    };
    let mut command = clone_command(&job.parent_path, &raw_url, &staging.checkout_path());
    crate::login_shell_environment::apply_login_shell_environment(
        &mut command,
        &BTreeMap::from([("GIT_TERMINAL_PROMPT".into(), "0".into())]),
    ).await;
    if !matches!(cancel.try_recv(), Err(oneshot::error::TryRecvError::Empty)) {
        finish_cancelled_clone(&store, &job, &staging, None).await;
        return;
    }
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            finish_failed_clone(&store, &job, &raw_url, &error.to_string(), Some(&staging)).await;
            return;
        }
    };
    let stderr = child.stderr.take().expect("clone stderr is piped");
    let mut lines = BufReader::new(stderr).lines();
    let progress_pattern = Regex::new(r"(?:Receiving objects|Resolving deltas):\s+(\d+)%").unwrap();
    let mut last_progress = None;
    let mut last_message = "Cloning Repository".to_string();
    loop {
        tokio::select! {
            _ = &mut cancel => {
                let _ = child.kill().await;
                finish_cancelled_clone(&store, &job, &staging, last_progress).await;
                return;
            }
            line = lines.next_line() => {
                match line {
                    Ok(Some(line)) => {
                        last_message = sanitize_error(&line, &raw_url, &job.source);
                        last_progress = progress_pattern
                            .captures(&line)
                            .and_then(|captures| captures.get(1))
                            .and_then(|value| value.as_str().parse::<i64>().ok())
                            .or(last_progress);
                        let _ = store.update_project_clone_job(
                            &job.id,
                            ProjectCloneJobStatus::Running,
                            ProjectCloneJobPhase::Cloning,
                            last_progress,
                            Some(&last_message),
                            None,
                            None,
                            None,
                        ).await;
                        let _ = inbox.send(ServerCommand::ProjectCloneChanged { job_id: job.id.clone() });
                    }
                    Ok(None) => break,
                    Err(error) => {
                        last_message = error.to_string();
                        break;
                    }
                }
            }
        }
    }
    match child.wait().await {
        Ok(status) if status.success() => {}
        Ok(status) => {
            finish_failed_clone(
                &store,
                &job,
                &raw_url,
                &format!(
                    "Git Clone Failed With Exit Code {}: {last_message}",
                    status.code().unwrap_or(-1)
                ),
                Some(&staging),
            )
            .await;
            return;
        }
        Err(error) => {
            finish_failed_clone(&store, &job, &raw_url, &error.to_string(), Some(&staging)).await;
            return;
        }
    }

    if !matches!(cancel.try_recv(), Err(oneshot::error::TryRecvError::Empty)) {
        finish_cancelled_clone(&store, &job, &staging, last_progress).await;
        return;
    }
    let publish_staging = staging.clone();
    let destination = PathBuf::from(&job.destination_path);
    let published = tokio::task::spawn_blocking(move || publish_staging.publish(&destination))
        .await.unwrap_or_else(|error| Err(error.into()));
    if let Err(error) = published {
        finish_failed_clone(&store, &job, &raw_url, &error.to_string(), Some(&staging)).await;
        return;
    }
    let _ = store
        .update_project_clone_job(
            &job.id,
            ProjectCloneJobStatus::Running,
            ProjectCloneJobPhase::Registering,
            Some(100),
            Some("Registering Project"),
            None,
            None,
            None,
        )
        .await;
    match register_project(&store, &job.destination_path, job.project_name.as_deref()).await {
        Ok(result) => {
            if let Err(error) = cleanup_staging_area(&staging).await {
                tracing::warn!(job_id = %job.id, "clone staging cleanup failed after publication: {error}");
            }
            let _ = store
                .update_project_clone_job(
                    &job.id,
                    ProjectCloneJobStatus::Completed,
                    ProjectCloneJobPhase::Registering,
                    Some(100),
                    Some("Project Ready"),
                    None,
                    Some(&result.project.id),
                    Some(&result.main_workspace.id),
                )
                .await;
        }
        Err(error) => finish_failed_clone(&store, &job, &raw_url,
            &format!("{error}; cloned repository was preserved at {}", job.destination_path), Some(&staging)).await,
    }
}

async fn finish_failed_clone(
    store: &alera_core::runtime::RuntimeStore,
    job: &ProjectCloneJob,
    raw_url: &str,
    error: &str,
    staging: Option<&ProjectCloneStaging>,
) {
    let cleanup_error = if let Some(staging) = staging {
        cleanup_staging_area(staging).await.err().map(|error| error.to_string())
    } else { None };
    let mut error = sanitize_error(error, raw_url, &job.source);
    if let Some(cleanup_error) = cleanup_error {
        error.push_str(&format!("; Cleanup Failed: {cleanup_error}"));
    }
    let current = store.find_project_clone_job(&job.id).await.ok().flatten();
    let _ = store
        .update_project_clone_job(
            &job.id,
            ProjectCloneJobStatus::Failed,
            current.as_ref().map_or(job.phase, |current| current.phase),
            current.as_ref().and_then(|current| current.progress_percent).or(job.progress_percent),
            Some("Clone Failed"),
            Some(&error),
            None,
            None,
        )
        .await;
}

fn clone_command(parent: &str, source: &str, checkout: &Path) -> tokio::process::Command {
    let mut command = windowless_async_command("git");
    command.arg("-C").arg(parent).args(["clone", "--progress", "--"])
        .arg(source).arg(checkout).env("GIT_TERMINAL_PROMPT", "0")
        .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::piped()).kill_on_drop(true);
    command
}

async fn cleanup_staging_area(staging: &ProjectCloneStaging) -> anyhow::Result<()> {
    let staging = staging.clone();
    tokio::task::spawn_blocking(move || staging.cleanup()).await?
}

async fn finish_cancelled_clone(store: &alera_core::runtime::RuntimeStore, job: &ProjectCloneJob, staging: &ProjectCloneStaging, progress: Option<i64>) {
    let cleanup_error = cleanup_staging_area(staging).await.err().map(|error| format!("Clone cancelled; staging cleanup failed: {error}"));
    let _ = store.update_project_clone_job(&job.id, ProjectCloneJobStatus::Cancelled,
        ProjectCloneJobPhase::Cloning, progress, Some("Clone Cancelled"), cleanup_error.as_deref(), None, None).await;
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn clone_command_keeps_relative_sources_based_at_the_requested_parent() {
        let command = clone_command("parent", "../source.git", Path::new("staging/repository"));
        let command = command.as_std();
        let args = command.get_args().map(|value| value.to_string_lossy().into_owned()).collect::<Vec<_>>();
        assert_eq!(args, ["-C", "parent", "clone", "--progress", "--", "../source.git", "staging/repository"]);
        assert_eq!(command.get_envs().find(|(key, _)| *key == "GIT_TERMINAL_PROMPT").and_then(|(_, value)| value), Some(std::ffi::OsStr::new("0")));
    }

    fn fixture_job(parent: &Path, source: &Path, directory: &str) -> ProjectCloneJob {
        let now = chrono::Utc::now();
        ProjectCloneJob {
            id: uuid::Uuid::new_v4().to_string(), source: source.to_string_lossy().into_owned(),
            parent_path: parent.to_string_lossy().into_owned(), directory_name: directory.into(),
            destination_path: parent.join(directory).to_string_lossy().into_owned(),
            project_name: Some("Clone Regression".into()), status: ProjectCloneJobStatus::Queued,
            phase: ProjectCloneJobPhase::Cloning, progress_percent: None, message: None, error: None,
            project_id: None, workspace_id: None, created_at: now, updated_at: now, finished_at: None,
        }
    }

    fn empty_origin(parent: &Path) -> PathBuf {
        let origin = parent.join("origin.git");
        let templates = parent.join("empty-templates");
        std::fs::create_dir(&templates).unwrap();
        let output = alera_core::child_process::windowless_command("git")
            .args(["init", "--bare", "--initial-branch=main"])
            .arg(format!("--template={}", templates.display())).arg(&origin).output().unwrap();
        assert!(output.status.success());
        origin
    }

    #[tokio::test]
    async fn clone_worker_publishes_before_registering_and_cleans_only_staging() {
        let parent = tempfile::tempdir().unwrap();
        let runtime = tempfile::tempdir().unwrap();
        let store = alera_core::runtime::RuntimeStore::open(runtime.path()).await.unwrap();
        let parent = std::fs::canonicalize(parent.path()).unwrap();
        let source = empty_origin(&parent);
        let job = fixture_job(&parent, &source, "published");
        store.insert_project_clone_job(job.clone()).await.unwrap();
        let (inbox, _events) = tokio::sync::mpsc::unbounded_channel();
        let (_cancel, receiver) = oneshot::channel();
        run_clone_job(store.clone(), inbox, job.clone(), job.source.clone(), receiver).await;
        let result = store.find_project_clone_job(&job.id).await.unwrap().unwrap();
        assert!(matches!(result.status, ProjectCloneJobStatus::Completed), "{:?}", result.error);
        assert!(result.project_id.is_some() && result.workspace_id.is_some());
        assert!(Path::new(&job.destination_path).join(".git").is_dir());
        assert!(!parent.join(format!(".alera-clone-{}", job.id)).exists());
    }

    #[tokio::test]
    async fn clone_worker_failure_preserves_a_destination_created_after_validation() {
        let parent = tempfile::tempdir().unwrap();
        let runtime = tempfile::tempdir().unwrap();
        let store = alera_core::runtime::RuntimeStore::open(runtime.path()).await.unwrap();
        let parent = std::fs::canonicalize(parent.path()).unwrap();
        let source = empty_origin(&parent);
        let job = fixture_job(&parent, &source, "competing");
        store.insert_project_clone_job(job.clone()).await.unwrap();
        std::fs::create_dir(&job.destination_path).unwrap();
        let keep = Path::new(&job.destination_path).join("keep");
        std::fs::write(&keep, "another job owns this").unwrap();
        let (inbox, _events) = tokio::sync::mpsc::unbounded_channel();
        let (_cancel, receiver) = oneshot::channel();
        run_clone_job(store.clone(), inbox, job.clone(), job.source.clone(), receiver).await;
        let result = store.find_project_clone_job(&job.id).await.unwrap().unwrap();
        assert!(matches!(result.status, ProjectCloneJobStatus::Failed));
        assert!(result.project_id.is_none());
        assert_eq!(std::fs::read_to_string(keep).unwrap(), "another job owns this");
        assert!(!parent.join(format!(".alera-clone-{}", job.id)).exists());
    }

    #[tokio::test]
    async fn clone_worker_cancelled_before_spawn_preserves_the_destination() {
        let parent = tempfile::tempdir().unwrap();
        let runtime = tempfile::tempdir().unwrap();
        let store = alera_core::runtime::RuntimeStore::open(runtime.path()).await.unwrap();
        let parent = std::fs::canonicalize(parent.path()).unwrap();
        let job = fixture_job(&parent, &parent.join("missing.git"), "competing");
        store.insert_project_clone_job(job.clone()).await.unwrap();
        std::fs::create_dir(&job.destination_path).unwrap();
        let keep = Path::new(&job.destination_path).join("keep");
        std::fs::write(&keep, "keep").unwrap();
        let (inbox, _events) = tokio::sync::mpsc::unbounded_channel();
        let (cancel, receiver) = oneshot::channel();
        cancel.send(()).unwrap();
        run_clone_job(store.clone(), inbox, job.clone(), job.source.clone(), receiver).await;
        let result = store.find_project_clone_job(&job.id).await.unwrap().unwrap();
        assert!(matches!(result.status, ProjectCloneJobStatus::Cancelled));
        assert!(keep.exists());
        assert!(!parent.join(format!(".alera-clone-{}", job.id)).exists());
    }
}

pub(super) fn sanitized_clone_source(raw: &str) -> String {
    let Ok(mut url) = url::Url::parse(raw) else {
        return raw.to_string();
    };
    let _ = url.set_username("");
    let _ = url.set_password(None);
    url.to_string()
}

fn sanitize_error(error: &str, raw_url: &str, safe_url: &str) -> String {
    error.replace(raw_url, safe_url)
}
