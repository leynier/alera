use anyhow::Result;
use serde_json::{json, Value};
use sqlx::{Row, SqliteConnection};

use super::models::*;
use super::validation::*;
use crate::runtime::agent_chat_receipts::{check_receipt_in, insert_receipt_in};
use crate::runtime::agent_chat_store::require_session_row_in;
use crate::runtime::agent_chat_validation::parse_header;
use crate::runtime::{
    AgentChatReceipt, AgentChatReceiptCheck, AgentChatSessionStatus, RuntimeStore,
};

pub(super) fn original_receipt(
    operation: &AgentChatNativeOperation,
    response: Value,
) -> AgentChatReceipt {
    AgentChatReceipt {
        caller_scope: json!([operation.caller_scope, operation.verb]).to_string(),
        request_id: operation.request_id.clone(),
        digest: operation.digest.clone(),
        receipt: response,
    }
}

pub(super) fn decode(row: sqlx::sqlite::SqliteRow) -> Result<AgentChatNativeOperation> {
    Ok(AgentChatNativeOperation {
        operation_id: row.try_get("operationId")?,
        chat_id: row.try_get("chatId")?,
        generation: row.try_get("generation")?,
        base_cursor: row.try_get("baseCursor")?,
        native_thread_id: row.try_get("nativeThreadId")?,
        process_epoch: row.try_get("processEpoch")?,
        kind: row.try_get("kind")?,
        turn_id: row.try_get("turnId")?,
        actor: row.try_get("actor")?,
        boundary: serde_json::from_str(row.try_get::<&str, _>("boundaryJson")?)?,
        caller_scope: row.try_get("callerScope")?,
        verb: row.try_get("verb")?,
        request_id: row.try_get("requestId")?,
        digest: row.try_get("digest")?,
        state: row.try_get("state")?,
        revision: row.try_get("revision")?,
        ack: row
            .try_get::<Option<&str>, _>("ackJson")?
            .map(serde_json::from_str)
            .transpose()?,
        result: row
            .try_get::<Option<&str>, _>("resultJson")?
            .map(serde_json::from_str)
            .transpose()?,
    })
}

pub(super) async fn operation_in(
    connection: &mut SqliteConnection,
    chat: &str,
    id: &str,
) -> Result<AgentChatNativeOperation> {
    sqlx::query("SELECT * FROM agentChatNativeOperations WHERE chatId = ? AND operationId = ?")
        .bind(chat)
        .bind(id)
        .fetch_optional(&mut *connection)
        .await?
        .map(decode)
        .transpose()?
        .ok_or_else(|| invalid("native operation not found"))
}

pub(in crate::runtime) async fn active_operation_in(
    connection: &mut SqliteConnection,
    chat: &str,
) -> Result<Option<AgentChatNativeOperation>> {
    sqlx::query(
        "SELECT * FROM agentChatNativeOperations WHERE chatId = ? \
        AND state IN ('prepared','executing','acknowledged','uncertain')",
    )
    .bind(chat)
    .fetch_optional(&mut *connection)
    .await?
    .map(decode)
    .transpose()
}

pub(in crate::runtime) async fn require_no_native_operation_in(
    connection: &mut SqliteConnection,
    chat: &str,
) -> Result<()> {
    if active_operation_in(connection, chat).await?.is_some() {
        return Err(invalid(
            "native operation pending; reconcile it before changing this chat",
        ));
    }
    Ok(())
}

async fn idle_reason_in(connection: &mut SqliteConnection, chat: &str) -> Result<Option<String>> {
    let row = require_session_row_in(connection, chat).await?;
    let header = parse_header(&row.snapshot_json)?;
    if row.archived
        || header.session.active_turn_id.is_some()
        || !header.pending_requests.is_empty()
        || matches!(
            header.session.status,
            AgentChatSessionStatus::Starting
                | AgentChatSessionStatus::Running
                | AgentChatSessionStatus::Waiting
        )
        || ["queue", "queuedMessages"].iter().any(|key| {
            header
                .extra
                .get(*key)
                .and_then(Value::as_array)
                .is_some_and(|queue| !queue.is_empty())
        })
    {
        return Ok(Some(
            "the chat must be open and idle without queued input or requests".into(),
        ));
    }
    let busy: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM agentChatTurns WHERE chatId = ?1 AND status = 'running') \
        OR EXISTS(SELECT 1 FROM chatOrchestrationTasks WHERE (parentChatId = ?1 OR childChatId = ?1 OR rootChatId = ?1) \
        AND status IN ('preparing','running','needs_input','cancel_requested'))")
        .bind(chat).fetch_one(&mut *connection).await?;
    Ok(busy.then(|| "the chat has active turns or task linkage".into()))
}

async fn require_exact_boundary_in(
    connection: &mut SqliteConnection,
    input: &AgentChatNativeOperationInput,
) -> Result<()> {
    let prefix = if input.kind == AGENT_CHAT_NATIVE_REWIND {
        "turn"
    } else {
        "userTurn"
    };
    let native = crate::runtime::agent_chat_identity::native_id_for_app_in(
        connection,
        &input.chat_id,
        input.expected_generation,
        &format!("{prefix}@{}", input.process_epoch),
        &input.turn_id,
    )
    .await?
    .ok_or_else(|| invalid("no native boundary in the exact process epoch"))?
    .native_id;
    let expected = if input.kind == AGENT_CHAT_NATIVE_REWIND {
        &input.boundary["value"]
    } else {
        &input.boundary["id"]
    };
    if !native.is_string() || &native != expected {
        return Err(invalid(
            "native operation boundary does not match the exact process epoch",
        ));
    }
    // Conversation prompt ambiguity must be refused before any provider I/O.
    super::prefix::target_in(connection, &input.chat_id, &input.turn_id).await?;
    if input.kind == AGENT_CHAT_NATIVE_REWIND {
        super::prefix::prompt_in(connection, &input.chat_id, &input.turn_id).await?;
    }
    Ok(())
}

impl RuntimeStore {
    pub async fn begin_agent_chat_native_operation(
        &self,
        input: &AgentChatNativeOperationInput,
        receipt: &AgentChatNativeOperationReceipt,
    ) -> Result<AgentChatNativeOperationOutcome> {
        require_input(input, receipt)?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let scope = json!([receipt.caller_scope, receipt.verb]).to_string();
        match check_receipt_in(&mut tx, &scope, &receipt.request_id, &receipt.digest).await? {
            AgentChatReceiptCheck::Replay(value) => {
                tx.commit().await?;
                return Ok(AgentChatNativeOperationOutcome::Replay(value));
            }
            AgentChatReceiptCheck::Conflict => {
                tx.commit().await?;
                return Ok(AgentChatNativeOperationOutcome::ReceiptConflict);
            }
            AgentChatReceiptCheck::New => {}
        }
        let existing = sqlx::query(
            "SELECT * FROM agentChatNativeOperations WHERE operationId = ? \
            OR (callerScope = ? AND verb = ? AND requestId = ?)",
        )
        .bind(&input.operation_id)
        .bind(&receipt.caller_scope)
        .bind(&receipt.verb)
        .bind(&receipt.request_id)
        .fetch_all(&mut *tx)
        .await?;
        if !existing.is_empty() {
            if existing.len() != 1 {
                return Ok(AgentChatNativeOperationOutcome::ReceiptConflict);
            }
            let operation = decode(existing.into_iter().next().unwrap())?;
            if operation.chat_id != input.chat_id
                || operation.caller_scope != receipt.caller_scope
                || operation.verb != receipt.verb
                || operation.request_id != receipt.request_id
                || operation.digest != receipt.digest
            {
                return Ok(AgentChatNativeOperationOutcome::ReceiptConflict);
            }
            tx.commit().await?;
            return Ok(if let Some(response) = operation.result.clone() {
                AgentChatNativeOperationOutcome::Replay(response)
            } else {
                AgentChatNativeOperationOutcome::Existing(Box::new(operation))
            });
        }
        let row = require_session_row_in(&mut tx, &input.chat_id).await?;
        if row.cursor != input.expected_cursor {
            tx.commit().await?;
            return Ok(AgentChatNativeOperationOutcome::CursorConflict {
                current: row.cursor,
            });
        }
        let reason = if active_operation_in(&mut tx, &input.chat_id)
            .await?
            .is_some()
        {
            Some("another native operation is pending".into())
        } else if row.generation != input.expected_generation
            || row.native_thread_id.as_deref() != Some(input.expected_native_thread_id.as_str())
        {
            Some("the native provider context changed".into())
        } else {
            idle_reason_in(&mut tx, &input.chat_id).await?
        };
        if let Some(reason) = reason {
            tx.commit().await?;
            return Ok(AgentChatNativeOperationOutcome::Busy { reason });
        }
        require_exact_boundary_in(&mut tx, input).await?;
        sqlx::query("INSERT INTO agentChatNativeOperations \
            (operationId,chatId,generation,baseCursor,nativeThreadId,processEpoch,kind,turnId,boundaryJson,actor,callerScope,verb,requestId,digest,state,revision) \
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,'prepared',1)")
            .bind(&input.operation_id).bind(&input.chat_id).bind(input.expected_generation).bind(input.expected_cursor)
            .bind(&input.expected_native_thread_id).bind(&input.process_epoch).bind(&input.kind).bind(&input.turn_id)
            .bind(bounded(&input.boundary)?).bind(&input.actor).bind(&receipt.caller_scope).bind(&receipt.verb)
            .bind(&receipt.request_id).bind(&receipt.digest).execute(&mut *tx).await?;
        let operation = operation_in(&mut tx, &input.chat_id, &input.operation_id).await?;
        tx.commit().await?;
        Ok(AgentChatNativeOperationOutcome::Applied(Box::new(
            operation,
        )))
    }

    pub async fn pending_agent_chat_native_operation(
        &self,
        chat_id: &str,
    ) -> Result<Option<AgentChatNativeOperation>> {
        let mut connection = self.pool().acquire().await?;
        active_operation_in(&mut connection, chat_id).await
    }

    pub async fn agent_chat_native_operation(
        &self,
        chat_id: &str,
        operation_id: &str,
    ) -> Result<Option<AgentChatNativeOperation>> {
        sqlx::query("SELECT * FROM agentChatNativeOperations WHERE chatId = ? AND operationId = ?")
            .bind(chat_id)
            .bind(operation_id)
            .fetch_optional(self.pool())
            .await?
            .map(decode)
            .transpose()
    }

    /// The CAS winner alone may proceed to provider I/O after executing.
    pub async fn transition_agent_chat_native_operation(
        &self,
        chat_id: &str,
        operation_id: &str,
        expected_revision: i64,
        new_state: &str,
        evidence: Option<&Value>,
    ) -> Result<AgentChatNativeOperationOutcome> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let operation = operation_in(&mut tx, chat_id, operation_id).await?;
        require_kind(&operation.kind)?;
        if operation.revision != expected_revision {
            tx.commit().await?;
            return Ok(AgentChatNativeOperationOutcome::RevisionConflict {
                current: operation.revision,
            });
        }
        if !matches!(
            (operation.state.as_str(), new_state),
            ("prepared", "executing" | "cancelled") | ("executing", "acknowledged" | "uncertain")
        ) {
            return Err(invalid("illegal native operation transition; uncertain operations require explicit reconciliation"));
        }
        require_transition_evidence(&operation, new_state, evidence)?;
        if new_state == "executing" {
            let row = require_session_row_in(&mut tx, chat_id).await?;
            if row.cursor != operation.base_cursor {
                return Ok(AgentChatNativeOperationOutcome::CursorConflict {
                    current: row.cursor,
                });
            }
            if row.generation != operation.generation
                || row.native_thread_id.as_deref() != Some(operation.native_thread_id.as_str())
            {
                return Ok(AgentChatNativeOperationOutcome::Busy {
                    reason: "the native provider context changed".into(),
                });
            }
            if let Some(reason) = idle_reason_in(&mut tx, chat_id).await? {
                return Ok(AgentChatNativeOperationOutcome::Busy { reason });
            }
        }
        let revision = operation
            .revision
            .checked_add(1)
            .ok_or_else(|| invalid("native operation revision exhausted"))?;
        let ack = (new_state == "acknowledged").then(|| evidence.unwrap().to_string());
        let result = (new_state == "cancelled").then(|| json!({
            "operationId": operation_id, "chatId": chat_id, "state": "cancelled", "operationKind": operation.kind,
            "nativeRollback": false, "filesystemRewindAcknowledged": false, "filesystemChangesReverted": null,
        }));
        let updated = sqlx::query("UPDATE agentChatNativeOperations SET state = ?, revision = ?, ackJson = ?, resultJson = ?, evidenceJson = ? WHERE operationId = ? AND revision = ?")
            .bind(new_state).bind(revision).bind(ack).bind(result.as_ref().map(Value::to_string)).bind(evidence.map(Value::to_string)).bind(operation_id)
            .bind(expected_revision).execute(&mut *tx).await?;
        if updated.rows_affected() != 1 {
            return Err(invalid("native transition was not persisted"));
        }
        if let Some(result) = result {
            let receipt = original_receipt(&operation, result);
            insert_receipt_in(&mut tx, None, None, &receipt).await?;
        }
        let updated = operation_in(&mut tx, chat_id, operation_id).await?;
        tx.commit().await?;
        Ok(AgentChatNativeOperationOutcome::Applied(Box::new(updated)))
    }

    /// Run once at host startup. An executing RPC has an unknown outcome;
    /// neither migration nor recovery issues a second provider request.
    pub async fn recover_agent_chat_native_operations(&self) -> Result<u64> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let exhausted: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM agentChatNativeOperations WHERE state = 'executing' AND kind IN ('rewind','rewindFiles') AND revision = ?)")
            .bind(i64::MAX).fetch_one(&mut *tx).await?;
        if exhausted {
            return Err(invalid("native operation revision exhausted"));
        }
        let changed = sqlx::query("UPDATE agentChatNativeOperations SET state = 'uncertain', revision = revision + 1, evidenceJson = '{\"reason\":\"runtimeRestarted\"}' WHERE state = 'executing' AND kind IN ('rewind','rewindFiles')")
            .execute(&mut *tx).await?.rows_affected();
        tx.commit().await?;
        Ok(changed)
    }

    pub async fn list_pending_agent_chat_native_operations(
        &self,
        after_operation_id: Option<&str>,
        limit: i64,
    ) -> Result<AgentChatNativeOperationPage> {
        let limit = limit.clamp(1, AGENT_CHAT_NATIVE_OPERATION_PAGE_LIMIT);
        let mut rows = sqlx::query("SELECT * FROM agentChatNativeOperations WHERE state IN ('prepared','executing','acknowledged','uncertain') \
            AND (? IS NULL OR operationId > ?) ORDER BY operationId LIMIT ?")
            .bind(after_operation_id).bind(after_operation_id).bind(limit + 1).fetch_all(self.pool()).await?;
        let has_more = rows.len() > limit as usize;
        if has_more {
            rows.pop();
        }
        let operations = rows.into_iter().map(decode).collect::<Result<Vec<_>>>()?;
        let next_after = has_more.then(|| operations.last().unwrap().operation_id.clone());
        Ok(AgentChatNativeOperationPage {
            operations,
            next_after,
        })
    }
}
