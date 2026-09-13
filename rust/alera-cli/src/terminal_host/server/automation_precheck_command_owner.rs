use std::sync::atomic::{AtomicBool, Ordering};

use alera_core::runtime::{
    AutomationDefinition, AutomationPrecheck, AutomationPrecheckProcess, AutomationRun,
    AutomationRunStatus, OwnerAutomationPrecheckRequest, RuntimeStore,
};

pub(super) enum PrecheckCommandOwner<'a> {
    Local {
        definition: &'a AutomationDefinition,
        run: &'a AutomationRun,
    },
    Remote {
        request: &'a OwnerAutomationPrecheckRequest,
        claimed: AtomicBool,
    },
}

impl<'a> PrecheckCommandOwner<'a> {
    pub(super) fn remote(request: &'a OwnerAutomationPrecheckRequest) -> Self {
        Self::Remote {
            request,
            claimed: AtomicBool::new(false),
        }
    }

    pub(super) fn claimed(&self) -> bool {
        matches!(self, Self::Remote { claimed, .. } if claimed.load(Ordering::Relaxed))
    }

    pub(super) fn precheck(&self) -> Result<&AutomationPrecheck, String> {
        match self {
            Self::Local { definition, .. } => definition
                .precheck
                .as_ref()
                .ok_or_else(|| "Automation has no precheck".into()),
            Self::Remote { request, .. } => Ok(&request.precheck),
        }
    }

    pub(super) fn command(&self, windows: bool) -> Result<(&str, Vec<&str>), String> {
        Ok(precheck_command(
            matches!(self, Self::Remote { .. }),
            windows,
            &self.precheck()?.command,
        ))
    }

    pub(super) async fn begin(
        &self,
        store: &RuntimeStore,
        boot: Option<String>,
    ) -> Result<Option<AutomationPrecheckProcess>, String> {
        match self {
            Self::Local { definition, run } => store
                .begin_automation_precheck_process(
                    run,
                    definition,
                    &uuid::Uuid::new_v4().to_string(),
                    std::env::consts::OS,
                    boot,
                )
                .await
                .map(Some)
                .map_err(|error| error.to_string()),
            Self::Remote { request, claimed } => {
                let record = store
                    .claim_owner_automation_precheck(request, std::env::consts::OS, boot)
                    .await
                    .map_err(|error| error.to_string())?;
                claimed.store(record.is_some(), Ordering::Relaxed);
                Ok(record)
            }
        }
    }

    pub(super) async fn cancellation(&self, store: &RuntimeStore) -> String {
        loop {
            let active = match self {
                Self::Local { run: started, .. } => {
                    store.find_automation_run(&started.id).await.map(|run| {
                        run.is_some_and(|run| {
                            run.cancel_requested_at.is_none()
                                && matches!(
                                    run.status,
                                    AutomationRunStatus::Dispatching
                                        | AutomationRunStatus::WaitingForUser
                                )
                                && run.attempt_count == started.attempt_count
                        })
                    })
                }
                Self::Remote { request, .. } => store
                    .find_owner_automation_precheck(&request.operation_id)
                    .await
                    .map(|job| {
                        job.is_some_and(|job| {
                            job.request == **request
                                && !job.cancel_requested
                                && job.outcome.is_none()
                        })
                    }),
            };
            match active {
                Ok(true) => {}
                Ok(false) => return "Automation precheck was cancelled or superseded".into(),
                Err(error) => {
                    return format!(
                        "Automation precheck cancellation state is unavailable: {error}"
                    )
                }
            }
            tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        }
    }

    pub(super) async fn report_unverified_closure(
        &self,
        store: &RuntimeStore,
        error: &str,
    ) -> bool {
        match self {
            Self::Local { run, .. } => store.update_automation_run_status(
                &run.id, AutomationRunStatus::WaitingForUser,
                Some(format!("Precheck process closure is unverified; retaining process ownership and retrying: {error}")),
            ).await.is_ok(),
            Self::Remote { request, .. } => {
                store.set_owner_precheck_attention(request, Some(&format!("Owner precheck closure is unverified; retaining native ownership and retrying: {error}"))).await.is_ok()
            }
        }
    }
}

fn precheck_command(remote: bool, windows: bool, command: &str) -> (&str, Vec<&str>) {
    // Preserve the original SSH interpreter when moving command ownership
    // from the transport into the native supervisor.
    match (remote, windows) {
        (true, true) => (
            "powershell",
            vec!["-NoProfile", "-NonInteractive", "-Command", command],
        ),
        (true, false) => ("sh", vec!["-lc", command]),
        (false, true) => ("cmd.exe", vec!["/d", "/c", command]),
        (false, false) => ("/bin/sh", vec!["-c", command]),
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn precheck_interpreters_preserve_local_and_ssh_command_semantics() {
        let command = "quoted 'argument'; $variable";
        for (remote, windows, program, flags) in [
            (
                true,
                true,
                "powershell",
                vec!["-NoProfile", "-NonInteractive", "-Command"],
            ),
            (true, false, "sh", vec!["-lc"]),
            (false, true, "cmd.exe", vec!["/d", "/c"]),
            (false, false, "/bin/sh", vec!["-c"]),
        ] {
            let (actual, arguments) = super::precheck_command(remote, windows, command);
            assert_eq!(actual, program);
            assert_eq!(&arguments[..arguments.len() - 1], flags);
            assert_eq!(arguments.last(), Some(&command));
        }
    }
}
