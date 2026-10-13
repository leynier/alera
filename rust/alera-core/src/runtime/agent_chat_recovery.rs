//! Startup recovery. Provider processes do not survive the runtime, so a
//! chat left live is committed as stopped: running turns become interrupted
//! with `reason: runtimeRestarted`, open requests expire, streaming items
//! settle, and `recovery {kind, message, canResume, canRestart}` says what
//! the user can do next. Nothing is re-sent to a model; queued user input
//! (user messages and any host field outside the canonical ones) stays for
//! an explicit resume or send.

use anyhow::Result;
use chrono::Utc;
use serde_json::{json, Value};
use sqlx::Row;

use super::agent_chat_commit::commit_in;
use super::agent_chat_models::*;
use super::agent_chat_projection::required_turns_in;
use super::agent_chat_store::require_session_row_in;
use super::agent_chat_validation::parse_header;
use super::{format_timestamp, RuntimeStore};

const USER_MESSAGE: &str = "user_message";

fn needs_recovery(snapshot: &AgentChatSnapshot) -> bool {
    snapshot.session.status.is_live()
        || snapshot.session.active_turn_id.is_some()
        || !snapshot.pending_requests.is_empty()
        || snapshot.turns.iter().any(|turn| turn.status == "running")
}

impl RuntimeStore {
    /// Run once by the runtime owner before it accepts agent chat commands.
    /// Each chat is recovered in its own transaction and cursor step.
    pub async fn recover_agent_chats(&self) -> Result<Vec<AgentChatRecoveryOutcome>> {
        let candidates: Vec<String> = sqlx::query_scalar(
            "SELECT DISTINCT s.chatId FROM agentChatSessions s \
             WHERE json_extract(s.snapshotJson, '$.session.status') IN ('starting', 'ready', 'running', 'waiting') \
             OR json_extract(s.snapshotJson, '$.session.activeTurnId') IS NOT NULL \
             OR json_array_length(s.snapshotJson, '$.pendingRequests') > 0 \
             OR EXISTS (SELECT 1 FROM agentChatTurns t \
                 WHERE t.chatId = s.chatId AND t.status = 'running') \
             OR EXISTS (SELECT 1 FROM agentChatItems i WHERE i.chatId = s.chatId \
                 AND (json_extract(i.itemJson, '$.streaming') = 1 \
                 OR json_extract(i.itemJson, '$.status') = 'inProgress')) \
             ORDER BY s.chatId",
        )
        .fetch_all(self.pool())
        .await?;
        let mut outcomes = Vec::new();
        for chat_id in candidates {
            if let Some(outcome) = self.recover_agent_chat(&chat_id).await? {
                outcomes.push(outcome);
            }
        }
        Ok(outcomes)
    }

    async fn recover_agent_chat(&self, chat_id: &str) -> Result<Option<AgentChatRecoveryOutcome>> {
        let mut tx = self.pool().begin().await?;
        let row = require_session_row_in(&mut tx, chat_id).await?;
        let mut stored = parse_header(&row.snapshot_json)?;
        stored.turns = required_turns_in(&mut tx, chat_id, &stored).await?;
        let now = format_timestamp(Utc::now());

        let item_rows = sqlx::query(
            "SELECT itemJson FROM agentChatItems WHERE chatId = ? \
             AND (json_extract(itemJson, '$.streaming') = 1 OR json_extract(itemJson, '$.status') = 'inProgress') \
             ORDER BY seq",
        )
        .bind(chat_id)
        .fetch_all(&mut *tx)
        .await?;
        let mut items = Vec::new();
        for item_row in item_rows {
            let mut item: AgentChatItem =
                serde_json::from_str(item_row.try_get::<&str, _>("itemJson")?)?;
            let before = item.clone();
            item.streaming = false;
            if item.status == "inProgress" && item.item_type != USER_MESSAGE {
                item.status = "failed".into();
            }
            if item != before {
                item.updated_at = now.clone();
                items.push(item);
            }
        }
        if !needs_recovery(&stored) && items.is_empty() {
            tx.commit().await?;
            return Ok(None);
        }

        let mut snapshot = stored.clone();
        let mut interrupted = Vec::new();
        let mut turns = Vec::new();
        for turn in &mut snapshot.turns {
            if turn.status == "running" {
                turn.status = "interrupted".into();
                turn.reason = Some(AGENT_CHAT_INTERRUPT_RUNTIME_RESTARTED.into());
                turn.completed_at = Some(now.clone());
                interrupted.push(turn.turn_id.clone());
                turns.push(turn.clone());
            }
        }
        if let Some(active) = snapshot.session.active_turn_id.take() {
            if !interrupted.contains(&active) {
                interrupted.push(active);
            }
        }
        if snapshot.session.status != AgentChatSessionStatus::Error {
            snapshot.session.status = AgentChatSessionStatus::Stopped;
        }
        let expired: Vec<String> = snapshot
            .pending_requests
            .drain(..)
            .map(|request| request.request_id)
            .collect();
        // Resuming needs both a provider thread to resume and a provider that
        // says it can; a thread id alone proves neither.
        let can_resume = row.native_thread_id.is_some()
            && stored
                .session
                .capabilities
                .get("resume")
                .and_then(Value::as_bool)
                == Some(true);
        let can_restart = true;
        let (kind, message) = if can_resume {
            (
                AGENT_CHAT_RECOVERY_RESUMABLE,
                "The Alera runtime restarted and stopped this chat. Resume to continue the provider session.",
            )
        } else {
            (
                AGENT_CHAT_RECOVERY_NOT_RESUMABLE,
                "The Alera runtime restarted and stopped this chat. Restart to continue with its history in a new provider session.",
            )
        };
        let recovery = json!({
            "kind": kind,
            "message": message,
            "canResume": can_resume,
            "canRestart": can_restart,
            "reason": AGENT_CHAT_INTERRUPT_RUNTIME_RESTARTED,
            "recoveredAt": now,
            "previousStatus": stored.session.status,
            "generation": row.generation,
            "interruptedTurnIds": interrupted,
            "expiredRequestIds": expired,
        });
        snapshot.recovery = Some(recovery.clone());
        snapshot.cursor = row.cursor + 1;
        snapshot.items.clear();

        let delta = AgentChatDelta {
            items: (!items.is_empty()).then_some(items),
            requests: (!expired.is_empty()).then(Vec::new),
            session: (snapshot.session != stored.session).then(|| snapshot.session.clone()),
            turns: (!turns.is_empty()).then_some(turns),
            recovery: Some(Some(recovery)),
            ..AgentChatDelta::default()
        };
        let event = commit_in(&mut tx, &row, snapshot, delta, None).await?;
        tx.commit().await?;
        Ok(Some(AgentChatRecoveryOutcome {
            chat_id: chat_id.to_string(),
            cursor: event.cursor,
            interrupted_turn_ids: interrupted,
            expired_request_ids: expired,
            can_resume,
            can_restart,
        }))
    }
}
