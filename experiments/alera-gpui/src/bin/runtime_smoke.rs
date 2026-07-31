use std::path::PathBuf;
use std::time::Duration;

use alera_runtime_client::{RuntimeClientConnection, RuntimeClientOptions};
use serde_json::{json, Value};

fn main() -> anyhow::Result<()> {
    tokio::runtime::Runtime::new()?.block_on(run())
}

async fn run() -> anyhow::Result<()> {
    let runtime_dir = runtime_dir()?;
    let Some(connection) =
        RuntimeClientConnection::connect(&runtime_dir, RuntimeClientOptions::default()).await?
    else {
        anyhow::bail!("Alera runtime is unavailable at {}", runtime_dir.display());
    };
    let client = connection.handle;
    let projects = client.request("project.list", &json!({})).await?;
    let project = projects
        .as_array()
        .and_then(|items| items.first())
        .ok_or_else(|| anyhow::anyhow!("runtime has no projects"))?;
    let project_id = string_field(project, "id")?;
    let workspaces = client
        .request("workspace.list", &json!({"projectId": project_id}))
        .await?;
    let workspace = workspaces
        .as_array()
        .and_then(|items| items.first())
        .ok_or_else(|| anyhow::anyhow!("first project has no workspaces"))?;
    let workspace_id = string_field(workspace, "id")?;

    let requests = [
        ("linkedReview.find", json!({"workspaceId": workspace_id})),
        (
            "workspace.repositoryWebUrl",
            json!({"workspaceId": workspace_id}),
        ),
        ("runtimeSettings.get", json!({})),
        ("agentProfile.list", json!({})),
        ("agentQuota.snapshot", json!({})),
        ("agentPresence.list", json!({})),
        ("resources.snapshot", json!({"appPid": std::process::id()})),
        ("orchestration.runList", json!({"workspace": workspace_id})),
        ("orchestration.taskList", json!({"workspace": workspace_id})),
        ("orchestration.gateList", json!({})),
        (
            "orchestration.terminals",
            json!({"workspace": workspace_id}),
        ),
        ("workbenchViewPrefs.get", json!({})),
        ("projectConfig.effective", json!({"projectId": project_id})),
        ("mobile.status.get", json!({})),
        ("mobile.device.list", json!({})),
        ("mobile.runtimeSettings.get", json!({})),
        ("status.get", json!({})),
        ("cliRegistration.status", json!({})),
    ];

    let mut failed = false;
    for (verb, payload) in requests {
        match client
            .request_with_timeout(verb, &payload, Duration::from_secs(30))
            .await
        {
            Ok(_) => println!("ok {verb}"),
            Err(error) => {
                failed = true;
                println!("error {verb}: {error}");
            }
        }
    }
    client.close().await;
    if failed {
        anyhow::bail!("one or more runtime smoke requests failed");
    }
    Ok(())
}

fn runtime_dir() -> anyhow::Result<PathBuf> {
    std::env::var_os("ALERA_RUNTIME_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            dirs::data_local_dir().map(|data| data.join("dev.leynier.alera").join("terminal_host"))
        })
        .ok_or_else(|| anyhow::anyhow!("failed to resolve the Alera runtime directory"))
}

fn string_field<'a>(value: &'a Value, key: &str) -> anyhow::Result<&'a str> {
    value
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("runtime payload omitted {key}"))
}
