//! Who answers a task's open input: its agent parent, for questions routed
//! to it as messages, or a person. Kept in `launchOptions.inputOwner`
//! without a revision bump, like `parentStopped`.

use anyhow::Result;
use serde_json::Value;

use super::super::chat_orchestration_models::{
    ChatOrchestrationTask, INPUT_OWNER_KEY, INPUT_OWNER_PARENT,
};
use super::super::chat_orchestration_rows::require_id;
use super::super::RuntimeStore;

impl ChatOrchestrationTask {
    /// Whether the task's open input is the agent parent's to answer.
    pub fn input_owned_by_parent(&self) -> bool {
        self.launch_options
            .as_ref()
            .and_then(|options| options.get(INPUT_OWNER_KEY))
            .and_then(Value::as_str)
            == Some(INPUT_OWNER_PARENT)
    }
}

impl RuntimeStore {
    pub async fn set_chat_orchestration_input_owner(
        &self,
        task_id: &str,
        owner: &str,
    ) -> Result<()> {
        require_id("taskId", task_id)?;
        sqlx::query(
            "UPDATE chatOrchestrationTasks SET launchOptionsJson = \
             json_set(COALESCE(launchOptionsJson, '{}'), '$.inputOwner', ?) WHERE taskId = ?",
        )
        .bind(owner)
        .bind(task_id)
        .execute(self.pool())
        .await?;
        Ok(())
    }
}
