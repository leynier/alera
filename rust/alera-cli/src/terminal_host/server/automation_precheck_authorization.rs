use crate::ssh_remote::RemoteHostExecutor;
use alera_core::runtime::{AutomationDefinition, AutomationRun, RuntimeStore, LOCAL_HOST_ID};

pub(in crate::terminal_host::server) async fn execute_authorized_precheck<E, F>(
    store: &RuntimeStore,
    definition: &AutomationDefinition,
    run: &AutomationRun,
    host_id: &str,
    path: &str,
    executor: &E,
    command: F,
) -> Result<bool, String>
where
    E: RemoteHostExecutor,
    F: std::future::Future<Output = Result<bool, String>>,
{
    // Bound authorization only; the runner owns its process shutdown deadline.
    tokio::time::timeout(
        std::time::Duration::from_secs(
            definition
                .precheck
                .as_ref()
                .map_or(60, |value| value.timeout_seconds.max(1) as u64),
        ),
        authorize_remote_precheck(store, definition, run, host_id, path, executor),
    )
    .await
    .map_err(|_| "Automation precheck authorization timed out")??;
    command.await
}

pub(super) async fn authorize_remote_precheck<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    definition: &AutomationDefinition,
    run: &AutomationRun,
    host_id: &str,
    path: &str,
    executor: &E,
) -> Result<(), String> {
    let Some((project_id, target_host)) = definition.target.project_checkout() else {
        return Ok(());
    };
    if host_id == LOCAL_HOST_ID {
        return Ok(());
    }
    if target_host != host_id {
        return Err("Automation precheck host changed".into());
    }
    let project = store
        .find_project(project_id)
        .await
        .map_err(|error| error.to_string())?
        .ok_or("Automation precheck project is missing")?;
    let inspection = crate::remote_project_checkout::inspect_remote(
        store,
        host_id,
        path,
        project.kind,
        executor,
    )
    .await
    .map_err(|error| error.to_string())?;
    if inspection.path != path {
        return Err("Automation precheck checkout changed".into());
    }
    // Inspection is networked. Decisions may have changed while it was pending.
    let current = store
        .find_automation_run(&run.id)
        .await
        .map_err(|error| error.to_string())?
        .ok_or("Automation run disappeared during precheck authorization")?;
    if current.cancel_requested_at.is_some()
        || current.status != run.status
        || current.attempt_count != run.attempt_count
    {
        return Err("Automation precheck was cancelled or superseded before execution".into());
    }
    let snapshot = current.definition_snapshot.as_ref().unwrap_or(definition);
    if snapshot.revision != definition.revision || snapshot.target != definition.target {
        return Err("Automation run definition changed during precheck".into());
    }
    let checkout = store
        .find_project_checkout(project_id, host_id)
        .await
        .map_err(|error| error.to_string())?
        .ok_or("Automation precheck checkout disappeared")?;
    if checkout.path != path {
        return Err("Automation precheck checkout changed".into());
    }
    Ok(())
}
