#[cfg(unix)]
use std::collections::hash_map::DefaultHasher;
#[cfg(unix)]
use std::hash::{Hash, Hasher};
use std::path::Path;
#[cfg(unix)]
use std::path::PathBuf;

#[cfg(any(unix, test))]
use crate::terminal_host::server::ServerCommand;
use crate::terminal_host::server::ServerInbox;
#[cfg(any(unix, test))]
use serde_json::{json, Value};

#[cfg(any(unix, test))]
use super::AgentHookEvent;

#[cfg(unix)]
const MAX_REQUEST_BYTES: u64 = 16 * 1024;

// Herdr is a Unix-socket protocol; Windows has no fx receiver to answer.
#[cfg(unix)]
pub fn fx_herdr_socket_path(runtime_dir: &Path) -> PathBuf {
    let direct = runtime_dir.join("fx-herdr.sock");
    if direct.to_string_lossy().len() <= 90 {
        return direct;
    }
    let mut hasher = DefaultHasher::new();
    runtime_dir.hash(&mut hasher);
    std::env::temp_dir().join(format!("alera-fx-herdr-{:016x}.sock", hasher.finish()))
}

#[cfg(unix)]
pub async fn start_fx_herdr_receiver(runtime_dir: &Path, inbox: ServerInbox) -> anyhow::Result<()> {
    use std::os::unix::fs::{FileTypeExt, PermissionsExt};
    use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
    use tokio::net::UnixListener;

    let socket_path = fx_herdr_socket_path(runtime_dir);
    if let Ok(metadata) = std::fs::symlink_metadata(&socket_path) {
        if !metadata.file_type().is_socket() {
            anyhow::bail!(
                "fx Herdr path is occupied by a non-socket: {}",
                socket_path.display()
            );
        }
        std::fs::remove_file(&socket_path)?;
    }
    let listener = UnixListener::bind(&socket_path)?;
    std::fs::set_permissions(&socket_path, std::fs::Permissions::from_mode(0o600))?;
    tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                break;
            };
            let inbox = inbox.clone();
            tokio::spawn(async move {
                let mut reader = BufReader::new(stream);
                let mut line = String::new();
                let read = (&mut reader)
                    .take(MAX_REQUEST_BYTES)
                    .read_line(&mut line)
                    .await;
                let response = match read {
                    Ok(bytes) if bytes > 0 => fx_herdr_response(&line, &inbox),
                    _ => json!({"id": Value::Null, "error": "invalid request"}),
                };
                if let Ok(mut encoded) = serde_json::to_vec(&response) {
                    encoded.push(b'\n');
                    let _ = reader.get_mut().write_all(&encoded).await;
                }
            });
        }
    });
    Ok(())
}

#[cfg(not(unix))]
pub async fn start_fx_herdr_receiver(
    _runtime_dir: &Path,
    _inbox: ServerInbox,
) -> anyhow::Result<()> {
    Ok(())
}

#[cfg(any(unix, test))]
fn fx_herdr_response(line: &str, inbox: &ServerInbox) -> Value {
    let Ok(request) = serde_json::from_str::<Value>(line) else {
        return json!({"id": Value::Null, "error": "invalid request"});
    };
    let id = request.get("id").cloned().unwrap_or(Value::Null);
    let method = request.get("method").and_then(Value::as_str);
    let params = request.get("params").and_then(Value::as_object);
    if let (Some(method), Some(params)) = (method, params) {
        if let Some(event) = fx_event(method, params) {
            let _ = inbox.send(ServerCommand::AgentHookEvent {
                event,
                relayed: false,
            });
        }
    }
    json!({"id": id, "result": {}})
}

#[cfg(any(unix, test))]
fn fx_event(method: &str, params: &serde_json::Map<String, Value>) -> Option<AgentHookEvent> {
    let pane_id = non_blank(params.get("pane_id"))?;
    let from_fx = || {
        non_blank(params.get("source")) == Some("custom:fx")
            && non_blank(params.get("agent")) == Some("fx")
    };
    // fx reports its conversation id at startup, before any prompt, and the
    // session is already saved then, so `fx --resume <id>` works from there.
    let session_id = non_blank(params.get("agent_session_id"));
    match method {
        "pane.report_agent_session" if from_fx() => Some(AgentHookEvent {
            terminal_session_id: pane_id.to_string(),
            workspace_id: String::new(),
            tab_id: String::new(),
            agent_type: "fx".to_string(),
            payload: json!({ "session_id": session_id? }),
            event_name: Some("SessionReport".to_string()),
        }),
        "pane.report_agent" if from_fx() => {
            let state = non_blank(params.get("state"))?;
            let event_name = match state {
                "idle" => "Idle",
                "working" => "Working",
                "blocked" => "Blocked",
                _ => return None,
            };
            let mut payload = json!({
                "state": state,
                "customStatus": non_blank(params.get("message"))
                    .or_else(|| non_blank(params.get("custom_status"))),
            });
            if let Some(session_id) = session_id {
                payload["session_id"] = json!(session_id);
            }
            Some(AgentHookEvent {
                terminal_session_id: pane_id.to_string(),
                workspace_id: String::new(),
                tab_id: String::new(),
                agent_type: "fx".to_string(),
                payload,
                event_name: Some(event_name.to_string()),
            })
        }
        "pane.clear_agent_authority" if non_blank(params.get("source"))? == "custom:fx" => {
            Some(AgentHookEvent {
                terminal_session_id: pane_id.to_string(),
                workspace_id: String::new(),
                tab_id: String::new(),
                agent_type: "fx".to_string(),
                payload: json!({}),
                event_name: Some("SessionEnd".to_string()),
            })
        }
        _ => None,
    }
}

#[cfg(any(unix, test))]
fn non_blank(value: Option<&Value>) -> Option<&str> {
    value?
        .as_str()
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {

    use super::*;

    #[test]
    fn report_agent_maps_fx_states_to_hook_events() {
        let (inbox, mut receiver) = ServerInbox::channel();
        let response = fx_herdr_response(
            r#"{"id":"7","method":"pane.report_agent","params":{"pane_id":"session-1","source":"custom:fx","agent":"fx","state":"blocked","custom_status":"permission"}}"#,
            &inbox,
        );
        assert_eq!(response, json!({"id": "7", "result": {}}));
        let command = receiver.try_recv().expect("fx event");
        let ServerCommand::AgentHookEvent { event, .. } = command else {
            panic!("unexpected server command");
        };
        assert_eq!(event.terminal_session_id, "session-1");
        assert_eq!(event.agent_type, "fx");
        assert_eq!(event.event_name.as_deref(), Some("Blocked"));
        assert_eq!(event.payload["customStatus"], "permission");
    }

    /// The exact line fx 0.0.11 sends at startup, captured from a real run.
    #[test]
    fn a_session_report_carries_the_resumable_fx_session_id() {
        let (inbox, mut receiver) = ServerInbox::channel();
        fx_herdr_response(
            r#"{"id":"1","method":"pane.report_agent_session","params":{"pane_id":"pane-1","source":"custom:fx","agent":"fx","agent_session_id":"3zfNDCfnTsuI"}}"#,
            &inbox,
        );
        let ServerCommand::AgentHookEvent { event, .. } = receiver.try_recv().expect("fx event")
        else {
            panic!("unexpected server command");
        };
        assert_eq!(event.event_name.as_deref(), Some("SessionReport"));
        assert_eq!(
            crate::terminal_host::orchestration::agent_session_resume::native_session_id(
                &event.payload
            ),
            Some("3zfNDCfnTsuI")
        );
        assert!(crate::agent_status::normalize_hook_event(&event, None).is_none());
    }

    #[test]
    fn clear_authority_closes_the_fx_session() {
        let (inbox, mut receiver) = ServerInbox::channel();
        fx_herdr_response(
            r#"{"id":"8","method":"pane.clear_agent_authority","params":{"pane_id":"session-1","source":"custom:fx"}}"#,
            &inbox,
        );
        let ServerCommand::AgentHookEvent { event, .. } = receiver.try_recv().expect("fx event")
        else {
            panic!("unexpected server command");
        };
        assert_eq!(event.event_name.as_deref(), Some("SessionEnd"));
    }

    #[test]
    fn foreign_herdr_reports_are_ignored() {
        let (inbox, mut receiver) = ServerInbox::channel();
        fx_herdr_response(
            r#"{"id":"9","method":"pane.report_agent","params":{"pane_id":"session-1","source":"custom:other","agent":"fx","state":"working"}}"#,
            &inbox,
        );
        assert!(receiver.try_recv().is_err());
    }
}
