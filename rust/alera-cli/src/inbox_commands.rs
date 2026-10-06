use std::time::{Duration, Instant};

use serde_json::{json, Map, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_inbox::{InboxAction, InboxCommand, InboxWaitArgs};
use crate::orchestration_commands::{read_body, request_value_with_capability};
use crate::terminal_host::protocol::{
    ORCHESTRATION_MAX_WAIT_TIMEOUT_MS, RUNTIME_HOST_INBOX_CAPABILITY,
};

const DEFAULT_INBOX: &str = "ext:user";
const DEFAULT_WAIT_MS: u64 = 10 * 60 * 1000;
/// The host answers a parked wait at its deadline; the client allows a little more.
const WAIT_CLIENT_GRACE_MS: u64 = 15_000;
const RECONNECT_BACKOFF: Duration = Duration::from_secs(2);

pub(crate) async fn run(command: InboxCommand) -> i32 {
    let json_output = command.output.json;
    let runtime = command.runtime;
    let result = match command.action {
        InboxAction::Targets(args) => {
            call(
                &runtime,
                "inbox.targets",
                json!({ "workspaceId": args.workspace }),
            )
            .await
        }
        InboxAction::Ask(args) => {
            let body = match read_body(args.body, args.body_file, args.body_stdin) {
                Ok(Some(body)) if !body.trim().is_empty() => body,
                Ok(_) => return usage("--body, --body-file or --body-stdin is required."),
                Err(message) => return usage(&message),
            };
            if args.to.is_none() && args.workspace.is_none() && args.thread.is_none() {
                return usage("--to, --workspace or --thread is required.");
            }
            let mut payload = Map::new();
            // A follow-up inherits its thread's inbox unless one is named.
            let inbox = match (&args.thread, args.address.inbox) {
                (Some(_), None) => None,
                (_, inbox) => Some(inbox_address(inbox)),
            };
            insert(&mut payload, "inbox", inbox);
            insert(&mut payload, "to", args.to);
            insert(&mut payload, "workspaceId", args.workspace);
            insert(&mut payload, "agent", args.agent);
            insert(&mut payload, "threadId", args.thread);
            insert(&mut payload, "subject", args.subject);
            insert(&mut payload, "priority", args.priority);
            insert(&mut payload, "expiresInMs", args.expires_in_ms);
            payload.insert("body".into(), json!(body));
            call(&runtime, "inbox.ask", Value::Object(payload)).await
        }
        InboxAction::List => call(&runtime, "inbox.summary", json!({})).await,
        InboxAction::Threads(args) => {
            let mut payload = Map::new();
            if !args.all_inboxes {
                payload.insert("inbox".into(), json!(inbox_address(args.address.inbox)));
            }
            insert(&mut payload, "workspaceId", args.workspace);
            insert(&mut payload, "status", args.status);
            insert(&mut payload, "limit", args.limit);
            insert(&mut payload, "before", args.before);
            call(&runtime, "inbox.threads", Value::Object(payload)).await
        }
        InboxAction::Show(args) => {
            call(
                &runtime,
                "inbox.thread",
                json!({ "questionId": args.question }),
            )
            .await
        }
        InboxAction::Read(args) => {
            call(
                &runtime,
                "inbox.markRead",
                json!({ "questionId": args.question }),
            )
            .await
        }
        InboxAction::Cancel(args) => {
            call(
                &runtime,
                "inbox.cancel",
                json!({ "questionId": args.question }),
            )
            .await
        }
        InboxAction::Purge(args) => {
            if !args.confirm {
                return usage(
                    "purge deletes every question and reply of the inbox; pass --confirm.",
                );
            }
            let inbox = inbox_address(args.address.inbox);
            call(&runtime, "inbox.purge", json!({ "inbox": inbox })).await
        }
        InboxAction::Wait(args) => wait(&runtime, args).await,
        InboxAction::Conversations(args) => {
            let mut payload = Map::new();
            insert(&mut payload, "workspaceId", args.workspace);
            insert(&mut payload, "participant", args.participant);
            insert(&mut payload, "limit", args.limit);
            insert(&mut payload, "before", args.before);
            call(&runtime, "inbox.conversations", Value::Object(payload)).await
        }
        InboxAction::Conversation(args) => {
            call(
                &runtime,
                "inbox.conversation",
                json!({ "threadId": args.thread }),
            )
            .await
        }
    };
    match result {
        Ok(value) => {
            print(&value, json_output);
            exit_code(&value)
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn inbox_address(explicit: Option<String>) -> String {
    explicit
        .or_else(|| {
            std::env::var("ALERA_EXTERNAL_INBOX")
                .ok()
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
        })
        .unwrap_or_else(|| DEFAULT_INBOX.to_string())
}

fn insert<T: Into<Value>>(payload: &mut Map<String, Value>, key: &str, value: Option<T>) {
    if let Some(value) = value {
        payload.insert(key.to_string(), value.into());
    }
}

async fn call(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    payload: Value,
) -> anyhow::Result<Value> {
    request_value_with_capability(
        runtime,
        RUNTIME_HOST_INBOX_CAPABILITY,
        request_type,
        payload,
        None,
    )
    .await
}

/// Chains host waits, each at most the host's ceiling, until there is news or
/// the overall deadline passes. A dropped connection is retried, so a host
/// restart in the middle of a long wait does not end it.
async fn wait(runtime: &RuntimeDirArgs, args: InboxWaitArgs) -> anyhow::Result<Value> {
    let total = Duration::from_millis(args.timeout_ms.unwrap_or(DEFAULT_WAIT_MS));
    let started = Instant::now();
    let mut payload = Map::new();
    match args.question {
        Some(question) => payload.insert("questionId".into(), json!(question)),
        None => payload.insert("inbox".into(), json!(inbox_address(args.address.inbox))),
    };
    payload.insert("after".into(), json!(args.after));
    loop {
        let remaining = total.saturating_sub(started.elapsed());
        // Never 0: the host treats 0 as a poll and answers `pending`.
        let slice_ms = (remaining.as_millis() as u64).clamp(1, ORCHESTRATION_MAX_WAIT_TIMEOUT_MS);
        payload.insert("timeoutMs".into(), json!(slice_ms));
        let result = request_value_with_capability(
            runtime,
            RUNTIME_HOST_INBOX_CAPABILITY,
            "inbox.wait",
            Value::Object(payload.clone()),
            Some(slice_ms.saturating_add(WAIT_CLIENT_GRACE_MS)),
        )
        .await;
        let still_time = started.elapsed() + RECONNECT_BACKOFF < total;
        match result {
            Ok(value) if value["outcome"] == "timeout" && still_time => {}
            Ok(mut value) => {
                if value["outcome"] == "pending" {
                    value["outcome"] = json!("timeout");
                }
                value["waitedMs"] = json!(started.elapsed().as_millis() as u64);
                return Ok(value);
            }
            Err(error) if still_time && is_transport_failure(&error) => {
                tokio::time::sleep(RECONNECT_BACKOFF).await
            }
            Err(error) => return Err(error),
        }
    }
}

/// `wait` exits 2 on timeout so scripts can tell "no answer yet" from errors.
fn exit_code(value: &Value) -> i32 {
    if value["outcome"] == "timeout" {
        2
    } else {
        0
    }
}

fn usage(message: &str) -> i32 {
    eprintln!("{message}");
    crate::USAGE_EXIT_CODE
}

fn print(value: &Value, json_output: bool) {
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".to_string())
        );
        return;
    }
    println!("{}", human_summary(value));
}

/// A lost, restarting or still starting host is worth waiting out; an
/// answer the host gave, such as an unknown question, is final.
fn is_transport_failure(error: &anyhow::Error) -> bool {
    error
        .downcast_ref::<crate::runtime_host_client::RuntimeHostAnswer>()
        .is_none()
}

fn human_summary(value: &Value) -> String {
    if let Some(deleted) = value["deleted"].as_u64() {
        return format!("purged {deleted} message(s)");
    }
    if let Some(marked) = value["marked"].as_u64() {
        return format!("marked {marked} reply(ies) read");
    }
    if value["message"].is_object() && value["questionId"].is_null() {
        return format!(
            "question {} is {}",
            value["message"]["id"].as_str().unwrap_or("?"),
            value["message"]["state"].as_str().unwrap_or("?"),
        );
    }
    if let Some(question_id) = value["questionId"]
        .as_str()
        .filter(|_| value["message"].is_object())
    {
        return format!(
            "question {question_id} to {} ({})",
            value["recipient"]["handle"].as_str().unwrap_or("?"),
            value["recipient"]["deliveryMode"].as_str().unwrap_or("?"),
        );
    }
    if let Some(outcome) = value["outcome"].as_str() {
        let mut lines = vec![format!(
            "{outcome} (cursor {})",
            value["cursor"].as_i64().unwrap_or(0)
        )];
        lines.extend(message_lines(&value["messages"]));
        return lines.join("\n");
    }
    if value["threadId"].is_string() && value["messages"].is_array() {
        return message_lines(&value["messages"]).join("\n");
    }
    if value["thread"].is_object() {
        let thread = &value["thread"];
        let mut lines = vec![format!(
            "{} [{}] {} -> {}",
            thread["subject"].as_str().unwrap_or(""),
            thread["status"].as_str().unwrap_or(""),
            thread["inbox"].as_str().unwrap_or(""),
            thread["recipient"].as_str().unwrap_or(""),
        )];
        lines.extend(message_lines(&value["messages"]));
        return lines.join("\n");
    }
    let listing = match value["kind"].as_str() {
        Some("inboxThreads") => list_lines(&value["items"], |thread| {
            format!(
                "{}  {:<9}  {}  {}",
                thread["threadId"].as_str().unwrap_or(""),
                thread["status"].as_str().unwrap_or(""),
                thread["recipient"].as_str().unwrap_or(""),
                thread["subject"].as_str().unwrap_or(""),
            )
        }),
        Some("inboxes") => list_lines(&value["items"], |inbox| {
            format!(
                "{}  threads={} pending={} awaiting={} unread={}",
                inbox["inbox"].as_str().unwrap_or(""),
                inbox["threadCount"],
                inbox["pendingCount"],
                inbox["awaitingReplyCount"],
                inbox["unreadReplyCount"],
            )
        }),
        Some("conversations") => list_lines(&value["items"], |thread| {
            format!(
                "{}  {} messages  {}  {}",
                thread["threadId"].as_str().unwrap_or(""),
                thread["messageCount"],
                thread["participants"]
                    .as_array()
                    .map(|handles| handles
                        .iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join(", "))
                    .unwrap_or_default(),
                thread["subject"].as_str().unwrap_or(""),
            )
        }),
        Some("inboxTargets") => list_lines(&value["items"], |target| {
            format!(
                "{}  {}  {}  {}",
                target["handle"].as_str().unwrap_or(""),
                target["agent"].as_str().unwrap_or("-"),
                target["deliveryMode"].as_str().unwrap_or(""),
                target["tabTitle"].as_str().unwrap_or(""),
            )
        }),
        _ => return serde_json::to_string_pretty(value).unwrap_or_default(),
    };
    match value["nextBefore"].as_i64() {
        Some(before) => format!("{listing}\nmore: --before {before}"),
        None => listing,
    }
}

fn list_lines(items: &Value, line: impl Fn(&Value) -> String) -> String {
    let items = items.as_array().cloned().unwrap_or_default();
    if items.is_empty() {
        return "(none)".to_string();
    }
    items.iter().map(line).collect::<Vec<_>>().join("\n")
}

fn message_lines(messages: &Value) -> Vec<String> {
    messages
        .as_array()
        .into_iter()
        .flatten()
        .map(|entry| {
            // Inbox entries wrap the message; agent conversations list it bare.
            let message = if entry["message"].is_object() {
                &entry["message"]
            } else {
                entry
            };
            format!(
                "--- {} {} from {} (#{})\n{}",
                entry["kind"].as_str().unwrap_or("message"),
                entry["status"].as_str().unwrap_or(""),
                message["from_handle"].as_str().unwrap_or(""),
                message["sequence"],
                message["body"].as_str().unwrap_or(""),
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inbox_address_prefers_the_flag_then_the_environment() {
        assert_eq!(inbox_address(Some("ext:ci".into())), "ext:ci");
        assert_eq!(exit_code(&json!({"outcome": "timeout"})), 2);
        assert_eq!(exit_code(&json!({"outcome": "answered"})), 0);
    }

    #[test]
    fn only_transport_failures_are_retried() {
        let io = anyhow::Error::new(std::io::Error::from(std::io::ErrorKind::ConnectionRefused));
        assert!(is_transport_failure(&io));
        assert!(is_transport_failure(&anyhow::anyhow!(
            "the runtime profile is owned by a host that is still starting"
        )));
        let answer = anyhow::Error::new(crate::runtime_host_client::RuntimeHostAnswer(
            "No inbox question did not answer".to_string(),
        ));
        assert!(!is_transport_failure(&answer));
        assert_eq!(human_summary(&json!({"deleted": 3})), "purged 3 message(s)");
        assert_eq!(
            human_summary(&json!({"marked": 1})),
            "marked 1 reply(ies) read"
        );
        assert_eq!(
            human_summary(&json!({"message": {"id": "msg_1", "state": "obsolete"}})),
            "question msg_1 is obsolete"
        );
    }

    #[test]
    fn summaries_name_the_outcome_and_the_messages() {
        let summary = human_summary(&json!({
            "outcome": "answered",
            "cursor": 12,
            "messages": [{"kind": "reply", "message": {"from_handle": "term", "sequence": 12, "body": "Done"}}],
        }));
        assert!(summary.starts_with("answered (cursor 12)"));
        assert!(summary.contains("Done"));
        let listing = human_summary(&json!({
            "kind": "inboxThreads",
            "items": [{"threadId": "msg_1", "status": "pending", "recipient": "term", "subject": "Q"}],
            "nextBefore": 40,
        }));
        assert!(listing.ends_with("more: --before 40"));
        assert_eq!(usage("missing --body"), crate::USAGE_EXIT_CODE);
    }
}
