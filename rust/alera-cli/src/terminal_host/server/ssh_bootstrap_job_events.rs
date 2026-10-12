use alera_core::runtime::SshBootstrapStatus;
use serde_json::{json, Value};

use super::ServerActor;
use crate::ssh_bootstrap::{SshTargetBootstrapJob, SshTargetBootstrapProgress};
use crate::terminal_host::protocol::event;

impl ServerActor {
    pub(super) fn list_ssh_bootstrap_jobs(&self) -> Value {
        let jobs = self
            .ssh_bootstrap_jobs
            .values()
            .map(|job| {
                json!(SshTargetBootstrapJob {
                    job_id: job.job_id.clone(),
                    target_id: job.target_id.clone(),
                    status: job.status,
                })
            })
            .collect::<Vec<_>>();
        json!(jobs)
    }

    pub(super) fn handle_ssh_bootstrap_progress(&mut self, progress: SshTargetBootstrapProgress) {
        let Some(job) = self.ssh_bootstrap_jobs.get_mut(&progress.target_id) else {
            return;
        };
        if job.job_id != progress.job_id {
            return;
        }
        job.status = progress.status;
        job.stage = progress.stage.clone();
        job.message = progress.message.clone();
        let target_id = progress.target_id.clone();
        self.broadcast_authenticated(event("sshTargetBootstrapProgress", json!(progress)));
        self.broadcast_ssh_targets_changed(Some(&target_id));
    }

    pub(super) fn handle_ssh_bootstrap_finished(
        &mut self,
        target_id: String,
        job_id: String,
        status: SshBootstrapStatus,
        error: Option<String>,
    ) {
        if self
            .ssh_bootstrap_jobs
            .get(&target_id)
            .is_some_and(|job| job.job_id == job_id)
        {
            self.ssh_bootstrap_jobs.remove(&target_id);
            self.broadcast_authenticated(event(
                "sshTargetBootstrapProgress",
                json!(SshTargetBootstrapProgress {
                    job_id,
                    target_id: target_id.clone(),
                    status,
                    stage: status.as_str().to_string(),
                    message: match status {
                        SshBootstrapStatus::Installed => "Remote Runtime Installed",
                        SshBootstrapStatus::Failed => "Remote Runtime Install Failed",
                        SshBootstrapStatus::Cancelled => "Remote Runtime Install Cancelled",
                        _ => "Remote Runtime Bootstrap Updated",
                    }
                    .to_string(),
                    error,
                }),
            ));
            self.broadcast_ssh_targets_changed(Some(&target_id));
            if status == SshBootstrapStatus::Installed {
                self.host_links.clear_configuration_failure(&target_id);
            }
            self.schedule_shutdown_if_idle();
        }
    }
}
