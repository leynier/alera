//! The one write path for dispatch contexts. A shared run (or a task outside
//! any run) dispatches to a terminal; an isolated run dispatches only to the
//! terminal of its task's current attempt.

use anyhow::{bail, Result};
use sqlx::SqliteConnection;

use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};

pub(super) enum DispatchTarget<'a> {
    Terminal {
        handle: &'a str,
        coordinator_handle: &'a str,
        terminal_policy: &'a str,
    },
    Attempt {
        workspace_id: &'a str,
        terminal_handle: &'a str,
        launch_id: &'a str,
        profile_name: &'a str,
        quota_group: Option<&'a str>,
    },
}

impl DispatchTarget<'_> {
    fn assignee(&self) -> &str {
        match self {
            DispatchTarget::Terminal { handle, .. } => handle,
            DispatchTarget::Attempt {
                terminal_handle, ..
            } => terminal_handle,
        }
    }
}

pub(super) struct NewRunDispatch<'a> {
    pub id: &'a str,
    pub task_id: &'a str,
    pub run_id: Option<&'a str>,
    pub workspace_id: &'a str,
    pub context_token_hash: Option<&'a str>,
    pub failure_count: i64,
    pub target: DispatchTarget<'a>,
}

/// An isolated run's tasks may only be dispatched to the terminal of their
/// current attempt launch.
pub(super) async fn ensure_dispatch_target_allowed(
    conn: &mut SqliteConnection,
    task_id: &str,
    target: &DispatchTarget<'_>,
) -> Result<()> {
    let isolated: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM orchestrationTasks t
            JOIN orchestrationCoordinatorRuns r ON r.id = t.run_id
            WHERE t.id = ? AND r.isolation = 'isolated')",
    )
    .bind(task_id)
    .fetch_one(&mut *conn)
    .await?;
    match target {
        DispatchTarget::Terminal { .. } if isolated => {
            bail!("isolated runs dispatch only to the terminal of the task's current attempt")
        }
        DispatchTarget::Attempt {
            launch_id,
            terminal_handle,
            workspace_id,
            ..
        } => {
            let current: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM runLaunches l WHERE l.id = ? AND l.task_id = ?
                    AND l.terminal_handle = ? AND l.workspace_id = ?
                    AND l.workspace_id = (SELECT id FROM runWorkspaces WHERE task_id = ?
                        ORDER BY attempt DESC LIMIT 1))",
            )
            .bind(launch_id)
            .bind(task_id)
            .bind(terminal_handle)
            .bind(workspace_id)
            .bind(task_id)
            .fetch_one(&mut *conn)
            .await?;
            if !isolated || !current {
                bail!("an attempt dispatch requires the task's current isolated attempt");
            }
            Ok(())
        }
        DispatchTarget::Terminal { .. } => Ok(()),
    }
}

/// Writes the dispatch context, marks its task dispatched and records the
/// timeline event, all on the caller's transaction.
pub(super) async fn create_run_dispatch(
    conn: &mut SqliteConnection,
    dispatch: &NewRunDispatch<'_>,
) -> Result<()> {
    ensure_dispatch_target_allowed(conn, dispatch.task_id, &dispatch.target).await?;
    let (coordinator, policy, profile, quota) = match &dispatch.target {
        DispatchTarget::Terminal {
            coordinator_handle,
            terminal_policy,
            ..
        } => (*coordinator_handle, *terminal_policy, None, None),
        DispatchTarget::Attempt {
            profile_name,
            quota_group,
            ..
        } => ("", "keep-open", Some(*profile_name), *quota_group),
    };
    sqlx::query(
        "INSERT INTO orchestrationDispatchContexts
        (id, task_id, assignee_handle, status, failure_count, dispatched_at, run_id, workspace_id,
         coordinator_handle, context_token_hash, terminal_policy, last_activity_at, agent_profile,
         agent_quota_group)
        VALUES (?, ?, ?, 'awaiting_acceptance', ?, datetime('now'), ?, ?, ?, ?, ?, datetime('now'), ?, ?)",
    )
    .bind(dispatch.id)
    .bind(dispatch.task_id)
    .bind(dispatch.target.assignee())
    .bind(dispatch.failure_count)
    .bind(dispatch.run_id)
    .bind(dispatch.workspace_id)
    .bind(coordinator)
    .bind(dispatch.context_token_hash)
    .bind(policy)
    .bind(profile)
    .bind(quota)
    .execute(&mut *conn)
    .await?;
    sqlx::query("UPDATE orchestrationTasks SET status = 'dispatched' WHERE id = ?")
        .bind(dispatch.task_id)
        .execute(&mut *conn)
        .await?;
    if let Some(run_id) = dispatch.run_id {
        let mut event = NewRunEvent::new(run_id, RunEventKind::Dispatched);
        event.task_id = Some(dispatch.task_id);
        event.dispatch_id = Some(dispatch.id);
        event.summary = dispatch.target.assignee();
        record_run_event(conn, &event).await?;
    }
    Ok(())
}

impl super::RuntimeStore {
    /// Refuses a terminal dispatch before any side effect when the task
    /// belongs to an isolated run, whose attempts only the scheduler starts.
    pub async fn ensure_terminal_dispatch_allowed(&self, task_id: &str) -> Result<()> {
        let mut conn = self.pool().acquire().await?;
        ensure_dispatch_target_allowed(
            &mut conn,
            task_id,
            &DispatchTarget::Terminal {
                handle: "",
                coordinator_handle: "",
                terminal_policy: "",
            },
        )
        .await
    }
}
