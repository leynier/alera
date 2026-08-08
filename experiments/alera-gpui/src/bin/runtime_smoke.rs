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
    let requested_workspace_id = std::env::var("ALERA_RUNTIME_SMOKE_WORKSPACE_ID").ok();
    let workspace = workspaces
        .as_array()
        .and_then(|items| {
            requested_workspace_id
                .as_deref()
                .and_then(|requested| {
                    items
                        .iter()
                        .find(|item| item.get("id").and_then(Value::as_str) == Some(requested))
                })
                .or_else(|| items.first())
        })
        .ok_or_else(|| anyhow::anyhow!("first project has no workspaces"))?;
    let workspace_id = string_field(workspace, "id")?;
    let workspace_path = string_field(workspace, "path")?;
    let workspace_entries = client
        .request(
            "workspaceFiles.list",
            &json!({
                "workspacePath": workspace_path,
                "relativePath": "",
                "hideIgnored": true,
            }),
        )
        .await?;

    let mut requests = vec![
        ("hostDirectory.list", json!({"path": workspace_path})),
        (
            "workspaceFiles.list",
            json!({
                "workspacePath": workspace_path,
                "relativePath": "",
                "hideIgnored": true,
            }),
        ),
        (
            "workspaceSearch.search",
            json!({
                "workspacePath": workspace_path,
                "query": "a",
                "caseSensitive": false,
                "wholeWord": false,
                "useRegex": false,
                "includePattern": null,
                "excludePattern": null,
                "includeIgnored": false,
            }),
        ),
        (
            "workspaceGit.snapshot",
            json!({"workspacePath": workspace_path}),
        ),
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
        ("tab.list", json!({"workspaceId": workspace_id})),
        ("layout.find", json!({"workspaceId": workspace_id})),
        ("projectConfig.effective", json!({"projectId": project_id})),
        ("mobile.status.get", json!({})),
        ("mobile.device.list", json!({})),
        ("mobile.runtimeSettings.get", json!({})),
        ("status.get", json!({})),
        ("cliRegistration.status", json!({})),
    ];
    if let Some(relative_path) = workspace_entries
        .as_array()
        .and_then(|entries| {
            entries
                .iter()
                .find(|entry| entry.get("kind").and_then(Value::as_str) == Some("file"))
        })
        .and_then(|entry| entry.get("relativePath"))
        .and_then(Value::as_str)
    {
        requests.push((
            "workspaceFiles.readEditor",
            json!({
                "workspacePath": workspace_path,
                "relativePath": relative_path,
                "tabSize": 4,
            }),
        ));
    }

    let mut failed = false;
    let dump_responses = std::env::var_os("ALERA_RUNTIME_SMOKE_DUMP").is_some();
    for (verb, payload) in requests {
        match client
            .request_with_timeout(verb, &payload, Duration::from_secs(30))
            .await
        {
            Ok(value) => {
                println!("ok {verb}");
                if dump_responses {
                    println!("value {verb} {value}");
                }
            }
            Err(error) => {
                failed = true;
                println!("error {verb}: {error}");
            }
        }
    }
    if std::env::var_os("ALERA_RUNTIME_SMOKE_RESTART_HOST").is_some() {
        client
            .request_with_timeout(
                "host.restart",
                &json!({"force": true}),
                Duration::from_secs(30),
            )
            .await?;
        println!("ok host.restart");
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
