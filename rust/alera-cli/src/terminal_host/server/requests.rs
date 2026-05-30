use serde_json::{json, Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{
    decode_bytes, error_response, int_or, ok_response, require_object, TerminalHostConfig,
    TerminalHostLaunch, PROTOCOL_VERSION,
};
use crate::terminal_host::session::Session;

use super::{ServerActor, ServerCommand};

impl ServerActor {
    /// Parse and dispatch one client line, then write the response, faithfully
    /// reproducing the Dart `_handleLine` control flow (including which failures
    /// drop the connection versus return an error response).
    pub(super) async fn handle_line(&mut self, client_id: u64, line: String) {
        let decoded: Value = match serde_json::from_str(&line) {
            Ok(value) => value,
            // jsonDecode threw: no request id is available, so drop the client.
            Err(_) => {
                self.dispose_client(client_id).await;
                return;
            }
        };
        let Some(obj) = decoded.as_object() else {
            self.dispose_client(client_id).await;
            return;
        };
        let request_id = obj.get("id").and_then(Value::as_i64);
        let outcome: HostResult<Value> = match extract_request(obj) {
            Ok((request_type, payload)) => {
                self.handle_request(client_id, &request_type, &payload)
                    .await
            }
            Err(error) => Err(error),
        };
        match outcome {
            Ok(payload) => {
                if let Some(id) = request_id {
                    self.client_write(client_id, ok_response(id, payload));
                }
            }
            Err(error) => {
                if let Some(id) = request_id {
                    self.client_write(client_id, error_response(id, &error));
                } else {
                    self.dispose_client(client_id).await;
                }
            }
        }
    }

    async fn handle_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        match request_type {
            "hello" => {
                let version_ok = payload.get("protocolVersion") == Some(&json!(PROTOCOL_VERSION));
                let token_ok =
                    payload.get("token").and_then(Value::as_str) == Some(self.token.as_str());
                if !version_ok || !token_ok {
                    return Err(HostError::state("Terminal host authentication failed."));
                }
                if let Some(client) = self.clients.get_mut(&client_id) {
                    client.authenticated = true;
                }
                self.cancel_shutdown_timer();
                Ok(json!({}))
            }
            "configure" => {
                self.require_auth(client_id)?;
                let config = TerminalHostConfig::from_json(payload)?;
                self.apply_config(config).await;
                Ok(json!({}))
            }
            "createOrAttach" => {
                self.require_auth(client_id)?;
                self.create_or_attach(client_id, payload).await
            }
            "write" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                let bytes = decode_bytes(payload.get("dataBase64"))?;
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.write(&bytes);
                }
                Ok(json!({}))
            }
            "resize" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                let cols = int_or(payload, "cols", 80);
                let rows = int_or(payload, "rows", 24);
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.resize(cols as u16, rows as u16);
                }
                Ok(json!({}))
            }
            "detach" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.detach(client_id);
                }
                self.immediate_checkpoint(&session_id).await;
                Ok(json!({}))
            }
            "terminate" => {
                self.require_auth(client_id)?;
                let session_id = self.require_session(payload)?;
                let store = self.store.clone();
                if let Some(mut session) = self.sessions.remove(&session_id) {
                    session.terminate(true, &store).await;
                }
                self.schedule_shutdown_if_idle();
                Ok(json!({}))
            }
            other => Err(HostError::state(format!(
                "Unknown terminal host request: {other}"
            ))),
        }
    }

    async fn create_or_attach(&mut self, client_id: u64, payload: &Value) -> HostResult<Value> {
        let session_id = require_string(payload, "sessionId")?;
        let workspace_id = require_string(payload, "workspaceId")?;
        let tab_id = require_string(payload, "tabId")?;
        let working_directory = require_string(payload, "workingDirectory")?;

        if self.sessions.contains_key(&session_id) {
            let session = self.sessions.get_mut(&session_id).expect("just checked");
            session.attach(client_id);
            return Ok(session.attachment_payload(false));
        }

        let store = self.store.clone();
        let max_bytes = self.config.scrollback_bytes as usize;
        if let Some(restored) = Session::restore_exited(
            session_id.clone(),
            workspace_id.clone(),
            tab_id.clone(),
            &store,
            max_bytes,
        )
        .await
        {
            self.sessions.insert(session_id.clone(), restored);
            if let Some(session) = self.sessions.get_mut(&session_id) {
                session.set_max_bytes(max_bytes);
            }
            self.immediate_checkpoint(&session_id).await;
            let session = self.sessions.get_mut(&session_id).expect("just inserted");
            session.attach(client_id);
            return Ok(session.attachment_payload(false));
        }

        let launch = TerminalHostLaunch::from_json(&Value::Object(
            require_object(payload.get("launch"), "launch")?.clone(),
        ))?;
        let cols = int_or(payload, "cols", 80) as u16;
        let rows = int_or(payload, "rows", 24) as u16;
        let inbox = self.inbox.clone();
        let reader_session_id = session_id.clone();
        let session = Session::start(
            session_id.clone(),
            workspace_id,
            tab_id,
            working_directory,
            &launch,
            cols,
            rows,
            max_bytes,
            &store,
            move |event| {
                let _ = inbox.send(ServerCommand::Pty {
                    session_id: reader_session_id.clone(),
                    event,
                });
            },
        )
        .await?;
        self.sessions.insert(session_id.clone(), session);
        let session = self.sessions.get_mut(&session_id).expect("just inserted");
        session.attach(client_id);
        Ok(session.attachment_payload(true))
    }
}

/// Validate the request envelope, matching the Dart ordering: the payload-object
/// check precedes the id/type validity check.
fn extract_request(obj: &Map<String, Value>) -> HostResult<(String, Value)> {
    let payload = match obj.get("payload") {
        Some(value @ Value::Object(_)) => value.clone(),
        _ => return Err(HostError::format("request payload must be a JSON object.")),
    };
    let id_ok = obj.get("id").and_then(Value::as_i64).is_some();
    let request_type = obj.get("type").and_then(Value::as_str);
    match (id_ok, request_type) {
        (true, Some(request_type)) => Ok((request_type.to_string(), payload)),
        _ => Err(HostError::format("Terminal host request is malformed.")),
    }
}

fn require_string(payload: &Value, key: &str) -> HostResult<String> {
    match payload.get(key) {
        Some(Value::String(value)) => Ok(value.clone()),
        _ => Err(HostError::format(
            "createOrAttach requires session metadata.",
        )),
    }
}
