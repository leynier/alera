use super::{ServerActor, ServerCommand};

impl ServerActor {
    pub(super) async fn handle_codex_command(&mut self, command: ServerCommand) {
        match command {
            ServerCommand::CodexForkCreated { job, result } => {
                self.finish_codex_fork_created(*job, result).await
            }
            ServerCommand::CodexForkProjected { job, result } => {
                self.finish_codex_fork_projected(*job, result).await
            }
            ServerCommand::CodexQueueStartupFinished { job, result } => {
                self.finish_codex_queue_startup(*job, result).await;
            }
            ServerCommand::CodexHistoryScanFinished { job, result } => {
                self.finish_codex_history_scan(*job, result).await;
            }
            ServerCommand::CodexQueueDelivered {
                tab_id,
                thread_id,
                message_id,
                result,
            } => {
                if let Err(error) = self
                    .finish_codex_queue_delivery(&tab_id, &thread_id, &message_id, result)
                    .await
                {
                    tracing::warn!(tab_id, "Codex delivery completion failed: {error}");
                }
            }
            ServerCommand::CodexQueueAdvance { tab_id } => self.advance_codex_queue(&tab_id).await,
            ServerCommand::CodexEditFinished {
                tab_id,
                operation_id,
                result,
            } => {
                self.finish_codex_history_edit(&tab_id, &operation_id, result)
                    .await
            }
            ServerCommand::CodexMessage { message } => self.handle_codex_message(message).await,
            ServerCommand::CodexProcessExited { reason } => {
                self.handle_codex_process_exited(reason).await
            }
            ServerCommand::CodexMalformed { reason } => self.handle_codex_malformed(reason),
            ServerCommand::CodexPresenceTick => self.handle_codex_presence_tick(),
            ServerCommand::CodexFlush { tab_id } => self.handle_codex_flush(&tab_id).await,
            ServerCommand::CodexAutoResolve {
                tab_id,
                thread_id,
                request_id,
                server_instance,
            } => {
                self.handle_codex_auto_resolve(&tab_id, &thread_id, request_id, server_instance)
                    .await
            }
            _ => unreachable!("non-Codex command routed to Codex handler"),
        }
    }
}
