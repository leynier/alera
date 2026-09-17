//! `alera workspace section` commands.
//!
//! Prefer a live host RPC so connected apps refresh from `workspaceSectionsChanged`.
//! Fall back to `RuntimeStore` when no host is connected, matching `workspace pin`.

use std::path::Path;

use alera_core::runtime::{RuntimeStore, WorkspaceSection};
use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

use crate::cli::{
    IdArgs, RuntimeDirArgs, WorkspaceSectionAction, WorkspaceSectionCommand,
    WorkspaceSectionCreateArgs, WorkspaceSectionWorkspaceArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;

pub async fn run(
    runtime: RuntimeDirArgs,
    command: WorkspaceSectionCommand,
    json_output: bool,
) -> i32 {
    match execute(&crate::runtime_dir(&runtime), command.action).await {
        Ok((value, message)) => {
            crate::print_value(&value, json_output, &message);
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn execute(runtime_dir: &Path, action: WorkspaceSectionAction) -> Result<(Value, String)> {
    let mut backend = Backend::open(runtime_dir).await?;
    match action {
        WorkspaceSectionAction::List => {
            let items = backend.list().await?;
            Ok((
                json!({ "kind": "workspaceSections", "items": items, "filters": {} }),
                "workspace sections listed".to_string(),
            ))
        }
        WorkspaceSectionAction::Create(WorkspaceSectionCreateArgs { name, workspace_id }) => {
            let section = backend.create(&name, &workspace_id).await?;
            Ok((json!(section), "workspace section created".to_string()))
        }
        WorkspaceSectionAction::Set(args) => {
            let payload = assign(
                &mut backend,
                &args.workspace_id,
                args.section,
                args.section_id,
            )
            .await?;
            Ok((payload, "workspace section assigned".to_string()))
        }
        WorkspaceSectionAction::Clear(WorkspaceSectionWorkspaceArgs { workspace_id }) => {
            backend.set(&workspace_id, None).await?;
            Ok((
                set_for_workspace_payload(&workspace_id, None),
                "workspace section cleared".to_string(),
            ))
        }
        WorkspaceSectionAction::Remove(IdArgs { id }) => {
            backend.remove(&id).await?;
            Ok((json!({ "id": id }), "workspace section removed".to_string()))
        }
    }
}

async fn assign(
    backend: &mut Backend,
    workspace_id: &str,
    section: Option<String>,
    section_id: Option<String>,
) -> Result<Value> {
    let section_id =
        resolve_section_ref(backend, section.as_deref(), section_id.as_deref()).await?;
    backend.set(workspace_id, Some(&section_id)).await?;
    Ok(set_for_workspace_payload(workspace_id, Some(&section_id)))
}

async fn resolve_section_ref(
    backend: &mut Backend,
    name: Option<&str>,
    section_id: Option<&str>,
) -> Result<String> {
    match (nonempty(name), nonempty(section_id)) {
        (None, None) => bail!("Pass --section or --section-id."),
        (Some(_), Some(_)) => bail!("Pass only one of --section or --section-id."),
        (None, Some(id)) => Ok(id.to_string()),
        (Some(name), None) => {
            let sections = backend.list().await?;
            resolve_section_id(&sections, name)
        }
    }
}

pub(crate) async fn resolve_optional_section_id(
    client: &mut RuntimeHostRpcClient,
    name: Option<&str>,
    section_id: Option<&str>,
) -> Result<Option<String>> {
    match (nonempty(name), nonempty(section_id)) {
        (None, None) => Ok(None),
        (Some(_), Some(_)) => bail!("Pass only one of --section or --section-id."),
        (None, Some(id)) => Ok(Some(id.to_string())),
        (Some(name), None) => {
            let sections: Vec<WorkspaceSection> =
                client.request("workspaceSection.list", &json!({})).await?;
            Ok(Some(resolve_section_id(&sections, name)?))
        }
    }
}

pub(crate) async fn set_for_workspace_on_client(
    client: &mut RuntimeHostRpcClient,
    workspace_id: &str,
    section_id: Option<&str>,
) -> Result<()> {
    client
        .request_value(
            "workspaceSection.setForWorkspace",
            &set_for_workspace_payload(workspace_id, section_id),
        )
        .await?;
    Ok(())
}

pub(crate) fn created_workspace_id(created: &Value) -> Result<&str> {
    created
        .get("workspace")
        .and_then(|workspace| workspace.get("id"))
        .and_then(Value::as_str)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| anyhow!("workspace create returned no workspace id"))
}

pub(crate) fn resolve_section_id(sections: &[WorkspaceSection], name: &str) -> Result<String> {
    let needle = name.trim();
    if needle.is_empty() {
        bail!("Section name cannot be empty.");
    }
    let needle_key = needle.to_lowercase();
    let matches: Vec<&WorkspaceSection> = sections
        .iter()
        .filter(|section| section.name.to_lowercase() == needle_key)
        .collect();
    match matches.as_slice() {
        [section] => Ok(section.id.clone()),
        [] => bail!("No workspace section named {needle}."),
        many => bail!(
            "Workspace section name {needle} is ambiguous ({} matches). Use --section-id.",
            many.len()
        ),
    }
}

pub(crate) fn set_for_workspace_payload(workspace_id: &str, section_id: Option<&str>) -> Value {
    json!({
        "workspaceId": workspace_id,
        "sectionId": section_id,
    })
}

fn nonempty(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
}

enum Backend {
    Host(RuntimeHostRpcClient),
    Store(RuntimeStore),
}

impl Backend {
    async fn open(runtime_dir: &Path) -> Result<Self> {
        if let Some(client) = RuntimeHostRpcClient::connect(runtime_dir).await? {
            return Ok(Self::Host(client));
        }
        Ok(Self::Store(RuntimeStore::open(runtime_dir).await?))
    }

    async fn list(&mut self) -> Result<Vec<WorkspaceSection>> {
        match self {
            Self::Host(client) => client.request("workspaceSection.list", &json!({})).await,
            Self::Store(store) => store.list_workspace_sections().await,
        }
    }

    async fn create(&mut self, name: &str, workspace_id: &str) -> Result<WorkspaceSection> {
        match self {
            Self::Host(client) => {
                client
                    .request(
                        "workspaceSection.create",
                        &json!({ "name": name, "workspaceId": workspace_id }),
                    )
                    .await
            }
            Self::Store(store) => store.create_workspace_section(name, workspace_id).await,
        }
    }

    async fn set(&mut self, workspace_id: &str, section_id: Option<&str>) -> Result<()> {
        match self {
            Self::Host(client) => {
                client
                    .request_value(
                        "workspaceSection.setForWorkspace",
                        &set_for_workspace_payload(workspace_id, section_id),
                    )
                    .await?;
                Ok(())
            }
            Self::Store(store) => store.set_workspace_section(workspace_id, section_id).await,
        }
    }

    async fn remove(&mut self, id: &str) -> Result<()> {
        match self {
            Self::Host(client) => {
                client
                    .request_value("workspaceSection.remove", &json!({ "id": id }))
                    .await?;
                Ok(())
            }
            Self::Store(store) => store.remove_workspace_section(id).await,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::protocol::{
        PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY, RUNTIME_HOST_WORKSPACE_SECTIONS_CAPABILITY,
    };
    use alera_core::runtime::{
        Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
    };
    use chrono::{TimeZone, Utc};
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

    fn section(id: &str, name: &str) -> WorkspaceSection {
        let now = Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap();
        WorkspaceSection {
            id: id.to_string(),
            name: name.to_string(),
            created_at: now,
            updated_at: now,
        }
    }

    #[test]
    fn resolve_section_id_matches_unique_names_case_insensitively() {
        let sections = vec![section("a", "Alera"), section("b", "Mobile")];
        assert_eq!(resolve_section_id(&sections, "alera").unwrap(), "a");
        assert_eq!(resolve_section_id(&sections, " Alera ").unwrap(), "a");
        assert_eq!(resolve_section_id(&sections, "MOBILE").unwrap(), "b");
    }

    #[test]
    fn resolve_section_id_fails_closed_for_missing_empty_and_ambiguous_names() {
        let sections = vec![section("a", "Alera"), section("b", "alera")];
        assert!(resolve_section_id(&sections, "missing")
            .unwrap_err()
            .to_string()
            .contains("No workspace section named missing"));
        assert!(resolve_section_id(&sections, "  ")
            .unwrap_err()
            .to_string()
            .contains("cannot be empty"));
        assert!(resolve_section_id(&sections, "ALERA")
            .unwrap_err()
            .to_string()
            .contains("ambiguous"));
    }

    #[test]
    fn clear_payload_sends_null_section_id() {
        assert_eq!(
            set_for_workspace_payload("workspace-1", None),
            json!({ "workspaceId": "workspace-1", "sectionId": null })
        );
        assert_eq!(
            set_for_workspace_payload("workspace-1", Some("section-1")),
            json!({ "workspaceId": "workspace-1", "sectionId": "section-1" })
        );
    }

    fn project(id: &str) -> Project {
        let now = Utc::now();
        Project {
            id: id.to_string(),
            name: id.to_string(),
            repo_path: format!("/tmp/{id}"),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        }
    }

    fn workspace(id: &str, project_id: &str) -> Workspace {
        let now = Utc::now();
        Workspace {
            id: id.to_string(),
            instance_id: format!("inst-{id}"),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: project_id.to_string(),
            name: id.to_string(),
            branch: Some("main".to_string()),
            path: format!("/tmp/{project_id}/{id}"),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        }
    }

    async fn seeded_store() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        store.upsert_project(project("p")).await.unwrap();
        store.upsert_workspace(workspace("a", "p")).await.unwrap();
        store.upsert_workspace(workspace("b", "p")).await.unwrap();
        dir
    }

    async fn host_server(
        sequence: Vec<(&'static str, Value, Value)>,
    ) -> (tempfile::TempDir, tokio::task::JoinHandle<()>) {
        let directory = tempfile::tempdir().unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        std::fs::write(
            directory.path().join("host.json"),
            serde_json::to_vec(&json!({
                "protocolVersion": PROTOCOL_VERSION,
                "port": port,
                "token": "fixture-token",
                "runtimeCapabilities": [
                    RUNTIME_HOST_CAPABILITY,
                    RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                    RUNTIME_HOST_WORKSPACE_SECTIONS_CAPABILITY
                ]
            }))
            .unwrap(),
        )
        .unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let (read, mut write) = stream.into_split();
            let mut lines = BufReader::new(read).lines();
            for (expected, payload, response) in
                std::iter::once(("hello", json!({}), json!({}))).chain(sequence)
            {
                let line = lines.next_line().await.unwrap().unwrap();
                let request: Value = serde_json::from_str(&line).unwrap();
                assert_eq!(request["type"], expected);
                if expected != "hello" {
                    assert_eq!(request["payload"], payload);
                }
                let frame = json!({"id": request["id"], "ok": true, "payload": response});
                write
                    .write_all(format!("{frame}\n").as_bytes())
                    .await
                    .unwrap();
            }
        });
        (directory, server)
    }

    #[tokio::test]
    async fn store_backend_is_used_when_no_host_is_connected() {
        let dir = seeded_store().await;
        let mut backend = Backend::open(dir.path()).await.unwrap();
        assert!(matches!(backend, Backend::Store(_)));
        let created = backend.create("Alera", "a").await.unwrap();
        assert_eq!(created.name, "Alera");
        backend.set("b", Some(&created.id)).await.unwrap();
        backend.set("a", None).await.unwrap();
        let listed = backend.list().await.unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].id, created.id);
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        assert_eq!(store.workspace_section_id("a").await.unwrap(), None);
        assert_eq!(
            store.workspace_section_id("b").await.unwrap(),
            Some(created.id)
        );
    }

    #[tokio::test]
    async fn host_backend_prefers_live_rpc_and_sends_null_on_clear() {
        let listed = json!([{
            "id": "sec-alera",
            "name": "Alera",
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z"
        }]);
        let (dir, server) = host_server(vec![
            ("workspaceSection.list", json!({}), listed),
            (
                "workspaceSection.setForWorkspace",
                json!({"workspaceId": "w", "sectionId": "sec-alera"}),
                json!({}),
            ),
            (
                "workspaceSection.setForWorkspace",
                json!({"workspaceId": "w", "sectionId": null}),
                json!({}),
            ),
        ])
        .await;
        let mut backend = Backend::open(dir.path()).await.unwrap();
        assert!(matches!(backend, Backend::Host(_)));
        let sections = backend.list().await.unwrap();
        let section_id = resolve_section_id(&sections, "alera").unwrap();
        assert_eq!(section_id, "sec-alera");
        backend.set("w", Some(&section_id)).await.unwrap();
        backend.set("w", None).await.unwrap();
        drop(backend);
        server.await.unwrap();
    }
}
