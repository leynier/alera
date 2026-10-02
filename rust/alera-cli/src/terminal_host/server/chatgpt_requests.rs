use super::{chatgpt_inference, chatgpt_session, ClientKind, ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::{json, Value};

impl ServerActor {
    pub(super) fn start_chatgpt_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<()> {
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, verb)?;
        if !self
            .clients
            .get(&client_id)
            .is_some_and(|client| client.kind == ClientKind::Local)
        {
            return Err(HostError::state(
                "ChatGPT account requests require a local client.",
            ));
        }
        let inbox = self.inbox.clone();
        let verb = verb.to_string();
        let id = payload
            .get("clientId")
            .and_then(Value::as_str)
            .map(str::to_string);
        tokio::spawn(async move {
            let result = async {
                let session = chatgpt_session::session()?;
                match verb.as_str() {
                    "aiAssist.chatgpt.status" => session.status().await,
                    "aiAssist.chatgpt.signIn" => session.start(id.as_deref()).await,
                    "aiAssist.chatgpt.cancel" => session.cancel().await,
                    "aiAssist.chatgpt.acknowledgePlan" => session.acknowledge_plan().await,
                    "aiAssist.chatgpt.select" => {
                        session
                            .select(
                                id.as_deref()
                                    .ok_or_else(|| HostError::format("clientId is required."))?,
                            )
                            .await
                    }
                    "aiAssist.chatgpt.signOut" => {
                        session
                            .sign_out(
                                id.as_deref()
                                    .ok_or_else(|| HostError::format("clientId is required."))?,
                            )
                            .await
                    }
                    "aiAssist.chatgpt.models" => chatgpt_inference::models().await,
                    _ => Ok(json!({})),
                }
            }
            .await;
            let _ = inbox
                .send_wait(ServerCommand::AiAssistFinished {
                    client_id,
                    request_id,
                    result,
                })
                .await;
        });
        Ok(())
    }
}
