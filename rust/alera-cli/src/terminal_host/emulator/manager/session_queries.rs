use super::EmulatorManager;

impl EmulatorManager {
    pub fn session_scopes(&self) -> Vec<(String, String)> {
        self.sessions
            .values()
            .map(|session| (session.tab_id.clone(), session.workspace_id.clone()))
            .collect()
    }

    pub fn tab_ids_for_workspace(&self, workspace_id: &str) -> Vec<String> {
        self.sessions
            .values()
            .filter(|session| session.workspace_id == workspace_id)
            .map(|session| session.tab_id.clone())
            .collect()
    }
}
