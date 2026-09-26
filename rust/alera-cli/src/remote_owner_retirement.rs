use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

#[derive(Debug, clap::Args)]
pub(crate) struct RemoteOwnerRetirementArgs {
    #[arg(long)]
    pub state_dir: std::path::PathBuf,
    #[arg(long)]
    pub workspace_id: String,
    #[arg(long)]
    pub instance_id: String,
    #[arg(long)]
    pub close_sessions: bool,
    #[arg(long)]
    pub delete_branch: bool,
    #[arg(long)]
    pub automation_cleanup_base64: Option<String>,
    #[arg(long)]
    pub enroll_never_started_base64: Option<String>,
}

pub(crate) async fn run(mut args: RemoteOwnerRetirementArgs) -> Result<Value> {
    if !args.state_dir.is_absolute()
        || args.workspace_id.trim().is_empty()
        || args.instance_id.trim().is_empty()
    {
        bail!("An absolute owner runtime directory and stable workspace and instance identities are required");
    }
    if !args.close_sessions {
        bail!("Pass --close-sessions to confirm stopping only this workspace's processes before retirement");
    }
    let automation_cleanup = parse_cleanup_scope(&args)?;
    args.state_dir = owning_state_dir(&args).await?;
    if let Some(workspace) = alera_core::runtime::RuntimeStore::read_workspace_retirement_receipt(
        &args.state_dir,
        &args.workspace_id,
        &args.instance_id,
    )
    .await?
    {
        if workspace.id != args.workspace_id || workspace.instance_id != args.instance_id {
            bail!("The stored retirement receipt belongs to another task instance");
        }
        return Ok(json!({"version":1, "workspace":workspace, "processClosureVerified":true}));
    }
    // Starting an empty host cannot prove that a previous host's processes exited.
    let capability = if automation_cleanup.is_some() {
        crate::terminal_host::protocol::RUNTIME_HOST_REMOTE_AUTOMATION_CLEANUP_CAPABILITY
    } else {
        crate::terminal_host::protocol::RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY
    };
    let mut connection =
        crate::runtime_host_client::RuntimeHostRpcClient::connect_with_required_capability(
            &args.state_dir,
            capability,
        )
        .await?;
    if let Some(encoded) = &args.enroll_never_started_base64 {
        if connection.is_none() {
            crate::terminal_host::runtime_owner::ensure_no_live_owner(&args.state_dir)?;
        }
        enroll_never_started(&args, encoded).await?;
        if connection.is_none() {
            connection = Some(crate::runtime_host_client::RuntimeHostRpcClient::connect_or_start_with_required_capability(
                &args.state_dir, capability,
            ).await?);
        }
    }
    let mut client = connection.ok_or_else(|| anyhow!("The owner runtime is unavailable. Remote process closure is unverified; task records were preserved."))?;
    let receipt = client
        .request_value(
            "workspace.retirementReceipt",
            &json!({
                "id":args.workspace_id, "instanceId":args.instance_id,
            }),
        )
        .await?;
    if !receipt.is_null() {
        if receipt["id"] != args.workspace_id || receipt["instanceId"] != args.instance_id {
            bail!("The owner returned a retirement receipt for another task instance");
        }
        return Ok(json!({"version":1, "workspace":receipt, "processClosureVerified":true}));
    }
    let store = alera_core::runtime::RuntimeStore::open_read_only(&args.state_dir).await?;
    let workspace = store
        .find_workspace(&args.workspace_id)
        .await?
        .ok_or_else(|| anyhow!("The owner workspace is missing; process closure is unverified"))?;
    if workspace.instance_id != args.instance_id
        || workspace.host_id != alera_core::runtime::LOCAL_HOST_ID
    {
        bail!("The owner task identity changed; no processes were stopped");
    }
    let operation = match workspace.kind {
        alera_core::runtime::WorkspaceKind::Main => "removeShared",
        alera_core::runtime::WorkspaceKind::Linked => "removeManaged",
    };
    let mut payload = json!({"id":args.workspace_id, "expectedInstanceId":args.instance_id, "closeSessions":true, "deleteBranch":args.delete_branch});
    if let Some(scope) = automation_cleanup {
        payload["remoteAutomationCleanup"] = serde_json::to_value(scope)?;
    }
    let workspace = crate::workspace_buffer_guard_request::request_with_workspace_buffer_guard(
        &mut client,
        operation,
        &payload,
    )
    .await?;
    Ok(json!({"version":1, "workspace":workspace, "processClosureVerified":true}))
}

/// The hub retires every remote workspace through the satellite profile, but a
/// workspace that was created before the satellite existed still lives, with
/// its retirement receipt or its live sessions, in the retired per-project
/// `owners/<sha256(projectId)>` profile next to it. That profile is the one
/// that can prove process closure, so it is used when the satellite has no
/// record of the workspace and one of them does.
async fn owning_state_dir(args: &RemoteOwnerRetirementArgs) -> Result<std::path::PathBuf> {
    if knows_workspace(&args.state_dir, &args.workspace_id, &args.instance_id).await? {
        return Ok(args.state_dir.clone());
    }
    let Some(legacy_root) = args.state_dir.parent().map(|dir| dir.join("owners")) else {
        return Ok(args.state_dir.clone());
    };
    let mut entries = match tokio::fs::read_dir(&legacy_root).await {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(args.state_dir.clone())
        }
        Err(error) => return Err(error.into()),
    };
    while let Some(entry) = entries.next_entry().await? {
        let candidate = entry.path();
        if candidate.is_dir()
            && knows_workspace(&candidate, &args.workspace_id, &args.instance_id).await?
        {
            return Ok(candidate);
        }
    }
    Ok(args.state_dir.clone())
}

async fn knows_workspace(
    state_dir: &std::path::Path,
    workspace_id: &str,
    instance_id: &str,
) -> Result<bool> {
    if !tokio::fs::try_exists(state_dir.join(alera_core::runtime::RUNTIME_DATABASE_FILE_NAME))
        .await?
    {
        return Ok(false);
    }
    if alera_core::runtime::RuntimeStore::read_workspace_retirement_receipt(
        state_dir,
        workspace_id,
        instance_id,
    )
    .await?
    .is_some()
    {
        return Ok(true);
    }
    let store = alera_core::runtime::RuntimeStore::open_read_only(state_dir).await?;
    Ok(store
        .find_workspace(workspace_id)
        .await?
        .is_some_and(|workspace| workspace.instance_id == instance_id))
}

async fn enroll_never_started(args: &RemoteOwnerRetirementArgs, encoded: &str) -> Result<()> {
    let registration = crate::remote_workspace_owner::parse_registration(
        &crate::remote_workspace_owner::RemoteWorkspaceOwnerArgs {
            state_dir: args.state_dir.clone(),
            metadata_base64: encoded.to_string(),
        },
    )?;
    crate::remote_owner_enrollment::enroll_never_started(
        &args.state_dir,
        &args.workspace_id,
        &args.instance_id,
        registration.workspace.kind,
        encoded,
    )
    .await
}

fn parse_cleanup_scope(
    args: &RemoteOwnerRetirementArgs,
) -> Result<Option<alera_core::runtime::RemoteAutomationCleanup>> {
    use base64::Engine;
    let Some(encoded) = args.automation_cleanup_base64.as_deref() else {
        return Ok(None);
    };
    if encoded.len() > 1_048_576 {
        bail!("Owner automation cleanup scope is too large");
    }
    let bytes = base64::engine::general_purpose::STANDARD.decode(encoded)?;
    let scope: alera_core::runtime::RemoteAutomationCleanup = serde_json::from_slice(&bytes)?;
    if scope.workspace.id != args.workspace_id
        || scope.workspace.instance_id != args.instance_id
        || scope.workspace.host_id != alera_core::runtime::LOCAL_HOST_ID
        || scope.run_id.trim().is_empty()
    {
        bail!("Owner automation cleanup scope belongs to another task instance");
    }
    Ok(Some(scope))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn enrollment_preserves_launch_history_and_rejects_identity_mismatch() {
        use base64::Engine;
        let root = tempfile::tempdir().unwrap();
        let source = alera_core::runtime::RuntimeStore::open(&root.path().join("source"))
            .await
            .unwrap();
        let folder = root.path().join("folder");
        std::fs::create_dir(&folder).unwrap();
        let registration =
            crate::project_management::register_project(&source, folder.to_str().unwrap(), None)
                .await
                .unwrap();
        let workspace = registration.initial_workspace.unwrap();
        let encoded = base64::engine::general_purpose::STANDARD.encode(
            serde_json::to_vec(&json!({"project":registration.project,"workspace":workspace}))
                .unwrap(),
        );
        let mut args = RemoteOwnerRetirementArgs {
            state_dir: root.path().join("owner"),
            workspace_id: workspace.id.clone(),
            instance_id: "wrong-instance".into(),
            close_sessions: true,
            delete_branch: false,
            automation_cleanup_base64: None,
            enroll_never_started_base64: Some(encoded.clone()),
        };
        assert!(enroll_never_started(&args, &encoded)
            .await
            .unwrap_err()
            .to_string()
            .contains("another task instance"));
        assert!(!args.state_dir.exists());
        args.instance_id = workspace.instance_id.clone();
        enroll_never_started(&args, &encoded).await.unwrap();
        enroll_never_started(&args, &encoded).await.unwrap();
        let owner = alera_core::runtime::RuntimeStore::open(&args.state_dir)
            .await
            .unwrap();
        owner
            .record_workspace_terminal_launch(&workspace.id)
            .await
            .unwrap();
        assert!(enroll_never_started(&args, &encoded)
            .await
            .unwrap_err()
            .to_string()
            .contains("earlier terminal launch"));
        assert!(owner.find_workspace(&workspace.id).await.unwrap().is_some());
        assert!(folder.exists());
    }

    #[tokio::test]
    async fn unavailable_owner_is_not_started_and_requires_explicit_confirmation() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(directory.path().join("keep"), "retained").unwrap();
        for close_sessions in [false, true] {
            let error = run(RemoteOwnerRetirementArgs {
                state_dir: directory.path().into(),
                workspace_id: "task".into(),
                instance_id: "instance".into(),
                close_sessions,
                delete_branch: false,
                automation_cleanup_base64: None,
                enroll_never_started_base64: None,
            })
            .await
            .unwrap_err();
            assert!(error.to_string().contains(if close_sessions {
                "closure is unverified"
            } else {
                "--close-sessions"
            }));
            assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 1);
            assert_eq!(
                std::fs::read_to_string(directory.path().join("keep")).unwrap(),
                "retained"
            );
        }
    }

    #[tokio::test]
    async fn retirement_falls_back_to_the_legacy_owner_profile_that_knows_the_workspace() {
        let install = tempfile::tempdir().unwrap();
        let satellite = install.path().join("data");
        let legacy = install.path().join("owners").join("abc123");
        let folder = install.path().join("folder");
        std::fs::create_dir_all(&folder).unwrap();
        for profile in [&satellite, &legacy] {
            let store = alera_core::runtime::RuntimeStore::open(profile)
                .await
                .unwrap();
            drop(store);
        }
        let legacy_store = alera_core::runtime::RuntimeStore::open(&legacy)
            .await
            .unwrap();
        let workspace = crate::project_management::register_project(
            &legacy_store,
            folder.to_str().unwrap(),
            None,
        )
        .await
        .unwrap()
        .initial_workspace
        .unwrap();
        let args = |workspace_id: &str, instance_id: &str| RemoteOwnerRetirementArgs {
            state_dir: satellite.clone(),
            workspace_id: workspace_id.into(),
            instance_id: instance_id.into(),
            close_sessions: true,
            delete_branch: false,
            automation_cleanup_base64: None,
            enroll_never_started_base64: None,
        };
        assert_eq!(
            owning_state_dir(&args(&workspace.id, &workspace.instance_id))
                .await
                .unwrap(),
            legacy
        );
        // A different instance is another task; the satellite stays authoritative.
        assert_eq!(
            owning_state_dir(&args(&workspace.id, "other-instance"))
                .await
                .unwrap(),
            satellite
        );
        assert_eq!(
            owning_state_dir(&args("unknown", "instance"))
                .await
                .unwrap(),
            satellite
        );
        // Without a legacy directory at all the satellite is used unchanged.
        let lone = tempfile::tempdir().unwrap();
        let lone_state = lone.path().join("data");
        assert_eq!(
            owning_state_dir(&RemoteOwnerRetirementArgs {
                state_dir: lone_state.clone(),
                ..args("task", "instance")
            })
            .await
            .unwrap(),
            lone_state
        );
    }
}

#[cfg(test)]
mod automation_tests {
    use super::*;
    use base64::Engine;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

    #[tokio::test]
    async fn old_owner_refuses_automation_cleanup_without_sending_removal() {
        use crate::terminal_host::protocol::*;
        let root = tempfile::tempdir().unwrap();
        let store = alera_core::runtime::RuntimeStore::open(&root.path().join("state"))
            .await
            .unwrap();
        let folder = root.path().join("folder");
        std::fs::create_dir(&folder).unwrap();
        let project =
            crate::project_management::register_project(&store, folder.to_str().unwrap(), None)
                .await
                .unwrap()
                .project;
        let workspace = store.list_workspaces(&project.id).await.unwrap().remove(0);
        let scope = alera_core::runtime::RemoteAutomationCleanup {
            run_id: "run".into(),
            workspace: workspace.clone(),
            tab_ids: vec!["owned".into()],
        };
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        std::fs::write(root.path().join("state/runtime-host.json"), json!({
            "protocolVersion":PROTOCOL_VERSION,"port":listener.local_addr().unwrap().port(),"token":"test-token",
            "runtimeCapabilities":[RUNTIME_HOST_CAPABILITY,RUNTIME_HOST_BOOTSTRAP_CAPABILITY,RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY]
        }).to_string()).unwrap();
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let (reader, mut writer) = socket.into_split();
            let mut lines = BufReader::new(reader).lines();
            let request: Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            assert_eq!(request["type"], "hello");
            writer
                .write_all(
                    format!("{}\n", json!({"id":request["id"],"ok":true,"payload":{}})).as_bytes(),
                )
                .await
                .unwrap();
            assert!(
                tokio::time::timeout(std::time::Duration::from_secs(5), lines.next_line())
                    .await
                    .unwrap()
                    .unwrap()
                    .is_none()
            );
        });
        let args = RemoteOwnerRetirementArgs {
            state_dir: root.path().join("state"),
            workspace_id: workspace.id.clone(),
            instance_id: workspace.instance_id.clone(),
            close_sessions: true,
            delete_branch: false,
            enroll_never_started_base64: None,
            automation_cleanup_base64: Some(
                base64::engine::general_purpose::STANDARD
                    .encode(serde_json::to_vec(&scope).unwrap()),
            ),
        };
        let error = run(args).await.unwrap_err();
        assert!(
            error
                .to_string()
                .contains(RUNTIME_HOST_REMOTE_AUTOMATION_CLEANUP_CAPABILITY),
            "{error}"
        );
        server.await.unwrap();
        assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
        assert!(folder.exists());
    }
}
