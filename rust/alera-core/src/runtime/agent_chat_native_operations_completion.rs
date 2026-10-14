//! Finalization uses persisted acknowledgment only, never provider I/O.

use anyhow::Result;
use serde_json::{json, Value};
use sqlx::SqliteConnection;

use super::models::*;
use super::prefix::{require_rewind_header, reset_context_in, rewind_in};
use super::store::{operation_in, original_receipt};
use super::validation::*;
use super::view::agent_chat_native_operation_public_summary;
use crate::runtime::agent_chat_receipts::{check_receipt_in, insert_receipt_in, require_receipt};
use crate::runtime::agent_chat_store::require_session_row_in;
use crate::runtime::agent_chat_validation::{parse_header, parse_snapshot};
use crate::runtime::{
    AgentChatReceipt, AgentChatReceiptCheck, AgentChatSessionStatus, RuntimeStore,
};

async fn receipt_outcome_in(
    connection: &mut SqliteConnection,
    receipt: Option<&AgentChatReceipt>,
) -> Result<Option<AgentChatNativeOperationCompleteOutcome>> {
    let Some(receipt) = receipt else {
        return Ok(None);
    };
    require_receipt(receipt)?;
    Ok(
        match check_receipt_in(
            connection,
            &receipt.caller_scope,
            &receipt.request_id,
            &receipt.digest,
        )
        .await?
        {
            AgentChatReceiptCheck::New => None,
            AgentChatReceiptCheck::Replay(value) => {
                Some(AgentChatNativeOperationCompleteOutcome::Replay(value))
            }
            AgentChatReceiptCheck::Conflict => {
                Some(AgentChatNativeOperationCompleteOutcome::ReceiptConflict)
            }
        },
    )
}

async fn save_response_in(
    connection: &mut SqliteConnection,
    receipt: &AgentChatReceipt,
    cursor: i64,
) -> Result<()> {
    // A provider effect is never retried to repair a local persistence failure.
    let json = serde_json::to_string(&receipt.receipt)?;
    if json.len() > 1024 * 1024 {
        return Err(invalid(
            "native completion response exceeds the byte budget",
        ));
    }
    crate::runtime::agent_chat_secrets::reject_secret_fields(
        "native completion response",
        &receipt.receipt,
    )?;
    match check_receipt_in(
        connection,
        &receipt.caller_scope,
        &receipt.request_id,
        &receipt.digest,
    )
    .await?
    {
        AgentChatReceiptCheck::New => {
            insert_receipt_in(connection, None, Some(cursor), receipt).await?
        }
        AgentChatReceiptCheck::Conflict => {
            return Err(invalid("native completion receipt conflicted"))
        }
        AgentChatReceiptCheck::Replay(value) if value == receipt.receipt => {}
        AgentChatReceiptCheck::Replay(_) => {
            return Err(invalid(
                "native completion receipt already has another response",
            ))
        }
    }
    Ok(())
}

async fn save_completion_in(
    connection: &mut SqliteConnection,
    operation: &AgentChatNativeOperation,
    response: &Value,
    reconcile_receipt: Option<&AgentChatReceipt>,
    cursor: i64,
) -> Result<()> {
    let original = original_receipt(operation, response.clone());
    save_response_in(connection, &original, cursor).await?;
    sqlx::query("UPDATE agentChatNativeOperations SET resultJson = ? WHERE operationId = ?")
        .bind(serde_json::to_string(response)?)
        .bind(&operation.operation_id)
        .execute(&mut *connection)
        .await?;
    if let Some(receipt) = reconcile_receipt {
        let terminal =
            operation_in(connection, &operation.chat_id, &operation.operation_id).await?;
        let saved = AgentChatReceipt {
            receipt: json!({
                "snapshot": response["snapshot"], "operation": agent_chat_native_operation_public_summary(&terminal), "result": response,
            }),
            ..receipt.clone()
        };
        save_response_in(connection, &saved, cursor).await?;
    }
    Ok(())
}

async fn terminal_replay_in(
    connection: &mut SqliteConnection,
    operation: &AgentChatNativeOperation,
    receipt: Option<&AgentChatReceipt>,
) -> Result<Option<AgentChatNativeOperationCompleteOutcome>> {
    let Some(result) = operation
        .result
        .as_ref()
        .filter(|_| matches!(operation.state.as_str(), "completed" | "reconciled"))
    else {
        return Ok(None);
    };
    if let Some(receipt) = receipt {
        let saved = AgentChatReceipt {
            receipt: json!({"snapshot": result["snapshot"],
            "operation": agent_chat_native_operation_public_summary(operation), "result": result}),
            ..receipt.clone()
        };
        save_response_in(
            connection,
            &saved,
            result["snapshot"]["cursor"]
                .as_i64()
                .unwrap_or(operation.base_cursor),
        )
        .await?;
        return Ok(Some(AgentChatNativeOperationCompleteOutcome::Replay(
            saved.receipt,
        )));
    }
    Ok(Some(AgentChatNativeOperationCompleteOutcome::Replay(
        result.clone(),
    )))
}

fn require_completion_state(
    operation: &AgentChatNativeOperation,
    fallback: bool,
    receipt: Option<&AgentChatReceipt>,
) -> Result<bool> {
    match operation.state.as_str() {
        "acknowledged" if !fallback => {
            require_ack(
                operation,
                operation
                    .ack
                    .as_ref()
                    .ok_or_else(|| invalid("native acknowledgment is missing"))?,
            )?;
            Ok(true)
        }
        "uncertain" if fallback && receipt.is_some() => Ok(false),
        _ => Err(invalid(
            "native completion needs persisted acknowledgment or explicit human reconciliation",
        )),
    }
}

async fn terminalize_in(
    connection: &mut SqliteConnection,
    operation: &AgentChatNativeOperation,
    acknowledged: bool,
) -> Result<()> {
    let revision = operation
        .revision
        .checked_add(1)
        .ok_or_else(|| invalid("native operation revision exhausted"))?;
    // Visible only with the transcript/receipt commit; rollback restores the
    // active state, so generic archive/delete guards stay correct on failure.
    let updated = sqlx::query("UPDATE agentChatNativeOperations SET state = ?, revision = ? WHERE operationId = ? AND revision = ?")
        .bind(if acknowledged {"completed"} else {"reconciled"}).bind(revision).bind(&operation.operation_id)
        .bind(operation.revision).execute(&mut *connection).await?;
    if updated.rows_affected() != 1 {
        return Err(invalid("native operation finalization lost its revision"));
    }
    Ok(())
}

impl RuntimeStore {
    pub async fn complete_agent_chat_native_rewind(
        &self,
        chat_id: &str,
        operation_id: &str,
        expected_revision: i64,
        expected_cursor: i64,
        snapshot: &Value,
        reconcile_receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatNativeOperationCompleteOutcome> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        if let Some(outcome) = receipt_outcome_in(&mut tx, reconcile_receipt).await? {
            tx.commit().await?;
            return Ok(outcome);
        }
        let operation = operation_in(&mut tx, chat_id, operation_id).await?;
        require_kind(&operation.kind)?;
        if let Some(outcome) = terminal_replay_in(&mut tx, &operation, reconcile_receipt).await? {
            tx.commit().await?;
            return Ok(outcome);
        }
        if operation.revision != expected_revision {
            return Ok(AgentChatNativeOperationCompleteOutcome::RevisionConflict {
                current: operation.revision,
            });
        }
        if operation.kind != AGENT_CHAT_NATIVE_REWIND {
            return Err(invalid("native operation is not a conversation rewind"));
        }
        let action = snapshot.get("nativeOperationReconcile");
        let fallback = action.is_some();
        if action.is_some_and(|value| value != &json!({"action":"continueFromTranscript"})) {
            return Err(invalid(
                "unsupported native conversation reconciliation action",
            ));
        }
        let acknowledged = require_completion_state(&operation, fallback, reconcile_receipt)?;
        let snapshot = parse_snapshot(snapshot)?;
        require_rewind_header(&snapshot)?;
        let row = require_session_row_in(&mut tx, chat_id).await?;
        if row.cursor != expected_cursor || row.cursor < operation.base_cursor {
            return Ok(AgentChatNativeOperationCompleteOutcome::CursorConflict {
                current: row.cursor,
            });
        }
        if row.generation != operation.generation
            || row.native_thread_id.as_deref() != Some(operation.native_thread_id.as_str())
        {
            return Err(invalid("native provider context changed during completion"));
        }
        terminalize_in(&mut tx, &operation, acknowledged).await?;
        let native = acknowledged.then(|| {
            operation.ack.as_ref().unwrap()["nativeThreadId"]
                .as_str()
                .unwrap()
        });
        let (record, event, prompt) =
            rewind_in(&mut tx, &row, &operation.turn_id, snapshot, native).await?;
        let response = json!({"chatId":chat_id,"operationId":operation_id,"snapshot":record.snapshot,"event":event,
            "prompt":prompt.get("text").and_then(Value::as_str).unwrap_or(""),
            "attachments":prompt.get("attachments").cloned().unwrap_or(json!([])),"promptItem":prompt,
            "operationKind":if acknowledged {"nativeRewind"} else {"transcriptRewind"},
            "nativeRollback":acknowledged,"filesystemChangesReverted":false,
            "state":if acknowledged {"completed"} else {"reconciled"}});
        save_completion_in(
            &mut tx,
            &operation,
            &response,
            reconcile_receipt,
            event.cursor,
        )
        .await?;
        tx.commit().await?;
        Ok(AgentChatNativeOperationCompleteOutcome::Committed {
            record: Box::new(record),
            event,
            response,
        })
    }

    pub async fn complete_agent_chat_native_files(
        &self,
        chat_id: &str,
        operation_id: &str,
        expected_revision: i64,
        expected_cursor: i64,
        observations: &Value,
        reconcile_receipt: Option<&AgentChatReceipt>,
    ) -> Result<AgentChatNativeOperationCompleteOutcome> {
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        if let Some(outcome) = receipt_outcome_in(&mut tx, reconcile_receipt).await? {
            tx.commit().await?;
            return Ok(outcome);
        }
        let operation = operation_in(&mut tx, chat_id, operation_id).await?;
        require_kind(&operation.kind)?;
        if let Some(outcome) = terminal_replay_in(&mut tx, &operation, reconcile_receipt).await? {
            tx.commit().await?;
            return Ok(outcome);
        }
        if operation.revision != expected_revision {
            return Ok(AgentChatNativeOperationCompleteOutcome::RevisionConflict {
                current: operation.revision,
            });
        }
        if operation.kind != AGENT_CHAT_NATIVE_REWIND_FILES {
            return Err(invalid("native operation is not a filesystem rewind"));
        }
        let fallback = observations.get("action").is_some();
        if fallback && observations != &json!({"action":"continueFromCurrentFiles"}) {
            return Err(invalid(
                "unsupported native filesystem reconciliation action",
            ));
        }
        let acknowledged = require_completion_state(&operation, fallback, reconcile_receipt)?;
        let effects = if acknowledged {
            require_observations(observations)?
        } else {
            None
        };
        let row = require_session_row_in(&mut tx, chat_id).await?;
        if row.cursor != expected_cursor || row.cursor < operation.base_cursor {
            return Ok(AgentChatNativeOperationCompleteOutcome::CursorConflict {
                current: row.cursor,
            });
        }
        if row.generation != operation.generation
            || row.native_thread_id.as_deref() != Some(operation.native_thread_id.as_str())
        {
            return Err(invalid("native provider context changed during completion"));
        }
        let mut snapshot = parse_header(&row.snapshot_json)?;
        snapshot.items.clear();
        snapshot.turns.clear();
        snapshot.cursor = row
            .cursor
            .checked_add(1)
            .ok_or_else(|| invalid("chat cursor exhausted"))?;
        snapshot.session.status = AgentChatSessionStatus::Stopped;
        snapshot.session.active_turn_id = None;
        snapshot.session.extra.remove("errorMessage");
        snapshot.session.extra.remove("historyOperation");
        snapshot.usage = None;
        snapshot.recovery = None;
        terminalize_in(&mut tx, &operation, acknowledged).await?;
        let native = acknowledged.then(|| {
            operation.ack.as_ref().unwrap()["nativeThreadId"]
                .as_str()
                .unwrap()
        });
        let (record, event) =
            reset_context_in(&mut tx, &row, snapshot, native, "nativeFilesRewind").await?;
        let response = json!({"chatId":chat_id,"operationId":operation_id,"snapshot":record.snapshot,"event":event,
            "operationKind":"nativeFilesRewind","filesystemRewindAcknowledged":acknowledged,
            "filesystemChangesReverted":effects,"nativeRollback":false,
            "state":if acknowledged {"completed"} else {"reconciled"}});
        save_completion_in(
            &mut tx,
            &operation,
            &response,
            reconcile_receipt,
            event.cursor,
        )
        .await?;
        tx.commit().await?;
        Ok(AgentChatNativeOperationCompleteOutcome::Committed {
            record: Box::new(record),
            event,
            response,
        })
    }
}
