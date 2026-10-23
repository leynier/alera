//! Remote runtime install jobs: `sshTarget.bootstrap.start` and
//! `sshTarget.bootstrap.cancel`. The install itself runs in a spawned task
//! and reports through `ServerCommand::SshBootstrapProgress` and
//! `SshBootstrapFinished` (see [`super::ssh_bootstrap_job_events`]). With
//! `restartRuntime`, the same job restarts the host's runtime onto the new
//! version once the install is validated ([`super::ssh_bootstrap_restart`]).

use alera_core::runtime::{SshBootstrapStatus, SshTarget};
use serde_json::{json, Value};
use tokio::task::JoinHandle;

use super::ssh_bootstrap_restart::{
    installed_version_dir, restart_satellite_runtime, RestartTiming, SshRestartRemote,
};
use super::{ServerActor, ServerCommand};
use crate::ssh_bootstrap::{
    cancel_ssh_bootstrap, mark_ssh_bootstrap_installing, new_bootstrap_job_id,
    reject_password_ssh_bootstrap_auth, run_ssh_bootstrap, SshTargetBootstrapJob,
    SshTargetBootstrapProgress, SshTargetBootstrapRequest,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

pub(super) struct SshBootstrapJobState {
    pub(super) job_id: String,
    pub(super) target_id: String,
    pub(super) status: SshBootstrapStatus,
    /// Last progress stage and message, for the host status.
    pub(super) stage: String,
    pub(super) message: String,
    pub(super) handle: JoinHandle<()>,
}

impl ServerActor {
    pub(super) async fn start_ssh_bootstrap_job(
        &mut self,
        request: SshTargetBootstrapRequest,
    ) -> HostResult<Value> {
        if let Some(existing) = self.ssh_bootstrap_jobs.get(&request.target_id) {
            return Ok(json!(SshTargetBootstrapJob {
                job_id: existing.job_id.clone(),
                target_id: existing.target_id.clone(),
                status: existing.status,
            }));
        }
        let target = self.find_ssh_target_or_refuse(&request.target_id).await?;
        reject_password_ssh_bootstrap_auth(target.auth_kind)
            .map_err(|error| HostError::from_anyhow(&error))?;
        // Refused before anything is installed, so the client can confirm and
        // retry with `force` without a half-finished job to clean up.
        if request.restart_runtime && !request.force {
            self.refuse_busy_host(&target).await?;
        }
        let job_id = new_bootstrap_job_id();
        mark_ssh_bootstrap_installing(&self.runtime_store, &target.id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?;
        self.broadcast_authenticated(event(
            "sshTargetBootstrapProgress",
            json!(SshTargetBootstrapProgress {
                job_id: job_id.clone(),
                target_id: target.id.clone(),
                status: SshBootstrapStatus::Installing,
                stage: "auth".to_string(),
                message: "Checking SSH Authentication".to_string(),
                error: None,
            }),
        ));
        self.broadcast_ssh_targets_changed(Some(&target.id));
        let target_id = request.target_id.clone();
        let store = self.runtime_store.clone();
        let cache_dir = self.runtime_dir.join("runtime-artifacts");
        let inbox = self.inbox.clone();
        let links = self.host_links.clone();
        let task_job_id = job_id.clone();
        let task_target_id = target_id.clone();
        let restart = request.restart_runtime.then_some(request.force);
        let handle = tokio::spawn(async move {
            let progress_inbox = inbox.clone();
            let result =
                run_ssh_bootstrap(store, cache_dir, request, task_job_id.clone(), |progress| {
                    // With a restart to follow, `installed` is the job's last
                    // word, sent once the new runtime answers.
                    if restart.is_some() && progress.stage == "installed" {
                        return;
                    }
                    let _ = progress_inbox.send(ServerCommand::SshBootstrapProgress { progress });
                })
                .await;
            let outcome = match (result, restart) {
                (Ok(installed), Some(force)) => {
                    let emit_inbox = inbox.clone();
                    let job_id = task_job_id.clone();
                    restart_satellite_runtime(
                        &links,
                        &installed,
                        force,
                        installed_version_dir(&installed),
                        &SshRestartRemote,
                        RestartTiming::default(),
                        |stage, message| {
                            let _ = emit_inbox.send(ServerCommand::SshBootstrapProgress {
                                progress: SshTargetBootstrapProgress {
                                    job_id: job_id.clone(),
                                    target_id: installed.id.clone(),
                                    status: SshBootstrapStatus::Installing,
                                    stage: stage.to_string(),
                                    message: message.to_string(),
                                    error: None,
                                },
                            });
                        },
                    )
                    .await
                    .map(|_| ())
                    .map_err(|error| error.wire_message())
                }
                (Ok(_), None) => Ok(()),
                (Err(error), _) => Err(format!("{error:#}")),
            };
            let (status, error) = match outcome {
                Ok(()) => (SshBootstrapStatus::Installed, None),
                Err(error) => (SshBootstrapStatus::Failed, Some(error)),
            };
            let _ = inbox
                .send_wait(ServerCommand::SshBootstrapFinished {
                    target_id: task_target_id,
                    job_id: task_job_id,
                    status,
                    error,
                })
                .await;
        });
        let job = SshBootstrapJobState {
            job_id: job_id.clone(),
            target_id: target_id.clone(),
            status: SshBootstrapStatus::Installing,
            stage: "auth".to_string(),
            message: "Checking SSH Authentication".to_string(),
            handle,
        };
        self.ssh_bootstrap_jobs.insert(target_id.clone(), job);
        self.cancel_shutdown_timer();
        Ok(json!(SshTargetBootstrapJob {
            job_id,
            target_id,
            status: SshBootstrapStatus::Installing,
        }))
    }

    /// `sshTarget.restartRuntime {id, force?}`: only the restart that follows
    /// an update, for a host whose runtime is already installed. Answers once
    /// the restarted runtime has attached, so it runs off the actor.
    pub(super) async fn start_ssh_runtime_restart(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let id = ["id", "targetId"]
            .iter()
            .find_map(|key| payload.get(*key).and_then(Value::as_str))
            .map(str::trim)
            .filter(|id| !id.is_empty())
            .ok_or_else(|| HostError::state("id is required"))?
            .to_string();
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let target = self.find_ssh_target_or_refuse(&id).await?;
        if self.ssh_bootstrap_jobs.contains_key(&target.id) {
            return Err(HostError::state(format!(
                "An Alera runtime install is already running on {}.",
                target.alias
            )));
        }
        if target.bootstrap_status != SshBootstrapStatus::Installed {
            return Err(HostError::state(format!(
                "Install the Alera runtime on {} before restarting it.",
                target.alias
            )));
        }
        if !force {
            self.refuse_busy_host(&target).await?;
        }
        let links = self.host_links.clone();
        self.spawn_deferred_request(client_id, request_id, async move {
            let version = restart_satellite_runtime(
                &links,
                &target,
                force,
                None,
                &SshRestartRemote,
                RestartTiming::default(),
                |_, _| {},
            )
            .await?;
            Ok(json!({ "hostId": target.id, "satelliteVersion": version }))
        });
        Ok(())
    }

    async fn find_ssh_target_or_refuse(&self, target_id: &str) -> HostResult<SshTarget> {
        self.runtime_store
            .find_ssh_target(target_id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?
            .ok_or_else(|| HostError::state(format!("ssh target not found: {target_id}")))
    }

    /// `hostBusy` while hub terminals still run on the host, because stopping
    /// its runtime ends them.
    async fn refuse_busy_host(&self, target: &SshTarget) -> HostResult<()> {
        let sessions: Vec<String> = self
            .sessions_on_host(&target.id)
            .await
            .into_iter()
            .filter(|id| {
                self.sessions
                    .get(id)
                    .is_some_and(|session| session.running())
            })
            .collect();
        match super::ssh_bootstrap_restart::host_busy_conflict(target, sessions) {
            Some(conflict) => Err(conflict),
            None => Ok(()),
        }
    }

    pub(super) async fn cancel_ssh_bootstrap_job(&mut self, target_id: &str) -> HostResult<Value> {
        if let Some(target) = self
            .cancel_active_ssh_bootstrap_job(target_id, "Remote Runtime Install Cancelled")
            .await?
        {
            self.schedule_shutdown_if_idle();
            return Ok(json!(target));
        }
        if let Some(target) = self
            .runtime_store
            .find_ssh_target(target_id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?
        {
            if target.bootstrap_status == SshBootstrapStatus::Installing {
                let target = self
                    .mark_ssh_bootstrap_cancelled(
                        target_id,
                        new_bootstrap_job_id(),
                        "Stale Remote Runtime Install Cancelled",
                    )
                    .await?;
                self.schedule_shutdown_if_idle();
                return Ok(json!(target));
            }
        }
        Err(HostError::state(format!(
            "No active bootstrap job for SSH target: {target_id}"
        )))
    }

    pub(super) async fn cancel_ssh_bootstrap_job_before_remove(
        &mut self,
        target_id: &str,
    ) -> HostResult<()> {
        self.cancel_active_ssh_bootstrap_job(target_id, "Remote Runtime Install Cancelled")
            .await?;
        self.schedule_shutdown_if_idle();
        Ok(())
    }

    async fn cancel_active_ssh_bootstrap_job(
        &mut self,
        target_id: &str,
        message: &str,
    ) -> HostResult<Option<SshTarget>> {
        let Some(job) = self.ssh_bootstrap_jobs.remove(target_id) else {
            return Ok(None);
        };
        job.handle.abort();
        self.mark_ssh_bootstrap_cancelled(target_id, job.job_id, message)
            .await
            .map(Some)
    }

    async fn mark_ssh_bootstrap_cancelled(
        &mut self,
        target_id: &str,
        job_id: String,
        message: &str,
    ) -> HostResult<SshTarget> {
        let target = cancel_ssh_bootstrap(&self.runtime_store, target_id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?;
        let progress = SshTargetBootstrapProgress {
            job_id,
            target_id: target_id.to_string(),
            status: SshBootstrapStatus::Cancelled,
            stage: "cancelled".to_string(),
            message: message.to_string(),
            error: None,
        };
        self.broadcast_authenticated(event("sshTargetBootstrapProgress", json!(progress)));
        self.broadcast_ssh_targets_changed(Some(target_id));
        Ok(target)
    }
}
