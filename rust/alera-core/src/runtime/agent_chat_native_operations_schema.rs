use anyhow::Result;

use crate::runtime::RuntimeStore;

impl RuntimeStore {
    pub(in crate::runtime) async fn migrate_agent_chat_native_operations(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        for statement in [
            "CREATE TABLE IF NOT EXISTS agentChatNativeOperations (
                operationId TEXT PRIMARY KEY,
                chatId TEXT NOT NULL,
                generation INTEGER NOT NULL,
                baseCursor INTEGER NOT NULL,
                nativeThreadId TEXT NOT NULL,
                processEpoch TEXT NOT NULL,
                kind TEXT NOT NULL,
                turnId TEXT NOT NULL,
                boundaryJson TEXT NOT NULL,
                actor TEXT NOT NULL,
                callerScope TEXT NOT NULL,
                verb TEXT NOT NULL,
                requestId TEXT NOT NULL,
                digest TEXT NOT NULL,
                state TEXT NOT NULL CHECK(state IN ('prepared','executing','acknowledged','uncertain','cancelled','completed','reconciled')),
                revision INTEGER NOT NULL CHECK(revision >= 1),
                ackJson TEXT,
                resultJson TEXT,
                evidenceJson TEXT
            )",
            "CREATE UNIQUE INDEX IF NOT EXISTS agentChatNativeOperationsReceiptIdx \
             ON agentChatNativeOperations(callerScope, verb, requestId)",
            "CREATE UNIQUE INDEX IF NOT EXISTS agentChatNativeOperationsActiveIdx \
             ON agentChatNativeOperations(chatId) WHERE state IN ('prepared','executing','acknowledged','uncertain')",
            "CREATE INDEX IF NOT EXISTS agentChatNativeOperationsRecoveryIdx \
             ON agentChatNativeOperations(state, operationId)",
            "CREATE INDEX IF NOT EXISTS agentChatItemsTurnIdx ON agentChatItems(chatId, turnId, seq)",
        ] {
            sqlx::query(statement).execute(&mut *tx).await?;
        }
        for statement in [
            "CREATE TRIGGER IF NOT EXISTS agentChatNativeOperationBlocksDeletion BEFORE DELETE ON agentChatSessions \
             WHEN EXISTS(SELECT 1 FROM agentChatNativeOperations WHERE chatId = OLD.chatId \
             AND state IN ('prepared','executing','acknowledged','uncertain')) \
             BEGIN SELECT RAISE(ABORT, 'native operation requires reconciliation'); END",
            "CREATE TRIGGER IF NOT EXISTS agentChatNativeOperationBlocksArchive BEFORE UPDATE OF archived ON agentChatSessions \
             WHEN NEW.archived = 1 AND EXISTS(SELECT 1 FROM agentChatNativeOperations WHERE chatId = OLD.chatId \
             AND state IN ('prepared','executing','acknowledged','uncertain')) \
             BEGIN SELECT RAISE(ABORT, 'native operation requires reconciliation'); END",
            "CREATE TRIGGER IF NOT EXISTS agentChatNativeOperationReservesReceipt BEFORE INSERT ON agentChatReceipts \
             WHEN EXISTS(SELECT 1 FROM agentChatNativeOperations WHERE state IN ('prepared','executing','acknowledged','uncertain') \
             AND json_array(callerScope,verb) = NEW.callerScope AND requestId = NEW.requestId) \
             BEGIN SELECT RAISE(ABORT, 'native operation receipt requires atomic completion'); END",
            "CREATE TRIGGER IF NOT EXISTS agentChatNativeOperationBlocksContextChange \
             BEFORE UPDATE OF provider,providerInstanceId,generation,nativeThreadId ON agentChatSessions \
             WHEN (OLD.provider IS NOT NEW.provider OR OLD.providerInstanceId IS NOT NEW.providerInstanceId \
             OR OLD.generation IS NOT NEW.generation OR OLD.nativeThreadId IS NOT NEW.nativeThreadId) \
             AND EXISTS(SELECT 1 FROM agentChatNativeOperations WHERE chatId = OLD.chatId \
             AND state IN ('prepared','executing','acknowledged','uncertain')) \
             BEGIN SELECT RAISE(ABORT, 'native provider context is frozen'); END",
        ] {
            crate::runtime::schema_object_replacement::replace_schema_object(&mut tx, statement).await?;
        }
        tx.commit().await?;
        Ok(())
    }
}
