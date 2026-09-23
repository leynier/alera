use alera_core::runtime::{RuntimeStore, Workspace, WorkspaceTabRecord};
use anyhow::{bail, Result};
use serde_json::json;

pub(crate) async fn automation_run_id(
    store: &RuntimeStore,
    workspace: &Workspace,
    tab_id: &str,
) -> Result<Option<String>> {
    let Some(tab) = store.find_workspace_tab(tab_id).await? else {
        return Ok(None);
    };
    if tab.payload["automationOwned"] != true {
        return Ok(None);
    }
    let id = tab.payload["automationRunId"]
        .as_str()
        .filter(|id| !id.trim().is_empty())
        .ok_or_else(|| {
            anyhow::anyhow!("Automation terminal ownership is missing its run identity")
        })?;
    let run = store
        .find_automation_run(id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("Automation terminal owner no longer exists"))?;
    // Fresh-tab dispatch persists the owned tab before opening its terminal,
    // then binds the returned terminal identity to the run after launch.
    let launching = run.status == alera_core::runtime::AutomationRunStatus::Dispatching
        && run.tab_id.is_none()
        && tab.created_at >= run.created_at;
    if tab.workspace_id != workspace.id
        || run.workspace_id.as_deref().or_else(|| {
            run.target_identity
                .as_ref()
                .and_then(|identity| identity.workspace_id.as_deref())
        }) != Some(workspace.id.as_str())
        || !(launching
            || (run.owned_tab && run.tab_id.as_deref() == Some(tab_id))
            || run.setup_tab_id.as_deref() == Some(tab_id))
    {
        bail!("Automation terminal does not belong to this task and execution");
    }
    Ok(Some(id.to_string()))
}

pub(crate) async fn register_tab(
    store: &RuntimeStore,
    workspace: &Workspace,
    tab_id: &str,
    session_id: &str,
    automation_run_id: Option<&str>,
) -> Result<()> {
    if automation_run_id.is_some_and(|id| id.trim().is_empty()) {
        bail!("Automation run identity must be nonempty");
    }
    if let Some(mut tab) = store.find_workspace_tab(tab_id).await? {
        if tab.workspace_id != workspace.id
            || tab.kind != "terminal"
            || tab.payload["terminalSessionId"].as_str() != Some(session_id)
        {
            bail!("Remote terminal identity belongs to another tab; no state was replaced");
        }
        if let Some(run_id) = automation_run_id {
            if tab.payload["automationRunId"].as_str() != Some(run_id)
                || tab.payload["automationOwned"] != true
            {
                bail!("Remote terminal ownership changed; an existing tab cannot be adopted by an automation");
            }
        }
        if tab.payload["sshOwnerTerminal"] != true {
            tab.payload["sshOwnerTerminal"] = json!(true);
            store.upsert_workspace_tab(tab).await?;
        }
        return Ok(());
    }
    let now = chrono::Utc::now();
    let mut payload = json!({"terminalSessionId":session_id,"sshOwnerTerminal":true});
    if let Some(run_id) = automation_run_id {
        payload["automationRunId"] = json!(run_id);
        payload["automationOwned"] = json!(true);
    }
    store
        .insert_workspace_tab(WorkspaceTabRecord {
            id: tab_id.into(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".into(),
            title: "Terminal".into(),
            created_at: now,
            updated_at: now,
            payload,
        })
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn fixture() -> (tempfile::TempDir, RuntimeStore, Workspace) {
        let root = tempfile::tempdir().unwrap();
        let folder = root.path().join("folder");
        std::fs::create_dir(&folder).unwrap();
        let store = RuntimeStore::open(&root.path().join("state"))
            .await
            .unwrap();
        let project =
            crate::project_management::register_project(&store, folder.to_str().unwrap(), None)
                .await
                .unwrap()
                .project;
        let workspace = store.list_workspaces(&project.id).await.unwrap().remove(0);
        (root, store, workspace)
    }

    #[tokio::test]
    async fn owner_tabs_retain_automation_identity_after_restart_and_reconnect() {
        let (root, store, workspace) = fixture().await;
        register_tab(&store, &workspace, "owned", "session", Some("run"))
            .await
            .unwrap();
        let reopened = RuntimeStore::open(&root.path().join("state"))
            .await
            .unwrap();
        register_tab(&reopened, &workspace, "owned", "session", Some("run"))
            .await
            .unwrap();
        register_tab(&reopened, &workspace, "owned", "session", None)
            .await
            .unwrap();
        let tab = reopened.find_workspace_tab("owned").await.unwrap().unwrap();
        assert_eq!(tab.payload["automationRunId"], "run");
        assert_eq!(tab.payload["automationOwned"], true);
        assert_eq!(tab.payload["terminalSessionId"], "session");
    }

    #[tokio::test]
    async fn reconnect_never_adopts_user_tabs_or_other_automation_tabs() {
        let (_root, store, workspace) = fixture().await;
        register_tab(&store, &workspace, "user", "session", None)
            .await
            .unwrap();
        let before = store.find_workspace_tab("user").await.unwrap().unwrap();
        assert!(
            register_tab(&store, &workspace, "user", "session", Some("run"))
                .await
                .unwrap_err()
                .to_string()
                .contains("cannot be adopted")
        );
        assert_eq!(
            store
                .find_workspace_tab("user")
                .await
                .unwrap()
                .unwrap()
                .payload,
            before.payload
        );
        register_tab(
            &store,
            &workspace,
            "owned",
            "owned-session",
            Some("original"),
        )
        .await
        .unwrap();
        assert!(register_tab(
            &store,
            &workspace,
            "owned",
            "owned-session",
            Some("replacement")
        )
        .await
        .is_err());
        assert!(register_tab(
            &store,
            &workspace,
            "owned",
            "other-session",
            Some("original")
        )
        .await
        .is_err());
        assert_eq!(
            store
                .find_workspace_tab("owned")
                .await
                .unwrap()
                .unwrap()
                .payload["automationRunId"],
            "original"
        );
    }

    #[tokio::test]
    async fn absent_or_invalid_home_ownership_is_never_forwarded_as_automation() {
        let (_root, store, workspace) = fixture().await;
        register_tab(&store, &workspace, "user", "session", None)
            .await
            .unwrap();
        assert!(automation_run_id(&store, &workspace, "user")
            .await
            .unwrap()
            .is_none());
        assert!(automation_run_id(&store, &workspace, "missing")
            .await
            .unwrap()
            .is_none());
        assert!(
            register_tab(&store, &workspace, "invalid", "session", Some(" "))
                .await
                .is_err()
        );
        assert!(store.find_workspace_tab("invalid").await.unwrap().is_none());
        register_tab(
            &store,
            &workspace,
            "orphan",
            "orphan-session",
            Some("missing-run"),
        )
        .await
        .unwrap();
        assert!(automation_run_id(&store, &workspace, "orphan")
            .await
            .unwrap_err()
            .to_string()
            .contains("owner no longer exists"));
    }
}
