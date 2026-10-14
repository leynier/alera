use serde_json::Value;

use std::time::Duration;

use tokio::sync::{mpsc, oneshot};

use crate::terminal_host::host_error::HostResult;

use super::super::commands::{CallerCtx, ChatOp, SendInput};
use super::AgentChatRuntime;

impl AgentChatRuntime {
    pub(crate) async fn send(
        &self,
        chat_id: &str,
        input: SendInput,
        ctx: CallerCtx,
    ) -> HostResult<Value> {
        self.command(chat_id, ChatOp::Send(input), ctx, None).await
    }

    pub(crate) async fn snapshot(&self, chat_id: &str) -> HostResult<Value> {
        self.command(chat_id, ChatOp::Snapshot, CallerCtx::runtime(), None)
            .await
    }

    pub(crate) async fn shutdown(&self) {
        let senders: Vec<mpsc::Sender<super::super::commands::ChatEnvelope>> = self
            .inner
            .sessions
            .lock()
            .unwrap()
            .drain()
            .map(|(_, sender)| sender)
            .collect();
        let closes = senders.into_iter().map(|sender| async move {
            let (reply, response) = oneshot::channel();
            let envelope = super::super::commands::ChatEnvelope {
                op: ChatOp::Shutdown,
                ctx: CallerCtx::runtime(),
                receipt_key: None,
                reply,
            };
            if sender.send(envelope).await.is_ok() {
                let _ = response.await;
            }
        });
        let _ = tokio::time::timeout(
            Duration::from_secs(10),
            futures_util::future::join_all(closes),
        )
        .await;
    }
}
