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
        self.broadcast_authenticated(event("sshTargetBootstrapProgress", json!(progress)));
        self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
    }

    pub(super) fn handle_ssh_bootstrap_finished(
        &mut self,
        target_id: String,
        job_id: String,
        status: SshBootstrapStatus,
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
                    target_id,
                    status,
                    stage: status.as_str().to_string(),
                    message: match status {
                        SshBootstrapStatus::Installed => "Remote Runtime Installed",
                        SshBootstrapStatus::Failed => "Remote Runtime Install Failed",
                        SshBootstrapStatus::Cancelled => "Remote Runtime Install Cancelled",
                        _ => "Remote Runtime Bootstrap Updated",
                    }
                    .to_string(),
                    error: None,
                }),
            ));
            self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
            self.schedule_shutdown_if_idle();
        }
    }
}
