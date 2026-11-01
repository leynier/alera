//! Claude MCP elicitations as Alera's generic `mcp_elicitation_approval`
//! request, so the request card shows the server's form, link or
//! confirmation and sends back what the person filled in. T3 Code instead
//! auto-fills consent and declines value forms and links; nothing is
//! filled in here on the person's behalf. An elicitation outside a turn is
//! declined without a card, as T3 does.

use super::canonical_payload::compact_nulls;
use super::*;
use alera_provider_protocol::{ElicitationAction, RequestId};
use claude_agent_sdk::{ElicitationCallback, ElicitationRequest, ElicitationResult};
use serde_json::Map;
use tokio::sync::oneshot;

pub(super) fn install_elicitation_callback(
    options: &mut ClaudeAgentOptions,
    request_tx: &mpsc::Sender<RequestNotice>,
    pending: &Arc<Mutex<HashMap<String, PendingResponse>>>,
    next_request: &Arc<AtomicU64>,
    thread_id: &Arc<Mutex<Option<String>>>,
    turn_id: &Arc<Mutex<Option<String>>>,
) {
    let tx = request_tx.clone();
    let pending = Arc::clone(pending);
    let next_request = Arc::clone(next_request);
    let thread_id = Arc::clone(thread_id);
    let turn_id = Arc::clone(turn_id);
    let callback: ElicitationCallback = Arc::new(move |request| {
        let tx = tx.clone();
        let pending = Arc::clone(&pending);
        let next_request = Arc::clone(&next_request);
        let thread_id = Arc::clone(&thread_id);
        let turn_id = Arc::clone(&turn_id);
        Box::pin(async move {
            let Some(turn) = turn_id.lock().await.clone() else {
                return Ok(ElicitationResult::decline());
            };
            let request_id = format!(
                "claude-request-{}",
                next_request.fetch_add(1, Ordering::Relaxed) + 1
            );
            let mode = elicitation_mode(&request);
            let runtime_request = RuntimeRequest {
                request_id: RequestId::from(request_id.clone()),
                thread_id: thread_id.lock().await.clone().unwrap_or_default(),
                turn_id: Some(turn),
                item_id: None,
                kind: RequestKind::McpElicitationApproval,
                questions: Vec::new(),
                payload: elicitation_payload(&request, mode),
                supports_feedback: false,
            };
            let native_request_id =
                Some(request.control.request_id.clone()).filter(|id| !id.trim().is_empty());
            let raw = if request.control.raw.is_null() {
                runtime_request.payload.clone()
            } else {
                request.control.raw.clone()
            };
            let (sender, receiver) = oneshot::channel();
            pending.lock().await.insert(
                request_id.clone(),
                PendingResponse::Mcp {
                    sender,
                    request: runtime_request.clone(),
                    native_request_id: native_request_id.clone(),
                },
            );
            let notice = RequestNotice {
                request: runtime_request,
                source: PERMISSION_SOURCE,
                raw,
                native_request_id,
            };
            if tx.send(notice).await.is_err() {
                pending.lock().await.remove(&request_id);
                return Ok(ElicitationResult::cancel());
            }
            // No timeout: a sign-in link can take a while, and a cancel,
            // interrupt or close aborts this wait.
            Ok(match receiver.await {
                Ok(response) => elicitation_result(response, mode),
                Err(_) => ElicitationResult::cancel(),
            })
        })
    });
    options.elicitation_callback = Some(callback);
}

fn elicitation_mode(request: &ElicitationRequest) -> &'static str {
    match request.mode.as_deref() {
        Some("url") => "url",
        Some("form") => "form",
        _ if request.url.is_some() => "url",
        _ => "form",
    }
}

fn elicitation_payload(request: &ElicitationRequest, mode: &str) -> Value {
    let title = request
        .title
        .clone()
        .or_else(|| request.display_name.clone())
        .unwrap_or_else(|| format!("MCP server {} needs input", request.server_name));
    compact_nulls(json!({
        "requestType": RequestKind::McpElicitationApproval,
        "serverName": request.server_name,
        "message": request.message,
        "mode": mode,
        "requestedSchema": request.requested_schema,
        "url": request.url,
        "elicitationId": request.elicitation_id,
        "title": title,
        "displayName": request.display_name,
        "description": request.description,
    }))
}

/// The runtime's answer for the CLI. An accept without content is a
/// confirmation: a form gets empty content, a link none.
fn elicitation_result(response: RuntimeResponse, mode: &str) -> ElicitationResult {
    match response {
        RuntimeResponse::Elicitation {
            action, content, ..
        } => match action {
            ElicitationAction::Accept => match content {
                Some(Value::Object(content)) => ElicitationResult::accept(Some(content)),
                _ if mode == "url" => ElicitationResult::accept(None),
                _ => ElicitationResult::accept(Some(Map::new())),
            },
            ElicitationAction::Decline => ElicitationResult::decline(),
            ElicitationAction::Cancel => ElicitationResult::cancel(),
        },
        _ => ElicitationResult::cancel(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alera_provider_protocol::ElicitationAction;

    fn request(mode: Option<&str>, url: Option<&str>) -> ElicitationRequest {
        ElicitationRequest {
            server_name: "github".into(),
            message: "Who?".into(),
            mode: mode.map(str::to_owned),
            url: url.map(str::to_owned),
            elicitation_id: None,
            requested_schema: None,
            title: None,
            display_name: None,
            description: None,
            control: Default::default(),
        }
    }

    fn answer(action: ElicitationAction, content: Option<Value>) -> RuntimeResponse {
        RuntimeResponse::Elicitation {
            request_id: RequestId::from("r".to_owned()),
            action,
            content,
        }
    }

    #[test]
    fn a_confirmation_accept_fits_its_mode() {
        let accept = |mode| elicitation_result(answer(ElicitationAction::Accept, None), mode);
        assert_eq!(accept("form"), ElicitationResult::accept(Some(Map::new())));
        assert_eq!(accept("url"), ElicitationResult::accept(None));
        let filled = elicitation_result(
            answer(ElicitationAction::Accept, Some(json!({"name": "x"}))),
            "form",
        );
        assert_eq!(filled.content.unwrap()["name"], "x");
        assert_eq!(
            elicitation_result(answer(ElicitationAction::Decline, None), "form"),
            ElicitationResult::decline()
        );
    }

    #[test]
    fn the_mode_and_title_have_fallbacks() {
        assert_eq!(elicitation_mode(&request(None, Some("https://x"))), "url");
        assert_eq!(elicitation_mode(&request(None, None)), "form");
        let payload = elicitation_payload(&request(None, None), "form");
        assert_eq!(payload["title"], "MCP server github needs input");
        assert!(payload.get("url").is_none());
    }
}
