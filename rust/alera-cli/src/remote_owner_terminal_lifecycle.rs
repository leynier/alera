use alera_core::runtime::{
    TerminalLifecycleAction, TerminalLifecycleOperation, Workspace, LOCAL_HOST_ID,
};
use anyhow::{anyhow, bail, Context, Result};
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, clap::Args)]
pub(crate) struct RemoteOwnerTerminalLifecycleArgs {
    #[arg(long)]
    pub state_dir: std::path::PathBuf,
    #[arg(long)]
    pub request_base64: String,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Request {
    operation_id: String,
    workspace: Workspace,
    tab_id: String,
    session_id: String,
    action: TerminalLifecycleAction,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    registration_base64: Option<String>,
}

fn parse(args: &RemoteOwnerTerminalLifecycleArgs) -> Result<Request> {
    if !args.state_dir.is_absolute() || args.request_base64.len() > 1_048_576 {
        bail!("An absolute owner runtime directory and bounded terminal request are required");
    }
    let request: Request = serde_json::from_slice(
        &base64::engine::general_purpose::STANDARD.decode(&args.request_base64)?,
    )?;
    if uuid::Uuid::parse_str(&request.operation_id).is_err()
        || request.workspace.host_id != LOCAL_HOST_ID
        || request.workspace.id.trim().is_empty()
        || request.workspace.instance_id.trim().is_empty()
        || request.tab_id.trim().is_empty()
        || request.session_id.trim().is_empty()
    {
        bail!("A stable operation UUID and exact owner task and terminal identities are required");
    }
    Ok(request)
}

fn verify(request: &Request, value: &Value) -> Result<()> {
    let operation: TerminalLifecycleOperation = serde_json::from_value(value["operation"].clone())?;
    let expected = &request.workspace;
    let actual = &operation.workspace;
    if value["processClosureVerified"] != true
        || !operation.closure_verified
        || operation.session_generation == 0
        || operation.id != request.operation_id
        || operation.action != request.action
        || operation.tab_id != request.tab_id
        || operation.session_id != request.session_id
        || actual.id != expected.id
        || actual.instance_id != expected.instance_id
        || actual.project_id != expected.project_id
        || actual.host_id != expected.host_id
        || actual.kind != expected.kind
        || actual.path != expected.path
    {
        bail!("Owner terminal closure evidence does not match the requested task and action");
    }
    Ok(())
}

pub(crate) async fn run(args: RemoteOwnerTerminalLifecycleArgs) -> Result<Value> {
    let request = parse(&args)?;
    // A new host cannot prove that processes from the previous owner exited.
    let mut connection =
        crate::runtime_host_client::RuntimeHostRpcClient::connect_with_required_capability(
            &args.state_dir,
            crate::terminal_host::protocol::RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY,
        )
        .await?;
    if request.registration_base64.is_some() {
        if connection.is_none() {
            crate::terminal_host::runtime_owner::ensure_no_live_owner(&args.state_dir)?;
        }
        let store = alera_core::runtime::RuntimeStore::open(&args.state_dir).await?;
        if let Some(receipt) = store
            .terminal_lifecycle_operation(&request.operation_id)
            .await?
        {
            if receipt.closure_verified {
                let value = serde_json::json!({"operation":receipt,"processClosureVerified":true});
                verify(&request, &value)?;
                return Ok(value);
            }
        }
        enroll_missing_terminal(&store, &args.state_dir, &request).await?;
        if connection.is_none() {
            crate::remote_owner_enrollment::require_never_started(
                &store,
                &request.workspace.id,
                &request.workspace.instance_id,
            )
            .await?;
            connection = Some(crate::runtime_host_client::RuntimeHostRpcClient::connect_or_start_with_required_capability(
                &args.state_dir, crate::terminal_host::protocol::RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY,
            ).await?);
        }
    }
    let mut client = connection.ok_or_else(|| {
        anyhow!("The owner runtime is unavailable; terminal process closure remains unverified")
    })?;
    let value = client
        .request_value("terminal.ownerLifecycle", &serde_json::to_value(&request)?)
        .await?;
    verify(&request, &value)?;
    Ok(value)
}

async fn enroll_missing_terminal(
    store: &alera_core::runtime::RuntimeStore,
    state_dir: &std::path::Path,
    request: &Request,
) -> Result<()> {
    if store.find_workspace_tab(&request.tab_id).await?.is_some() {
        return Ok(());
    }
    let encoded = request
        .registration_base64
        .as_ref()
        .context("Recovery registration is missing")?;
    let registration = crate::remote_workspace_owner::parse_registration(
        &crate::remote_workspace_owner::RemoteWorkspaceOwnerArgs {
            state_dir: state_dir.into(),
            metadata_base64: encoded.clone(),
        },
    )?;
    if registration.workspace != request.workspace {
        bail!("Terminal recovery registration belongs to another task or checkout");
    }
    let workspace = crate::remote_workspace_owner::register(store, registration).await?;
    crate::remote_owner_enrollment::require_never_started(
        store,
        &workspace.id,
        &workspace.instance_id,
    )
    .await?;
    crate::remote_owner_terminal_ownership::register_tab(
        store,
        &workspace,
        &request.tab_id,
        &request.session_id,
        None,
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn recovery_enrollment_requires_exact_identity_and_no_prior_attempt() {
        for scenario in ["new", "attempted", "foreign"] {
            let root = tempfile::tempdir().unwrap();
            let folder = root.path().join("project");
            std::fs::create_dir(&folder).unwrap();
            let source = alera_core::runtime::RuntimeStore::open(&root.path().join("source"))
                .await
                .unwrap();
            let created = crate::project_management::register_project(
                &source,
                folder.to_str().unwrap(),
                None,
            )
            .await
            .unwrap();
            let workspace = created.initial_workspace.unwrap();
            let state = root.path().join("owner");
            let owner = alera_core::runtime::RuntimeStore::open(&state)
                .await
                .unwrap();
            let metadata = json!({"project":created.project,"workspace":workspace});
            let mut request = Request {
                operation_id: uuid::Uuid::new_v4().to_string(),
                workspace: workspace.clone(),
                tab_id: "tab".into(),
                session_id: "session".into(),
                action: TerminalLifecycleAction::Close,
                registration_base64: Some(
                    base64::engine::general_purpose::STANDARD
                        .encode(serde_json::to_vec(&metadata).unwrap()),
                ),
            };
            if scenario == "attempted" {
                crate::remote_workspace_owner::register(
                    &owner,
                    serde_json::from_value(metadata).unwrap(),
                )
                .await
                .unwrap();
                owner
                    .record_workspace_terminal_launch(&workspace.id)
                    .await
                    .unwrap();
            }
            if scenario == "foreign" {
                request.workspace.instance_id = "another-instance".into();
            }
            let result = enroll_missing_terminal(&owner, &state, &request).await;
            if scenario == "new" {
                result.unwrap();
                assert_eq!(
                    owner
                        .terminal_launch_attempted(
                            &workspace.id,
                            &workspace.instance_id,
                            "tab",
                            "session"
                        )
                        .await
                        .unwrap(),
                    Some(false)
                );
                enroll_missing_terminal(&owner, &state, &request)
                    .await
                    .unwrap();
            } else {
                assert!(result.is_err());
                assert!(owner.find_workspace_tab("tab").await.unwrap().is_none());
            }
        }
    }

    #[tokio::test]
    async fn request_and_receipt_require_exact_scope_without_starting_an_owner() {
        let root = tempfile::tempdir().unwrap();
        let folder = root.path().join("project");
        std::fs::create_dir(&folder).unwrap();
        let state = root.path().join("state");
        let store = alera_core::runtime::RuntimeStore::open(&state)
            .await
            .unwrap();
        let project =
            crate::project_management::register_project(&store, folder.to_str().unwrap(), None)
                .await
                .unwrap();
        let workspace = store
            .list_workspaces(&project.project.id)
            .await
            .unwrap()
            .remove(0);
        let request = Request {
            operation_id: uuid::Uuid::new_v4().to_string(),
            workspace,
            tab_id: "tab".into(),
            session_id: "session".into(),
            action: TerminalLifecycleAction::Close,
            registration_base64: None,
        };
        let receipt = json!({"processClosureVerified":true,"operation":TerminalLifecycleOperation {
            id: request.operation_id.clone(), workspace: request.workspace.clone(),
            tab_id: request.tab_id.clone(), session_id: request.session_id.clone(),
            session_generation: 7, initiator_epoch: None, action: request.action, closure_verified: true,
        }});
        verify(&request, &receipt).unwrap();
        for (pointer, replacement) in [
            ("/processClosureVerified", json!(false)),
            ("/operation/closureVerified", json!(false)),
            ("/operation/sessionGeneration", json!(0)),
            ("/operation/id", json!("another-operation")),
            ("/operation/action", json!("restart")),
            ("/operation/tabId", json!("another-tab")),
            ("/operation/sessionId", json!("another-session")),
            ("/operation/workspace/instanceId", json!("another-instance")),
            ("/operation/workspace/hostId", json!("another-host")),
            ("/operation/workspace/path", json!("another-path")),
        ] {
            let mut altered = receipt.clone();
            *altered.pointer_mut(pointer).unwrap() = replacement;
            assert!(verify(&request, &altered).is_err(), "{pointer}");
        }
        let encode = |request: &Request| {
            base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(request).unwrap())
        };
        let args = RemoteOwnerTerminalLifecycleArgs {
            state_dir: state.clone(),
            request_base64: encode(&request),
        };
        parse(&args).unwrap();
        assert!(run(args)
            .await
            .unwrap_err()
            .to_string()
            .contains("unavailable"));
        let mut invalid = request;
        invalid.operation_id = "not-a-uuid".into();
        assert!(parse(&RemoteOwnerTerminalLifecycleArgs {
            state_dir: state,
            request_base64: encode(&invalid)
        })
        .is_err());
    }
}
