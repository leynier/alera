//! Background AI title jobs of agent chats. A session actor starts a job and
//! keeps going; the job reads the stored conversation, asks AI Assist
//! (`agentTitle`) and posts `ChatOp::ApplyGeneratedTitle` back to the actor,
//! which decides whether the title still applies.

use std::path::PathBuf;
use std::sync::Arc;

use alera_core::runtime::RuntimeStore;
use async_trait::async_trait;
use serde_json::Value;
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;

use super::agent_chat_runtime::commands::{CallerCtx, ChatEnvelope, ChatOp};
use super::agent_chat_title_prompt::{
    chat_title_prompt, limit_middle, parse_chat_title, ChatTitleForkSource, ChatTitleRequest,
};
use super::ai_assist_generation::generate_ai_assist_output;

const PAGE_ITEMS: i64 = 200;
const MAX_PAGES: usize = 16;
const MESSAGE_CHARS: usize = 2_000;
const CONTEXT_CHARS: usize = 8_000;

/// Produces chat titles. Production asks AI Assist; tests script answers.
#[async_trait]
pub(crate) trait ChatTitleGenerator: Send + Sync + 'static {
    /// Whether the one automatic attempt may run (`autoGenerateAgentTitles`).
    async fn automatic_enabled(&self) -> bool;
    async fn generate(
        &self,
        request: ChatTitleRequest,
        cancel: oneshot::Receiver<()>,
    ) -> Result<String, String>;
}

/// The production generator: AI Assist's `agentTitle` operation.
pub(crate) struct AiAssistChatTitles {
    store: RuntimeStore,
    runtime_dir: PathBuf,
}

impl AiAssistChatTitles {
    pub(crate) fn new(store: RuntimeStore, runtime_dir: PathBuf) -> Self {
        Self { store, runtime_dir }
    }
}

#[async_trait]
impl ChatTitleGenerator for AiAssistChatTitles {
    async fn automatic_enabled(&self) -> bool {
        self.store
            .effective_ai_assist_settings()
            .await
            .is_ok_and(|settings| settings.enabled && settings.auto_generate_agent_titles)
    }

    async fn generate(
        &self,
        request: ChatTitleRequest,
        cancel: oneshot::Receiver<()>,
    ) -> Result<String, String> {
        let settings = self
            .store
            .effective_ai_assist_settings()
            .await
            .map_err(|_| "AI Assist settings are unavailable.".to_string())?;
        if !settings.enabled {
            return Err("AI Assist is disabled.".into());
        }
        let instructions = settings
            .instructions_by_operation
            .get("agentTitle")
            .map(String::as_str)
            .unwrap_or_default();
        let prompt = chat_title_prompt(&request, instructions).map_err(|e| e.wire_message())?;
        let directory = self
            .runtime_dir
            .join("agent-title-jobs")
            .join(Uuid::new_v4().to_string());
        tokio::fs::create_dir_all(&directory)
            .await
            .map_err(|_| "Could not prepare title generation.".to_string())?;
        let output = generate_ai_assist_output(
            &settings,
            "agentTitle",
            &prompt,
            &directory.to_string_lossy(),
            cancel,
        )
        .await;
        let _ = tokio::fs::remove_dir_all(&directory).await;
        let (output, _) = output.map_err(|_| {
            "AI Assist could not generate a title. Check the configured provider and try again."
                .to_string()
        })?;
        parse_chat_title(&output).map_err(|e| e.wire_message())
    }
}

/// One job, as the session actor describes it.
pub(crate) struct ChatTitleJob {
    pub chat_id: String,
    pub job_id: String,
    /// Set for regeneration: the title the chat has now.
    pub previous_title: Option<String>,
    /// Set for a fork: the source chat's title and the turn it forked at.
    pub fork: Option<(String, String)>,
}

/// Starts `job` off the actor; the returned sender cancels it.
pub(crate) fn spawn_chat_title_job(
    job: ChatTitleJob,
    store: RuntimeStore,
    generator: Arc<dyn ChatTitleGenerator>,
    mailbox: Option<mpsc::WeakSender<ChatEnvelope>>,
) -> oneshot::Sender<()> {
    let (cancel_tx, cancel_rx) = oneshot::channel();
    tokio::spawn(async move {
        let result = async {
            let messages = conversation(&store, &job.chat_id).await?;
            let request = title_request(&messages, job.previous_title, job.fork)?;
            generator.generate(request, cancel_rx).await
        }
        .await;
        let Some(mailbox) = mailbox.and_then(|mailbox| mailbox.upgrade()) else {
            return;
        };
        let (reply, _) = oneshot::channel();
        let _ = mailbox
            .send(ChatEnvelope {
                op: ChatOp::ApplyGeneratedTitle {
                    job_id: job.job_id,
                    result,
                },
                ctx: CallerCtx::runtime(),
                receipt_key: None,
                reply,
            })
            .await;
    });
    cancel_tx
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TitleMessage {
    pub role: &'static str,
    pub text: String,
    pub turn_id: Option<String>,
}

/// The user and assistant messages of a chat, oldest first, each bounded.
async fn conversation(store: &RuntimeStore, chat_id: &str) -> Result<Vec<TitleMessage>, String> {
    let mut before = i64::MAX;
    let mut messages = Vec::new();
    for _ in 0..MAX_PAGES {
        let page = store
            .agent_chat_history(chat_id, before, PAGE_ITEMS)
            .await
            .map_err(|_| "The chat conversation is unavailable.".to_string())?;
        let mut older: Vec<TitleMessage> = page.items.iter().filter_map(title_message).collect();
        older.append(&mut messages);
        messages = older;
        match page.history_before {
            Some(next) if next < before => before = next,
            _ => break,
        }
    }
    Ok(messages)
}

fn title_message(item: &Value) -> Option<TitleMessage> {
    let role = match item.get("type")?.as_str()? {
        "user_message" => "USER",
        "assistant_message" => "ASSISTANT",
        _ => return None,
    };
    let text = item.get("text")?.as_str()?.trim();
    if text.is_empty() {
        return None;
    }
    Some(TitleMessage {
        role,
        text: limit_middle(text, MESSAGE_CHARS),
        turn_id: item
            .get("turnId")
            .and_then(Value::as_str)
            .map(str::to_owned),
    })
}

/// Splits the conversation at the fork point and picks what the prompt reads.
pub(crate) fn title_request(
    messages: &[TitleMessage],
    previous_title: Option<String>,
    fork: Option<(String, String)>,
) -> Result<ChatTitleRequest, String> {
    let (before, after) = match &fork {
        Some((_, turn_id)) => {
            let split = messages
                .iter()
                .rposition(|message| message.turn_id.as_deref() == Some(turn_id))
                .map_or(0, |index| index + 1);
            messages.split_at(split)
        }
        None => (&messages[..0], messages),
    };
    let conversation = if previous_title.is_none() {
        after
            .iter()
            .find(|message| message.role == "USER")
            .map(|message| message.text.clone())
            .unwrap_or_else(|| format_messages(after))
    } else {
        format_messages(after)
    };
    if conversation.trim().is_empty() {
        return Err("No conversation content is available to generate a title.".into());
    }
    Ok(ChatTitleRequest {
        previous_title,
        fork: fork.map(|(title, _)| ChatTitleForkSource {
            title,
            history: format_messages(before),
        }),
        conversation,
    })
}

/// `ROLE:\ntext` sections within the context budget: the first user message,
/// then the newest messages, in conversation order.
fn format_messages(messages: &[TitleMessage]) -> String {
    let section = |message: &TitleMessage| format!("{}:\n{}", message.role, message.text);
    let mut chosen = vec![false; messages.len()];
    let mut remaining = CONTEXT_CHARS;
    let mut take = |index: usize, chosen: &mut Vec<bool>| {
        let size = section(&messages[index]).chars().count() + 2;
        if !chosen[index] && size <= remaining {
            chosen[index] = true;
            remaining -= size;
        }
    };
    if let Some(first) = messages.iter().position(|message| message.role == "USER") {
        take(first, &mut chosen);
    }
    for index in (0..messages.len()).rev() {
        take(index, &mut chosen);
    }
    messages
        .iter()
        .zip(chosen)
        .filter(|(_, chosen)| *chosen)
        .map(|(message, _)| section(message))
        .collect::<Vec<_>>()
        .join("\n\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(role: &'static str, text: &str, turn: &str) -> TitleMessage {
        TitleMessage {
            role,
            text: text.into(),
            turn_id: Some(turn.into()),
        }
    }

    #[test]
    fn initial_title_reads_the_first_user_message() {
        let messages = [
            message("USER", "Fix the login crash", "t1"),
            message("ASSISTANT", "Looking", "t1"),
        ];
        let request = title_request(&messages, None, None).unwrap();
        assert_eq!(request.conversation, "Fix the login crash");
        assert!(request.fork.is_none());
    }

    #[test]
    fn fork_splits_inherited_history_from_the_new_direction() {
        let messages = [
            message("USER", "Fix the login crash", "t1"),
            message("ASSISTANT", "Fixed", "t1"),
            message("USER", "Now add tests", "t2"),
        ];
        let fork = Some(("Fix Login Crash".to_string(), "t1".to_string()));
        let request = title_request(&messages, None, fork).unwrap();
        assert_eq!(request.conversation, "Now add tests");
        let source = request.fork.unwrap();
        assert_eq!(source.title, "Fix Login Crash");
        assert_eq!(
            source.history,
            "USER:\nFix the login crash\n\nASSISTANT:\nFixed"
        );
    }

    #[test]
    fn regeneration_formats_the_conversation() {
        let messages = [
            message("USER", "first", "t1"),
            message("ASSISTANT", "answer", "t1"),
        ];
        let request = title_request(&messages, Some("Old".into()), None).unwrap();
        assert_eq!(request.conversation, "USER:\nfirst\n\nASSISTANT:\nanswer");
        assert!(title_request(&[], Some("Old".into()), None).is_err());
    }

    #[test]
    fn formatting_keeps_the_first_user_message_and_the_newest_ones() {
        let long = "x".repeat(MESSAGE_CHARS);
        let mut messages = vec![message("USER", "the subject", "t0")];
        for index in 1..20 {
            messages.push(message("ASSISTANT", &long, &format!("t{index}")));
        }
        messages.push(message("USER", "latest goal", "t20"));
        let formatted = format_messages(&messages);
        assert!(formatted.starts_with("USER:\nthe subject"));
        assert!(formatted.ends_with("USER:\nlatest goal"));
        assert!(formatted.chars().count() <= CONTEXT_CHARS);
    }
}
