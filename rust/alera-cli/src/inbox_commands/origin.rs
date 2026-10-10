//! The MCP client behind an `inbox` command, when an MCP tool runs it: who a
//! question is attributed to, which threads `--scope own` keeps, and whether
//! each returned thread or message is the caller's own.

use serde_json::{json, Map, Value};

use crate::cli_inbox::InboxScope;
use crate::mcp_tools::CallOrigin;

/// `externalOrigin` for `inbox.ask`: who asked, without the per-call id.
pub(super) fn external_origin(origin: &CallOrigin) -> Value {
    let mut value = Map::new();
    value.insert("transport".into(), json!(origin.transport));
    for (key, field) in [
        ("clientId", &origin.client_id),
        ("clientName", &origin.client_name),
        ("grantId", &origin.grant_id),
    ] {
        if let Some(text) = field {
            value.insert(key.into(), json!(text));
        }
    }
    Value::Object(value)
}

/// The `originClientId` filter: an explicit id, or the caller's own for
/// `--scope own`.
pub(super) fn client_filter(
    explicit: Option<String>,
    scope: Option<InboxScope>,
    caller: Option<&CallOrigin>,
) -> Result<Option<String>, String> {
    if explicit.is_some() {
        return Ok(explicit);
    }
    if scope != Some(InboxScope::Own) {
        return Ok(None);
    }
    caller
        .and_then(|origin| origin.client_id.clone())
        .map(Some)
        .ok_or_else(|| {
            "--scope own needs the identity of the MCP client running this command; use --scope all."
                .to_string()
        })
}

/// Whether `origin` (a thread's recorded origin) names the calling client.
fn is_own(origin: &Value, caller: Option<&CallOrigin>) -> bool {
    let Some(client_id) = caller.and_then(|origin| origin.client_id.as_deref()) else {
        return false;
    };
    origin["surface"] == "mcp" && origin["clientId"].as_str() == Some(client_id)
}

/// Adds `isOwn` to listed threads and to a shown thread, and `threadId`,
/// `origin`, and `isOwn` to the messages of an inbox wait.
pub(super) fn annotate(value: &mut Value, caller: Option<&CallOrigin>) {
    let listing = value["kind"] == "inboxThreads";
    if let Some(items) = value.get_mut("items").and_then(Value::as_array_mut) {
        for thread in items.iter_mut().filter(|_| listing) {
            let own = is_own(&thread["origin"], caller);
            thread["isOwn"] = json!(own);
        }
    }
    if let Some(thread) = value.get_mut("thread").filter(|thread| thread.is_object()) {
        let own = is_own(&thread["origin"], caller);
        thread["isOwn"] = json!(own);
    }
    let Some(origins) = value.get("threadOrigins").cloned() else {
        return;
    };
    if let Some(messages) = value.get_mut("messages").and_then(Value::as_array_mut) {
        for message in messages {
            let thread_id = message["thread_id"]
                .as_str()
                .or_else(|| message["id"].as_str())
                .unwrap_or_default()
                .to_string();
            let origin = origins.get(&thread_id).cloned().unwrap_or(Value::Null);
            message["isOwn"] = json!(is_own(&origin, caller));
            message["origin"] = origin;
            message["threadId"] = json!(thread_id);
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn caller(client_id: &str) -> CallOrigin {
        CallOrigin::remote(client_id, "ChatGPT", "g-1", "c-1")
    }

    #[test]
    fn the_external_origin_drops_the_call_id() {
        let origin = external_origin(&caller("chatgpt"));
        assert_eq!(
            origin,
            json!({"transport": "remote", "clientId": "chatgpt", "clientName": "ChatGPT", "grantId": "g-1"})
        );
    }

    #[test]
    fn own_scope_uses_the_callers_client_id() {
        let chatgpt = caller("chatgpt");
        assert_eq!(
            client_filter(None, Some(InboxScope::Own), Some(&chatgpt)).unwrap(),
            Some("chatgpt".to_string())
        );
        assert_eq!(
            client_filter(None, Some(InboxScope::All), Some(&chatgpt)).unwrap(),
            None
        );
        assert_eq!(
            client_filter(Some("other".into()), None, None).unwrap(),
            Some("other".to_string())
        );
        assert!(client_filter(None, Some(InboxScope::Own), None).is_err());
    }

    #[test]
    fn threads_and_messages_say_whether_they_are_the_callers() {
        let chatgpt = caller("chatgpt");
        let mut listing = json!({"kind": "inboxThreads", "items": [
            {"threadId": "a", "origin": {"surface": "mcp", "clientId": "chatgpt"}},
            {"threadId": "b", "origin": {"surface": "mcp", "clientId": "claude-ai"}},
            {"threadId": "c", "origin": null},
        ]});
        annotate(&mut listing, Some(&chatgpt));
        let own: Vec<bool> = listing["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|item| item["isOwn"].as_bool().unwrap())
            .collect();
        assert_eq!(own, [true, false, false]);
        let mut wait = json!({
            "outcome": "message",
            "messages": [{"id": "r1", "thread_id": "a"}, {"id": "r2", "thread_id": "z"}],
            "threadOrigins": {"a": {"surface": "mcp", "clientId": "chatgpt"}},
        });
        annotate(&mut wait, Some(&chatgpt));
        assert_eq!(wait["messages"][0]["isOwn"], true);
        assert_eq!(wait["messages"][0]["threadId"], "a");
        assert_eq!(wait["messages"][1]["origin"], json!(null));
        assert_eq!(wait["messages"][1]["isOwn"], false);
        let mut anonymous = listing.clone();
        annotate(&mut anonymous, None);
        assert_eq!(anonymous["items"][0]["isOwn"], false);
    }
}
