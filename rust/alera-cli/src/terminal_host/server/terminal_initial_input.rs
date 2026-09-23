use alera_core::runtime::WorkspaceTabRecord;

use super::ServerActor;

impl ServerActor {
    /// Rewrites a launch so the agent reads its prompt from stdin.
    ///
    /// Falls back to the bare launch if script creation fails, preserving a usable agent.
    pub(super) fn stdin_prompt_command(
        &self,
        session_id: &str,
        command: &str,
        prompt: &str,
    ) -> String {
        let Some(directory) = self.setup_script_directory() else {
            tracing::warn!(
                session_id = %session_id,
                "no runtime directory for the agent prompt script; launching without the prompt"
            );
            return command.to_string();
        };
        match crate::agent_prompt_stdin_script::write_agent_prompt_stdin_script(
            &directory, session_id, command, prompt,
        ) {
            Ok(script) => script.command,
            Err(error) => {
                tracing::error!(
                    session_id = %session_id,
                    "failed to write the agent prompt script; launching without the prompt: {error}"
                );
                command.to_string()
            }
        }
    }

    pub(super) async fn clear_initial_command(
        &mut self,
        tab: &WorkspaceTabRecord,
    ) -> Option<WorkspaceTabRecord> {
        let mut next = tab.clone();
        let payload = next.payload.as_object_mut()?;
        payload.remove("initialCommand");
        payload.remove("initialCommandOnce");
        match self.runtime_store.upsert_workspace_tab(next).await {
            Ok(saved) => Some(saved),
            Err(error) => {
                eprintln!(
                    "failed to clear the one-shot initial command of tab {}: {error}",
                    tab.id
                );
                None
            }
        }
    }

    pub(super) async fn clear_initial_prompt(
        &mut self,
        tab: &WorkspaceTabRecord,
    ) -> Option<WorkspaceTabRecord> {
        let mut next = tab.clone();
        let payload = next.payload.as_object_mut()?;
        payload.remove("initialPrompt");
        payload.remove("initialPromptOnce");
        match self.runtime_store.upsert_workspace_tab(next).await {
            Ok(saved) => Some(saved),
            Err(error) => {
                tracing::error!(
                    tab_id = %tab.id,
                    "failed to clear one-shot initial agent prompt: {error}"
                );
                None
            }
        }
    }
}
