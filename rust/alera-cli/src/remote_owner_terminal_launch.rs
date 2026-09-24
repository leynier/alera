use alera_core::runtime::{RuntimeStore, SshTarget, Workspace};
use anyhow::{anyhow, Result};
use base64::Engine;
use serde_json::json;

use crate::ssh_bootstrap::{powershell_encoded, powershell_string, shell_quote};
use crate::terminal_host::protocol::TerminalHostLaunch;

pub(crate) struct TerminalIdentity<'a> {
    pub session_id: &'a str,
    pub tab_id: &'a str,
    pub cols: u16,
    pub rows: u16,
}

/// The `{project, workspace, repositoryPath?}` document a satellite needs to
/// register a hub workspace as its own (`remote_workspace_owner::register`).
/// The project path is the checkout registered for the workspace's host.
pub(crate) async fn satellite_registration(
    store: &RuntimeStore,
    workspace: &Workspace,
) -> Result<serde_json::Value> {
    let mut project = store
        .find_project(&workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("The remote workspace project is missing"))?;
    let checkout = store
        .find_project_checkout(&project.id, &workspace.host_id)
        .await?
        .ok_or_else(|| {
            anyhow!("Register this project's checkout on the SSH host before opening its terminal")
        })?;
    if workspace.kind == alera_core::runtime::WorkspaceKind::Main && checkout.path != workspace.path
    {
        anyhow::bail!("The shared workspace no longer matches its registered SSH checkout");
    }
    project.repo_path = checkout.path;
    let repository_path = if workspace.kind == alera_core::runtime::WorkspaceKind::Linked {
        let binding = store
            .find_workspace_checkout(&workspace.id)
            .await?
            .ok_or_else(|| anyhow!("The linked SSH checkout binding is missing"))?;
        if binding.project_id != workspace.project_id
            || binding.host_id != workspace.host_id
            || binding.path != workspace.path
            || binding.kind != alera_core::runtime::CheckoutKind::Linked
        {
            anyhow::bail!("The linked SSH checkout ownership changed");
        }
        Some(binding.repository_path.ok_or_else(|| anyhow!("The linked SSH repository origin must be verified before opening its owner terminal"))?)
    } else {
        None
    };
    let mut registration = json!({"project":project,"workspace":workspace});
    if let Some(repository_path) = repository_path {
        registration["repositoryPath"] = json!(repository_path);
    }
    Ok(registration)
}

pub(crate) async fn owned_launch(
    store: &RuntimeStore,
    target: &SshTarget,
    workspace: &Workspace,
    identity: TerminalIdentity<'_>,
    windows: bool,
) -> Result<TerminalHostLaunch> {
    let registration = satellite_registration(store, workspace).await?;
    let install = target
        .install_dir
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| {
            anyhow!("Bootstrap this SSH host again to record its sidecar installation directory")
        })?;
    let metadata =
        base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(&registration)?);
    let automation_run_id = crate::remote_owner_terminal_ownership::automation_run_id(
        store,
        workspace,
        identity.tab_id,
    )
    .await?;
    let launch_token = store
        .terminal_restart_launch_token(workspace, identity.tab_id, identity.session_id)
        .await?;
    let script = command_script(
        windows,
        install,
        &metadata,
        identity,
        automation_run_id.as_deref(),
        launch_token.as_deref(),
    );
    let command = if windows {
        format!(
            "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand {}",
            powershell_encoded(&script)
        )
    } else {
        format!("sh -lc {}", shell_quote(&script))
    };
    Ok(TerminalHostLaunch {
        label: "ssh".into(),
        shell: "ssh".into(),
        arguments: crate::ssh_remote::ssh_pty_arguments(target, &command),
        environment: Default::default(),
    })
}

fn command_script(
    windows: bool,
    install: &str,
    metadata: &str,
    identity: TerminalIdentity<'_>,
    automation_run_id: Option<&str>,
    launch_token: Option<&str>,
) -> String {
    let quote = if windows {
        powershell_string
    } else {
        shell_quote
    };
    let mut arguments = format!("project owner-terminal --metadata-base64 {} --session-id {} --tab-id {} --cols {} --rows {}",
        quote(metadata), quote(identity.session_id), quote(identity.tab_id), identity.cols, identity.rows);
    if let Some(run_id) = automation_run_id {
        arguments.push_str(&format!(" --automation-run-id {}", quote(run_id)));
    }
    if let Some(token) = launch_token {
        arguments.push_str(&format!(" --launch-token {}", quote(token)));
    }
    owner_command_script(windows, install, &arguments)
}

/// Wraps a sidecar CLI invocation so it runs against the satellite runtime
/// profile at `<installDir>/data`: the same profile the host link attaches
/// to, so every project on a host shares one runtime instead of the retired
/// per-project `owners/<sha256(projectId)>` profiles.
pub(crate) fn owner_command_script(windows: bool, install: &str, arguments: &str) -> String {
    let quote = if windows {
        powershell_string
    } else {
        shell_quote
    };
    if windows {
        format!("$ErrorActionPreference = 'Stop'\n$install = [Environment]::ExpandEnvironmentVariables({})\n$current = (Get-Content -Raw -LiteralPath (Join-Path $install 'current.txt')).Trim()\n$state = Join-Path $install 'data'\n& (Join-Path $current 'alera.exe') {arguments} --state-dir $state\nexit $LASTEXITCODE\n", quote(install))
    } else {
        format!("set -eu\ninstall={}\ncase \"$install\" in '~/'*) install=\"$HOME/${{install#\"~/\"}}\";; esac\nexec \"$install/current/alera\" {arguments} --state-dir \"$install/data\"\n", quote(install))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn shared_tasks_use_remote_project_path_and_the_same_owner_profile() {
        let directory = tempfile::tempdir().unwrap();
        let folder = directory.path().join("folder");
        std::fs::create_dir(&folder).unwrap();
        let store = RuntimeStore::open(&directory.path().join("state"))
            .await
            .unwrap();
        let mut project =
            crate::project_management::register_project(&store, folder.to_str().unwrap(), None)
                .await
                .unwrap()
                .project;
        let mut task = store.list_workspaces(&project.id).await.unwrap().remove(0);
        store
            .register_project_checkout(&project.id, "ssh", "/remote/project")
            .await
            .unwrap();
        task.host_id = "ssh".into();
        task.path = "/remote/project".into();
        let target: SshTarget = serde_json::from_value(json!({
            "id":"ssh", "alias":"Test", "host":"test.invalid", "port":22,
            "username":"test", "authKind":"agent", "createdAt":chrono::Utc::now(),
            "updatedAt":chrono::Utc::now(), "installDir":"/remote/sidecar", "bootstrapStatus":"installed",
        })).unwrap();
        project = store.find_project(&project.id).await.unwrap().unwrap();
        project.repo_path = task.path.clone();
        for id in ["one", "two"] {
            task.id = id.into();
            task.instance_id = format!("instance-{id}");
            let launch = owned_launch(
                &store,
                &target,
                &task,
                TerminalIdentity {
                    session_id: id,
                    tab_id: id,
                    cols: 80,
                    rows: 24,
                },
                false,
            )
            .await
            .unwrap();
            let command = launch.arguments.last().unwrap();
            let expected = base64::engine::general_purpose::STANDARD
                .encode(serde_json::to_vec(&json!({"project":project,"workspace":task})).unwrap());
            assert!(command.contains(&expected));
            assert!(command.contains("--state-dir \"$install/data\""));
            assert!(launch.arguments.contains(&"-tt".into()));
        }
        task.path = "/remote/other".into();
        assert!(owned_launch(
            &store,
            &target,
            &task,
            TerminalIdentity {
                session_id: "one",
                tab_id: "one",
                cols: 80,
                rows: 24,
            },
            false
        )
        .await
        .unwrap_err()
        .to_string()
        .contains("no longer matches"));
        for (id, origin) in [
            ("new-linked", "/remote/project"),
            ("old-linked", "/remote/legacy.git"),
        ] {
            task.id = id.into();
            task.instance_id = format!("instance-{id}");
            task.kind = alera_core::runtime::WorkspaceKind::Linked;
            task.path = format!("/remote/{id}");
            task.branch = Some(id.into());
            store
                .insert_workspace_with_repository(task.clone(), origin)
                .await
                .unwrap();
            let launch = owned_launch(
                &store,
                &target,
                &task,
                TerminalIdentity {
                    session_id: id,
                    tab_id: id,
                    cols: 80,
                    rows: 24,
                },
                false,
            )
            .await
            .unwrap();
            let command = launch.arguments.last().unwrap();
            let expected = base64::engine::general_purpose::STANDARD.encode(
                serde_json::to_vec(
                    &json!({"project":project,"workspace":task,"repositoryPath":origin}),
                )
                .unwrap(),
            );
            assert!(command.contains(&expected));
            assert!(command.contains("project owner-terminal"));
            assert!(command.contains("--state-dir \"$install/data\""));
            assert_eq!(
                store
                    .find_workspace_checkout(id)
                    .await
                    .unwrap()
                    .unwrap()
                    .repository_path
                    .as_deref(),
                Some(origin)
            );
        }
    }

    #[test]
    fn native_terminal_commands_preserve_identity_and_exit_status() {
        for windows in [false, true] {
            let script = command_script(
                windows,
                "~/sidecar's files",
                "e30=",
                TerminalIdentity {
                    session_id: "session'1",
                    tab_id: "tab'2",
                    cols: 120,
                    rows: 40,
                },
                Some("run'3"),
                Some("restart'4"),
            );
            assert!(script.contains("project owner-terminal"));
            assert!(script.contains("--metadata-base64 'e30='"));
            assert!(script.contains("--cols 120 --rows 40"));
            let quote = if windows {
                powershell_string
            } else {
                shell_quote
            };
            assert!(script.contains(&format!("--automation-run-id {}", quote("run'3"))));
            assert!(!script.contains("owners"));
            if windows {
                assert!(script.contains("$state = Join-Path $install 'data'"));
            } else {
                assert!(script.contains("--state-dir \"$install/data\""));
            }
            if windows {
                assert!(script.contains("'session''1'"));
                assert!(script.contains("exit $LASTEXITCODE"));
            } else {
                assert!(script.contains(&shell_quote("session'1")));
                assert!(script.contains("exec \"$install/current/alera\""));
            }
        }
    }
}
