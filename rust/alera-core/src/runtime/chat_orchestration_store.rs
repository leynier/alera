//! Task rows: creation with an atomic receipt, reads, and conditional status
//! changes. Every mutation commits before it returns, so a caller broadcasts
//! `chatOrchestrationChanged` only for state that is already durable.

use anyhow::Result;
use chrono::Utc;
use sqlx::SqliteConnection;

use super::chat_orchestration_delivery::*;
use super::chat_orchestration_models::*;
use super::chat_orchestration_receipts::{
    check_receipt_in, insert_receipt_in, prune_receipts_in, require_receipt,
};
use super::chat_orchestration_rows::*;
use super::chat_orchestration_wakes::enqueue_wake_in;
use super::{format_timestamp, RuntimeStore};

pub fn new_chat_orchestration_task_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

fn validate_new_task(task: &NewChatOrchestrationTask) -> Result<()> {
    require_id("taskId", &task.task_id)?;
    require_id("callerScope", &task.caller_scope)?;
    require_optional_id("parentTaskId", task.parent_task_id.as_deref())?;
    require_optional_id("parentChatId", task.parent_chat_id.as_deref())?;
    require_optional_id("childChatId", task.child_chat_id.as_deref())?;
    require_optional_id("projectId", task.project_id.as_deref())?;
    require_optional_id("workspaceId", task.workspace_id.as_deref())?;
    require_optional_id("hostId", task.host_id.as_deref())?;
    match &task.target {
        ChatOrchestrationTarget::Chat { chat_id } => require_id("target.chatId", chat_id)?,
        ChatOrchestrationTarget::Workspace { workspace_id } => {
            require_id("target.workspaceId", workspace_id)?
        }
        ChatOrchestrationTarget::NewWorkspace(spec) => {
            require_id("target.projectId", &spec.project_id)?;
            require_id("target.hostId", &spec.host_id)?;
            require_optional_id(
                "target.parentWorkspaceId",
                spec.parent_workspace_id.as_deref(),
            )?;
        }
    }
    if task.brief.trim().is_empty() {
        return Err(invalid("task brief must not be empty"));
    }
    require_bounded("task", &task.brief, CHAT_ORCHESTRATION_BRIEF_MAX_BYTES)?;
    for (label, value) in [("title", &task.title), ("role", &task.role)] {
        if let Some(value) = value {
            require_bounded(label, value, CHAT_ORCHESTRATION_LABEL_MAX_BYTES)?;
        }
    }
    if let Some(options) = &task.launch_options {
        if !options.is_object() {
            return Err(invalid("launch options must be an object"));
        }
        require_bounded(
            "launch options",
            &options.to_string(),
            CHAT_ORCHESTRATION_OPTIONS_MAX_BYTES,
        )?;
    }
    Ok(())
}

async fn insert_task_in(
    connection: &mut SqliteConnection,
    task: &NewChatOrchestrationTask,
) -> Result<ChatOrchestrationTask> {
    if super::chat_orchestration_rows::task_in(connection, &task.task_id)
        .await?
        .is_some()
    {
        return Err(conflict(format!("task {} already exists", task.task_id)));
    }
    let (root_task_id, root_chat_id, depth) = match &task.parent_task_id {
        Some(parent_id) => {
            let parent = require_task_in(connection, parent_id).await?;
            let root_chat_id = parent.root_chat_id.or(parent.parent_chat_id);
            (parent.root_task_id, root_chat_id, parent.depth + 1)
        }
        None => (task.task_id.clone(), task.parent_chat_id.clone(), 0),
    };
    let now = format_timestamp(Utc::now());
    sqlx::query(
        "INSERT INTO chatOrchestrationTasks (taskId, kind, status, revision, callerScope, \
         parentTaskId, rootTaskId, depth, parentChatId, rootChatId, childChatId, projectId, \
         workspaceId, hostId, targetJson, title, role, brief, notify, launchOptionsJson, \
         resultDelivery, createdAt, updatedAt) VALUES (?, ?, 'preparing', 1, ?, ?, ?, ?, ?, ?, \
         ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)",
    )
    .bind(&task.task_id)
    .bind(task.kind.as_str())
    .bind(&task.caller_scope)
    .bind(&task.parent_task_id)
    .bind(&root_task_id)
    .bind(depth)
    .bind(&task.parent_chat_id)
    .bind(&root_chat_id)
    .bind(&task.child_chat_id)
    .bind(&task.project_id)
    .bind(&task.workspace_id)
    .bind(&task.host_id)
    .bind(serde_json::to_string(&task.target)?)
    .bind(&task.title)
    .bind(&task.role)
    .bind(&task.brief)
    .bind(task.notify.as_str())
    .bind(task.launch_options.as_ref().map(|value| value.to_string()))
    .bind(&now)
    .bind(&now)
    .execute(&mut *connection)
    .await?;
    require_task_in(connection, &task.task_id).await
}

/// Applies `transition` inside the caller's transaction. The conditional
/// UPDATE runs first, so it also takes the write lock before any read.
pub(super) async fn transition_in(
    connection: &mut SqliteConnection,
    task_id: &str,
    transition: &ChatOrchestrationTaskTransition,
) -> Result<ChatOrchestrationTransitionOutcome> {
    let allowed: Vec<&'static str> = transition
        .to
        .legal_predecessors()
        .iter()
        .filter(|status| transition.from.contains(status))
        .map(|status| status.as_str())
        .collect();
    let (result_text, result_truncated) = match &transition.result_text {
        Some(text) => {
            let (text, truncated) = truncate_utf8(text, CHAT_ORCHESTRATION_RESULT_MAX_BYTES);
            (Some(text), truncated)
        }
        None => (None, false),
    };
    let error = transition
        .error
        .as_deref()
        .map(|error| truncate_utf8(error, CHAT_ORCHESTRATION_ERROR_MAX_BYTES).0);
    let now = format_timestamp(Utc::now());
    let to = transition.to;
    let applied = if allowed.is_empty() {
        0
    } else {
        let placeholders = vec!["?"; allowed.len()].join(", ");
        let mut query = sqlx::query(sqlx::AssertSqlSafe(format!(
            "UPDATE chatOrchestrationTasks SET status = ?, revision = revision + 1, \
             childChatId = COALESCE(?, childChatId), childTurnId = COALESCE(?, childTurnId), \
             projectId = COALESCE(?, projectId), workspaceId = COALESCE(?, workspaceId), \
             hostId = COALESCE(?, hostId), errorCode = COALESCE(?, errorCode), \
             resultText = COALESCE(?, resultText), \
             resultTruncated = CASE WHEN ? IS NULL THEN resultTruncated ELSE ? END, \
             error = COALESCE(?, error), updatedAt = ?, \
             cancelRequestedAt = CASE WHEN ? THEN ? ELSE cancelRequestedAt END, \
             settledAt = CASE WHEN ? THEN ? ELSE settledAt END \
             WHERE taskId = ? AND status IN ({placeholders}) \
             AND (? IS NULL OR revision = ?)"
        )))
        .bind(to.as_str())
        .bind(&transition.child_chat_id)
        .bind(&transition.child_turn_id)
        .bind(&transition.project_id)
        .bind(&transition.workspace_id)
        .bind(&transition.host_id)
        .bind(&transition.error_code)
        .bind(&result_text)
        .bind(&result_text)
        .bind(result_truncated)
        .bind(&error)
        .bind(&now)
        .bind(to == ChatOrchestrationTaskStatus::CancelRequested)
        .bind(&now)
        .bind(to.is_terminal())
        .bind(&now)
        .bind(task_id);
        for status in &allowed {
            query = query.bind(*status);
        }
        query
            .bind(transition.expected_revision)
            .bind(transition.expected_revision)
            .execute(&mut *connection)
            .await?
            .rows_affected()
    };
    let task = require_task_in(connection, task_id).await?;
    if applied == 0 {
        return Ok(ChatOrchestrationTransitionOutcome::Rejected { current: task });
    }
    let wake = enqueue_wake_in(connection, &task).await?;
    Ok(ChatOrchestrationTransitionOutcome::Applied { task, wake })
}

fn validate_transition(task_id: &str, transition: &ChatOrchestrationTaskTransition) -> Result<()> {
    require_id("taskId", task_id)?;
    if transition.from.is_empty() {
        return Err(invalid(
            "a transition must name the statuses it applies from",
        ));
    }
    if transition.to == ChatOrchestrationTaskStatus::Preparing {
        return Err(invalid("a task cannot return to preparing"));
    }
    if transition.to == ChatOrchestrationTaskStatus::CancelRequested {
        return Err(invalid("use request_chat_orchestration_cancel to cancel"));
    }
    require_optional_id("childChatId", transition.child_chat_id.as_deref())?;
    require_optional_id("childTurnId", transition.child_turn_id.as_deref())?;
    require_optional_id("projectId", transition.project_id.as_deref())?;
    require_optional_id("workspaceId", transition.workspace_id.as_deref())?;
    require_optional_id("hostId", transition.host_id.as_deref())?;
    require_optional_id("errorCode", transition.error_code.as_deref())
}

impl RuntimeStore {
    /// Creates a `preparing` task. With a receipt, the receipt commits in the
    /// same transaction: an identical retry replays its response and a
    /// different payload under the same request id conflicts, without a
    /// second task either way.
    pub async fn create_chat_orchestration_task(
        &self,
        task: NewChatOrchestrationTask,
        receipt: Option<&ChatOrchestrationReceipt>,
    ) -> Result<ChatOrchestrationCreateOutcome> {
        validate_new_task(&task)?;
        if let Some(receipt) = receipt {
            require_receipt(receipt)?;
        }
        let mut tx = self.pool().begin().await?;
        prune_receipts_in(&mut tx).await?;
        if let Some(receipt) = receipt {
            match check_receipt_in(
                &mut tx,
                &receipt.scope,
                &receipt.verb,
                &receipt.request_id,
                &receipt.digest,
            )
            .await?
            {
                ChatOrchestrationReceiptCheck::New => {}
                ChatOrchestrationReceiptCheck::Replay(response) => {
                    tx.commit().await?;
                    return Ok(ChatOrchestrationCreateOutcome::Replay(response));
                }
                ChatOrchestrationReceiptCheck::Conflict => {
                    tx.commit().await?;
                    return Ok(ChatOrchestrationCreateOutcome::Conflict);
                }
            }
        }
        let created = insert_task_in(&mut tx, &task).await?;
        if let Some(receipt) = receipt {
            insert_receipt_in(&mut tx, Some(&created.task_id), receipt).await?;
        }
        tx.commit().await?;
        Ok(ChatOrchestrationCreateOutcome::Created(Box::new(created)))
    }

    pub async fn chat_orchestration_task(
        &self,
        task_id: &str,
    ) -> Result<Option<ChatOrchestrationTask>> {
        let mut connection = self.pool().acquire().await?;
        super::chat_orchestration_rows::task_in(&mut connection, task_id).await
    }

    /// Newest first.
    pub async fn list_chat_orchestration_tasks(
        &self,
        filter: &ChatOrchestrationTaskFilter,
    ) -> Result<ChatOrchestrationTaskPage> {
        let limit = filter
            .limit
            .unwrap_or(CHAT_ORCHESTRATION_LIST_MAX_LIMIT)
            .clamp(1, CHAT_ORCHESTRATION_LIST_MAX_LIMIT);
        let mut clauses = Vec::new();
        let mut binds: Vec<String> = Vec::new();
        for (column, value) in [
            ("parentChatId", &filter.parent_chat_id),
            ("rootChatId", &filter.root_chat_id),
            ("childChatId", &filter.child_chat_id),
            ("projectId", &filter.project_id),
            ("workspaceId", &filter.workspace_id),
            ("hostId", &filter.host_id),
            ("parentTaskId", &filter.parent_task_id),
            ("rootTaskId", &filter.root_task_id),
            ("callerScope", &filter.caller_scope),
        ] {
            if let Some(value) = value {
                clauses.push(format!("{column} = ?"));
                binds.push(value.clone());
            }
        }
        if !filter.statuses.is_empty() {
            clauses.push(format!(
                "status IN ({})",
                vec!["?"; filter.statuses.len()].join(", ")
            ));
            binds.extend(
                filter
                    .statuses
                    .iter()
                    .map(|status| status.as_str().to_string()),
            );
        }
        if let Some(attention) = filter.attention {
            let needs = "(status = 'needs_input' OR (status = 'failed' \
                AND resultDelivery != 'acknowledged'))";
            clauses.push(if attention {
                needs.to_string()
            } else {
                format!("NOT {needs}")
            });
        }
        clauses.push("(? IS NULL OR sequence < ?)".into());
        let sql = format!(
            "SELECT {TASK_COLUMNS} FROM chatOrchestrationTasks WHERE {} \
             ORDER BY sequence DESC LIMIT ?",
            clauses.join(" AND ")
        );
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        for value in &binds {
            query = query.bind(value.as_str());
        }
        let query = query
            .bind(filter.before_sequence)
            .bind(filter.before_sequence);
        let rows = query.bind(limit + 1).fetch_all(self.pool()).await?;
        let mut tasks = rows.iter().map(task_from_row).collect::<Result<Vec<_>>>()?;
        let next_before_sequence = if tasks.len() as i64 > limit {
            tasks.truncate(limit as usize);
            tasks.last().map(|task| task.sequence)
        } else {
            None
        };
        Ok(ChatOrchestrationTaskPage {
            tasks,
            next_before_sequence,
        })
    }

    /// The unsettled task a child chat is working on, newest first: what a
    /// bound agent's own delegations hang under as `parentTaskId`.
    pub async fn active_chat_orchestration_task_for_child(
        &self,
        child_chat_id: &str,
    ) -> Result<Option<ChatOrchestrationTask>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {TASK_COLUMNS} FROM chatOrchestrationTasks WHERE childChatId = ? \
             AND status IN ('preparing', 'running', 'needs_input', 'cancel_requested') \
             ORDER BY sequence DESC LIMIT 1"
        )))
        .bind(child_chat_id)
        .fetch_optional(self.pool())
        .await?;
        row.as_ref().map(task_from_row).transpose()
    }

    /// Conditional status change committed before it returns. A settled or
    /// `needs_input` move joins the parent's open wake cohort in the same
    /// transaction when the task's `notify` asks for it.
    pub async fn transition_chat_orchestration_task(
        &self,
        task_id: &str,
        transition: &ChatOrchestrationTaskTransition,
    ) -> Result<ChatOrchestrationTransitionOutcome> {
        validate_transition(task_id, transition)?;
        let mut tx = self.pool().begin().await?;
        let outcome = transition_in(&mut tx, task_id, transition).await?;
        tx.commit().await?;
        Ok(outcome)
    }

    /// Marks a settled result as read by the parent (`task` with `ack`, or a
    /// bounded wait that returned it) and withdraws it from any wake cohort
    /// not yet sealed, so the parent is not woken for what it already has.
    pub async fn acknowledge_chat_orchestration_result(
        &self,
        task_id: &str,
    ) -> Result<ChatOrchestrationTask> {
        require_id("taskId", task_id)?;
        let mut tx = self.pool().begin().await?;
        let now = format_timestamp(Utc::now());
        let updated = sqlx::query(
            "UPDATE chatOrchestrationTasks SET resultDelivery = 'acknowledged', updatedAt = ? \
             WHERE taskId = ? AND status IN ('completed', 'failed', 'interrupted', 'cancelled') \
             AND resultDelivery != 'acknowledged'",
        )
        .bind(&now)
        .bind(task_id)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        let task = require_task_in(&mut tx, task_id).await?;
        if updated == 0 && !task.status.is_terminal() {
            return Err(conflict(format!("task {task_id} has not settled")));
        }
        super::chat_orchestration_wakes::withdraw_pending_in(&mut tx, task_id).await?;
        tx.commit().await?;
        Ok(task)
    }
}
