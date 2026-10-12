//! `alera ssh-target`: the remote hosts this runtime reaches over SSH.

use super::*;
use crate::cli::{
    SshAuthKindArg, SshTargetAction, SshTargetAddArgs, SshTargetBootstrapArgs,
    SshTargetBootstrapPlanArgs, SshTargetCommand, SshTargetLinkArgs, SshTargetRuntimeArgs,
    SshTargetStatusArgs, SshTargetUpdateArgs,
};
use crate::ssh_bootstrap::{
    build_ssh_bootstrap_plan, new_bootstrap_job_id, reject_password_ssh_bootstrap_auth,
    run_ssh_bootstrap, SshTargetBootstrapRequest,
};
use crate::ssh_target_status::{collect_ssh_target_status, LiveSshTargetProbe};
use alera_core::runtime::{SshAuthKind, SshTarget};

pub(super) async fn run_ssh_target_command(command: SshTargetCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        SshTargetAction::List => match list_ssh_targets(&runtime).await {
            Ok(targets) => print_value(
                &json!({ "kind": "sshTargets", "items": targets, "filters": {} }),
                json_output,
                "ssh targets listed",
            ),
            Err(error) => return print_error(error),
        },
        SshTargetAction::Add(args) => {
            let target = ssh_target_from_args(args);
            if let Err(error) = reject_password_ssh_bootstrap_auth(target.auth_kind) {
                return print_error(error);
            }
            match add_ssh_target_from_cli(&runtime, target).await {
                Ok(target) => print_value(&target, json_output, "ssh target saved"),
                Err(error) => return print_error(error),
            }
        }
        SshTargetAction::Update(args) => match update_ssh_target_from_cli(&runtime, args).await {
            Ok(target) => print_value(&target, json_output, "ssh target updated"),
            Err(error) => return print_error(error),
        },
        SshTargetAction::Remove(IdArgs { id }) => {
            let payload = json!({ "id": id });
            let removed_id = id.clone();
            match runtime_host_or_store_unit(
                &runtime,
                "sshTarget.remove",
                &payload,
                |store| async move { store.remove_ssh_target(&id).await },
            )
            .await
            {
                Ok(()) => print_value(
                    &json!({ "id": removed_id }),
                    json_output,
                    "ssh target removed",
                ),
                Err(error) => return print_error(error),
            }
        }
        SshTargetAction::Link(SshTargetLinkArgs {
            id,
            connect,
            disconnect,
        }) => {
            let mut client = match runtime_host_required(&runtime).await {
                Ok(client) => client,
                Err(error) => return print_error(error),
            };
            let (verb, payload, message) = match (id, connect, disconnect) {
                (Some(id), true, _) => (
                    "hostLink.connect",
                    json!({ "hostId": id }),
                    "host link attached",
                ),
                (Some(id), _, true) => (
                    "hostLink.disconnect",
                    json!({ "hostId": id }),
                    "host link closed",
                ),
                (None, true, _) | (None, _, true) => {
                    return print_error("--id is required with --connect or --disconnect")
                }
                (_, false, false) => ("hostLink.status", json!({}), "host links listed"),
            };
            match client.request_value(verb, &payload).await {
                Ok(value) => print_value(&value, json_output, message),
                Err(error) => return print_error(error),
            }
        }
        SshTargetAction::Status(SshTargetStatusArgs { id }) => {
            let value = match check_ssh_targets(&runtime, id).await {
                Ok(value) => value,
                Err(error) => return print_error(error),
            };
            print_value(&value, json_output, "ssh target status ready");
        }
        SshTargetAction::BootstrapPlan(args) => {
            let request = match ssh_bootstrap_request_from_plan_args(args) {
                Ok(request) => request,
                Err(error) => return print_error(error),
            };
            let fallback_request = request.clone();
            let value = match runtime_host_or_store(
                &runtime,
                "sshTarget.bootstrap.plan",
                &request,
                |store| async move { build_ssh_bootstrap_plan(&store, &fallback_request).await },
            )
            .await
            {
                Ok(plan) => plan,
                Err(error) => return print_error(error),
            };
            print_value(&value, json_output, "ssh bootstrap plan ready");
        }
        SshTargetAction::Bootstrap(args) => {
            let request = match ssh_bootstrap_request_from_args(args) {
                Ok(request) => request,
                Err(error) => return print_error(error),
            };
            let payload = request.clone();
            // The restart needs the runtime's host link, so it never runs in
            // the CLI process.
            let client = if request.restart_runtime {
                runtime_host_required(&runtime).await.map(Some)
            } else {
                RuntimeHostRpcClient::connect(&runtime_dir(&runtime)).await
            };
            let value: Value = if let Some(mut client) = match client {
                Ok(client) => client,
                Err(error) => return print_error(error),
            } {
                match client
                    .request_value("sshTarget.bootstrap.start", &payload)
                    .await
                {
                    Ok(value) => value,
                    Err(error) => return print_error(error),
                }
            } else {
                let store = match open_store(&runtime).await {
                    Ok(store) => store,
                    Err(error) => return print_error(error),
                };
                let cache_dir = runtime_dir(&runtime).join("runtime-artifacts");
                let job_id = new_bootstrap_job_id();
                match run_ssh_bootstrap(store, cache_dir, request, job_id, |progress| {
                    if json_output {
                        eprintln!(
                            "{}",
                            serde_json::to_string(&progress).unwrap_or_else(|_| "{}".to_string())
                        );
                    } else {
                        eprintln!("{}", progress.message);
                    }
                })
                .await
                {
                    Ok(target) => json!(target),
                    Err(error) => return print_error(error),
                }
            };
            print_value(&value, json_output, "ssh bootstrap started");
        }
        SshTargetAction::UpdateRuntime(SshTargetRuntimeArgs { id, force }) => {
            let payload = json!({ "targetId": id, "restartRuntime": true, "force": force });
            match runtime_request(&runtime, "sshTarget.bootstrap.start", &payload).await {
                Ok(value) => print_value(&value, json_output, "ssh runtime update started"),
                Err(error) => return print_error(error),
            }
        }
        SshTargetAction::RestartRuntime(SshTargetRuntimeArgs { id, force }) => {
            let payload = json!({ "id": id, "force": force });
            match runtime_request(&runtime, "sshTarget.restartRuntime", &payload).await {
                Ok(value) => print_value(&value, json_output, "ssh runtime restarted"),
                Err(error) => return print_error(error),
            }
        }
        SshTargetAction::BootstrapCancel(IdArgs { id }) => {
            let payload = json!({ "id": id });
            let value: Value = if let Some(mut client) =
                match RuntimeHostRpcClient::connect(&runtime_dir(&runtime)).await {
                    Ok(client) => client,
                    Err(error) => return print_error(error),
                } {
                match client
                    .request_value("sshTarget.bootstrap.cancel", &payload)
                    .await
                {
                    Ok(value) => value,
                    Err(error) => return print_error(error),
                }
            } else {
                return print_error("no active runtime host bootstrap job is available to cancel");
            };
            print_value(&value, json_output, "ssh bootstrap cancelled");
        }
    }
    0
}

/// Updating or restarting a host's runtime goes through this machine's
/// runtime, which owns the host link; it is started when needed.
async fn runtime_request(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    payload: &Value,
) -> anyhow::Result<Value> {
    runtime_host_required(runtime)
        .await?
        .request_value(request_type, payload)
        .await
}

/// A running runtime answers with each host's `hostStatus` as well.
async fn list_ssh_targets(runtime: &RuntimeDirArgs) -> anyhow::Result<Value> {
    runtime_host_or_store(runtime, "sshTarget.list", &json!({}), |store| async move {
        Ok(json!(store.list_ssh_targets().await?))
    })
    .await
}

/// Probes through the running runtime (`sshTarget.check`), so it records the
/// result, refreshes the app and reconnects a host that should be linked;
/// without one the store is probed directly. Either way `--id` prints one
/// target and no id prints them all.
async fn check_ssh_targets(runtime: &RuntimeDirArgs, id: Option<String>) -> anyhow::Result<Value> {
    if let Some(mut client) = RuntimeHostRpcClient::connect(&runtime_dir(runtime)).await? {
        let answer = client
            .request_value("sshTarget.check", &json!({ "id": id }))
            .await?;
        let targets = answer.get("targets").cloned().unwrap_or(json!([]));
        return Ok(match id {
            Some(_) => targets.get(0).cloned().unwrap_or(Value::Null),
            None => targets,
        });
    }
    let store = open_store(runtime).await?;
    collect_ssh_target_status(&store, id.as_deref(), &LiveSshTargetProbe).await
}

/// Saved hosts are read and written through the running runtime when there is
/// one, so the app sees the change at once, and through the store otherwise.
enum SshTargetRecords {
    Runtime(RuntimeHostRpcClient),
    Store(RuntimeStore),
}

impl SshTargetRecords {
    async fn open(args: &RuntimeDirArgs) -> anyhow::Result<Self> {
        if let Some(client) = RuntimeHostRpcClient::connect(&runtime_dir(args)).await? {
            return Ok(Self::Runtime(client));
        }
        Ok(Self::Store(open_store(args).await?))
    }

    async fn find(&mut self, id: &str) -> anyhow::Result<Option<SshTarget>> {
        match self {
            Self::Runtime(client) => {
                let targets: Vec<SshTarget> = client.request("sshTarget.list", &json!({})).await?;
                Ok(targets.into_iter().find(|target| target.id == id))
            }
            Self::Store(store) => store.find_ssh_target(id).await,
        }
    }

    async fn save(&mut self, target: SshTarget) -> anyhow::Result<SshTarget> {
        match self {
            Self::Runtime(client) => client.request("sshTarget.upsert", &target).await,
            Self::Store(store) => store.upsert_ssh_target(target).await,
        }
    }
}

/// `add` only creates: an upsert under an existing id used to replace the
/// whole record, silently dropping fields the caller did not repeat.
async fn add_ssh_target_from_cli(
    args: &RuntimeDirArgs,
    target: SshTarget,
) -> anyhow::Result<SshTarget> {
    let mut records = SshTargetRecords::open(args).await?;
    if records.find(&target.id).await?.is_some() {
        anyhow::bail!(
            "ssh target already exists: {id}. Change it with `alera ssh-target update --id {id}`, or remove it first.",
            id = target.id
        );
    }
    records.save(target).await
}

async fn update_ssh_target_from_cli(
    args: &RuntimeDirArgs,
    update: SshTargetUpdateArgs,
) -> anyhow::Result<SshTarget> {
    let mut records = SshTargetRecords::open(args).await?;
    let existing = records
        .find(&update.id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("ssh target not found: {}", update.id))?;
    let target = apply_ssh_target_update(existing, update, Utc::now());
    reject_password_ssh_bootstrap_auth(target.auth_kind)?;
    records.save(target).await
}

/// Only the flags given change. Install and status fields are kept, because
/// they describe the runtime already on the host.
pub(super) fn apply_ssh_target_update(
    mut target: SshTarget,
    update: SshTargetUpdateArgs,
    now: chrono::DateTime<Utc>,
) -> SshTarget {
    if let Some(alias) = update.alias {
        target.alias = alias;
    }
    if let Some(host) = update.host {
        target.host = host;
    }
    if let Some(port) = update.port {
        target.port = port;
    }
    if let Some(username) = update.username {
        target.username = username;
    }
    if let Some(platform) = update.platform {
        target.platform = non_empty(platform);
    }
    if let Some(arch) = update.arch {
        target.arch = non_empty(arch);
    }
    if let Some(auth_kind) = update.auth_kind {
        target.auth_kind = ssh_auth_kind(auth_kind);
    }
    if let Some(projects_dir) = update.projects_dir {
        target.projects_dir = non_empty(projects_dir);
    }
    if let Some(identity_file) = update.identity_file {
        target.identity_file = non_empty(identity_file);
    }
    target.updated_at = now;
    target
}

fn non_empty(value: String) -> Option<String> {
    Some(value.trim().to_string()).filter(|value| !value.is_empty())
}

fn ssh_auth_kind(value: SshAuthKindArg) -> SshAuthKind {
    match value {
        SshAuthKindArg::Password => SshAuthKind::Password,
        SshAuthKindArg::Key => SshAuthKind::Key,
        SshAuthKindArg::Agent => SshAuthKind::Agent,
    }
}

fn ssh_target_from_args(args: SshTargetAddArgs) -> SshTarget {
    let now = Utc::now();
    SshTarget {
        id: args.id.unwrap_or_else(|| Uuid::new_v4().to_string()),
        alias: args.alias,
        host: args.host,
        port: args.port,
        username: args.username,
        platform: args.platform,
        arch: args.arch,
        auth_kind: ssh_auth_kind(args.auth_kind),
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
        projects_dir: args.projects_dir.and_then(non_empty),
        identity_file: args.identity_file.and_then(non_empty),
        runtime_version: None,
        runtime_platform: None,
        runtime_arch: None,
        bootstrap_status: Default::default(),
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    }
}

fn ssh_bootstrap_request_from_plan_args(
    args: SshTargetBootstrapPlanArgs,
) -> anyhow::Result<SshTargetBootstrapRequest> {
    Ok(SshTargetBootstrapRequest {
        target_id: args.id,
        channel: args.channel,
        version: args.version,
        install_dir: args.install_dir,
        platform: args.platform,
        arch: args.arch,
        archive_url: args.archive_url,
        archive_path: host_accessible_optional_path(args.archive_path)?,
        artifact_path: host_accessible_optional_path(args.artifact_path)?,
        manifest_public_key: args.manifest_public_key,
        restart_runtime: false,
        force: false,
    })
}

fn ssh_bootstrap_request_from_args(
    args: SshTargetBootstrapArgs,
) -> anyhow::Result<SshTargetBootstrapRequest> {
    Ok(SshTargetBootstrapRequest {
        target_id: args.id,
        channel: args.channel,
        version: args.version,
        install_dir: args.install_dir,
        platform: args.platform,
        arch: args.arch,
        archive_url: args.archive_url,
        archive_path: host_accessible_optional_path(args.archive_path)?,
        artifact_path: host_accessible_optional_path(args.artifact_path)?,
        manifest_public_key: args.manifest_public_key,
        restart_runtime: args.restart_runtime,
        force: args.force,
    })
}

#[cfg(test)]
#[path = "main_ssh_target_commands_tests.rs"]
mod tests;
