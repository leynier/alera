//! `alera chat transfers`: the context transfers recorded in a chat
//! (`chatOrchestration.transfers`, `agentChatTransfersV1`).

use anyhow::Result;
use serde_json::{json, Value};

use crate::chat_orchestration_commands_args::ChatTransfersArgs;
use crate::cli::RuntimeDirArgs;

pub(crate) async fn run(runtime: &RuntimeDirArgs, args: ChatTransfersArgs) -> Result<Value> {
    let chat_id = args
        .chat_id
        .map(|chat_id| chat_id.trim().to_owned())
        .filter(|chat_id| !chat_id.is_empty());
    crate::chat_orchestration_request::request(
        runtime,
        "chatOrchestration.transfers",
        json!({"chatId": chat_id}),
        None,
    )
    .await
}
