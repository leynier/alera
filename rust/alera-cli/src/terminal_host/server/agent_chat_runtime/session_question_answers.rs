//! Questions answered by message. A question whose provider callback is gone
//! (the runtime restarted while it waited) stays pending as
//! `answerBy: message`; its answer goes to the agent as a new user message,
//! one `question\nanswer` block per question, and resumes the chat like any
//! other message.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{unsupported, CallerCtx, SendInput};
use super::session::ChatSession;
use super::wire::ChatRequest;

/// `origin.kind` of the user message that answers a question.
pub(crate) const QUESTION_ANSWER_ORIGIN: &str = "questionAnswer";

impl ChatSession {
    /// Answers `row` with a `userInput` response. An empty `answers` map
    /// dismisses the question without a message.
    pub(super) async fn answer_by_message(
        &mut self,
        row: ChatRequest,
        response: Value,
        ctx: &CallerCtx,
    ) -> HostResult<Value> {
        if response["type"] != "userInput" {
            return Err(unsupported(
                "This question is answered with a userInput response.",
            ));
        }
        let answers = response["answers"]
            .as_object()
            .ok_or_else(|| HostError::format("answers must be an object"))?;
        let mut answer = json!({
            "resolved": true,
            "answeredBy": "message",
            "answeredTurnId": row.turn_id,
        });
        if answers.is_empty() {
            answer["dismissed"] = json!(true);
        } else {
            let text = super::request_answers::message_answer_text(&row.questions, answers)?;
            // Boxed: a send can answer requests itself (declineRequests).
            let sent = Box::pin(self.send(
                SendInput {
                    client_message_id: format!("question-answer:{}", row.request_id),
                    text,
                    attachments: Vec::new(),
                    delivery: "auto".into(),
                    model: None,
                    reasoning_effort: None,
                    interaction_mode: None,
                    runtime_mode_ceiling: None,
                    origin: Some(json!({
                        "kind": QUESTION_ANSWER_ORIGIN,
                        "requestId": row.request_id,
                        "answeredTurnId": row.turn_id,
                    })),
                },
                ctx,
            ))
            .await?;
            for key in ["delivery", "turnId", "queueId", "itemId"] {
                if let Some(value) = sent.get(key) {
                    answer[key] = value.clone();
                }
            }
        }
        self.record_request_history(&row, "resolved", Some(&response), Some(&ctx.actor));
        self.header
            .pending_requests
            .retain(|request| request.request_id != row.request_id);
        self.refresh_waiting_status();
        Ok(answer)
    }
}
