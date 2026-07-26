mod agent_quota;
mod agent_status;
mod cli;
mod cli_orchestration;
mod cli_orchestration_runs;
mod cli_orchestration_terminal;
mod cli_orchestration_timeouts;
#[cfg(test)]
mod cli_tests;
mod computer_commands;
mod computer_output;
mod computer_use;
mod host_tools;
mod login_shell_environment;
mod managed_workspace;
mod mobile_access;
mod orchestration_command_summaries;
mod orchestration_commands;
mod orchestration_terminal_commands;
mod project_management;
mod runtime_archive;
mod runtime_commands;
mod runtime_host_client;
mod ssh_bootstrap;
mod tailscale;
mod terminal_alias_commands;
mod terminal_host;
mod workspace_pinning;

mod workspace_registration;

use std::future::Future;
use std::io::Read;
use std::path::{Path, PathBuf};

use alera_core::runtime::{
    CascadePreview, MobileAccessSettings, MobileEndpointMode, Project, ProjectKind, RuntimeStore,
    SshAuthKind, SshTarget, WorkspaceTabRecord, WorkspaceTag,
};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use chrono::Utc;
use clap::Parser;
use serde::{de::DeserializeOwned, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::cli::{
    CascadePreviewArgs, Cli, Command, IdArgs, ProjectAction, ProjectAddArgs, ProjectCommand,
    ProjectKindArg, RuntimeDirArgs, SshAuthKindArg, SshTargetAction, SshTargetAddArgs,
    SshTargetBootstrapArgs, SshTargetBootstrapPlanArgs, SshTargetCommand, SshTargetStatusArgs,
    TabAction, TabCommand, TabCreateArgs, TerminalHostArgs, WorkspaceAction, WorkspaceAddArgs,
    WorkspaceCommand,
};
use crate::cli::{MobileAction, MobileCommand, MobileDevicesAction, MobilePairingAction};
use crate::cli::{TerminalAction, TerminalCommand};
use crate::mobile_access::{
    cancel_mobile_pairing_offer, list_mobile_devices, mobile_status, pair_mobile_device,
    rename_mobile_device, revoke_mobile_device, update_mobile_settings, MobileDevicePairRequest,
    MobileDeviceSummary, MobilePairingCreateRequest, MobilePairingOfferPayload,
    MobileSettingsUpdateRequest,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::ssh_bootstrap::{
    build_ssh_bootstrap_plan, new_bootstrap_job_id, run_ssh_bootstrap, SshTargetBootstrapRequest,
};
use crate::terminal_host::protocol::TerminalHostConfig;
use crate::terminal_host::server::run_terminal_host_server;

/// Usage-error exit code, matching the Dart CLI (`_usageExitCode`).
const USAGE_EXIT_CODE: i32 = 64;
const SUPPORTED_TAB_KINDS: &[&str] = &[
    "terminal",
    "editor",
    "markdownViewer",
    "pdf",
    "gitDiff",
    "browser",
];

#[tokio::main]
async fn main() {
    std::process::exit(run().await);
}

async fn run() -> i32 {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error) => {
            let _ = error.print();
            // Help/version requests exit cleanly; real usage errors use code 64.
            return if error.use_stderr() {
                USAGE_EXIT_CODE
            } else {
                0
            };
        }
    };

    match cli.command {
        Command::RuntimeHost(args) => run_terminal_host(args).await,
        Command::RuntimeProxy => agent_quota::run_runtime_proxy().await,
        Command::Version(command) => run_version_command(command).await,
        Command::TerminalHost(args) => run_terminal_host(args).await,
        Command::Runtime(command) => runtime_commands::run_runtime_command(command).await,
        Command::Project(command) => run_project_command(command).await,
        Command::Workspace(command) => run_workspace_command(command).await,
        Command::Tag(command) => run_tag_command(command).await,
        Command::Tab(command) => run_tab_command(command).await,
        Command::Terminal(command) => run_terminal_command(command).await,
        Command::SshTarget(command) => run_ssh_target_command(command).await,
        Command::Mobile(command) => run_mobile_command(command).await,
        Command::Computer(command) => computer_commands::run(command).await,
        Command::Orchestration(command) => {
            orchestration_commands::run_orchestration_command(command).await
        }
    }
}

async fn run_terminal_command(command: TerminalCommand) -> i32 {
    let required_capability = terminal_alias_commands::required_capability(&command.action);
    let client = match required_capability {
        Some(capability) => {
            RuntimeHostRpcClient::connect_or_start_with_required_capability(
                &runtime_dir(&command.runtime),
                capability,
            )
            .await
        }
        None => runtime_host_required(&command.runtime).await,
    };
    let mut client = match client {
        Ok(client) => client,
        Err(error) => return print_error(error),
    };
    match command.action {
        action @ (TerminalAction::List(_)
        | TerminalAction::Show(_)
        | TerminalAction::Wait(_)
        | TerminalAction::Prune(_)) => {
            terminal_alias_commands::run(&mut client, action, command.output.json).await
        }
        TerminalAction::Read(args) => match client
            .request_value(
                "terminal.read",
                &json!({ "sessionId": args.handle, "cursor": args.cursor, "maxBytes": args.max_bytes }),
            )
            .await
        {
            Ok(value) => {
                if command.output.json {
                    print_value(&value, true, "terminal output read");
                } else if let Some(text) = value.get("text").and_then(Value::as_str) {
                    print!("{text}");
                }
                0
            }
            Err(error) => print_error(error),
        },
        TerminalAction::Write(args) => {
            let bytes = if let Some(text) = args.text {
                text.into_bytes()
            } else if let Some(path) = args.file {
                match std::fs::read(path) {
                    Ok(bytes) => bytes,
                    Err(error) => return print_error(error),
                }
            } else if args.stdin {
                let mut bytes = Vec::new();
                if let Err(error) = std::io::stdin().read_to_end(&mut bytes) {
                    return print_error(error);
                }
                bytes
            } else {
                return required_option_error("", "text, --file, or --stdin").unwrap_or(USAGE_EXIT_CODE);
            };
            match client
                .request_value(
                    "write",
                    &json!({
                        "sessionId": args.handle,
                        "dataBase64": STANDARD.encode(bytes),
                        "deferredEnter": args.enter || args.submit,
                        "bracketedPaste": args.submit,
                    }),
                )
                .await
            {
                Ok(value) => {
                    print_value(&value, command.output.json, "terminal input written");
                    0
                }
                Err(error) => print_error(error),
            }
        }
    }
}

async fn run_version_command(command: crate::cli::VersionCommand) -> i32 {
    let commit = option_env!("ALERA_BUILD_COMMIT").unwrap_or("unknown");
    let version = option_env!("ALERA_BUILD_VERSION").unwrap_or(env!("CARGO_PKG_VERSION"));
    let host_status = match RuntimeHostRpcClient::connect(&runtime_dir(&command.runtime)).await {
        Ok(Some(mut client)) => client.request_value("status.get", &json!({})).await.ok(),
        Ok(None) | Err(_) => None,
    };
    let payload = json!({
        "cliVersion": version,
        "cliCommit": commit,
        "runtimeHostAvailable": host_status.is_some(),
        "runtimeHostVersion": host_status.as_ref().and_then(|value| value.get("runtimeHostVersion")),
        "runtimeHostCommit": host_status.as_ref().and_then(|value| value.get("runtimeHostCommit")),
        "terminalHostProtocolVersion": terminal_host::protocol::PROTOCOL_VERSION,
        "runtimeHostProtocolVersion": host_status.as_ref().and_then(|value| value.get("protocolVersion")),
        "orchestrationProtocolVersion": terminal_host::protocol::ORCHESTRATION_PROTOCOL_VERSION,
        "runtimeHostOrchestrationProtocolVersion": host_status.as_ref().and_then(|value| value.get("orchestrationProtocolVersion")),
        "dispatchPreambleVersion": terminal_host::protocol::DISPATCH_PREAMBLE_VERSION,
        "runtimeHostDispatchPreambleVersion": host_status.as_ref().and_then(|value| value.get("dispatchPreambleVersion")),
        "skillVersion": terminal_host::protocol::ORCHESTRATION_SKILL_VERSION,
        "runtimeHostSkillVersion": host_status.as_ref().and_then(|value| value.get("skillVersion")),
    });
    print_value(&payload, command.output.json, "Alera version information");
    0
}

async fn run_terminal_host(args: TerminalHostArgs) -> i32 {
    let runtime_dir = args.runtime_dir.trim().to_string();
    let control_file = args.control_file.trim().to_string();
    let token = args.token.trim().to_string();
    if let Some(code) = required_option_error(&runtime_dir, "runtime-dir")
        .or_else(|| required_option_error(&control_file, "control-file"))
        .or_else(|| required_option_error(&token, "token"))
    {
        return code;
    }

    let config = TerminalHostConfig {
        empty_shutdown_delay_seconds: args.empty_shutdown_delay_seconds,
        detached_session_shutdown_delay_seconds: args.detached_session_shutdown_delay_seconds,
        scrollback_bytes: args.scrollback_bytes,
        // Standalone host: the app overrides this in its `configure`.
        restore_snapshot_bytes: args.scrollback_bytes,
        persistent: args.persistent,
        login_shell: terminal_host::protocol::default_login_shell(),
    };

    match run_terminal_host_server(
        PathBuf::from(runtime_dir),
        PathBuf::from(control_file),
        token,
        config,
    )
    .await
    {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn required_option_error(value: &str, name: &str) -> Option<i32> {
    if value.is_empty() {
        eprintln!("Missing required option --{name}.");
        Some(USAGE_EXIT_CODE)
    } else {
        None
    }
}

async fn run_project_command(command: ProjectCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        ProjectAction::List => match open_store(&runtime).await {
            Ok(store) => match store.list_projects().await {
                Ok(projects) => print_value(
                    &json!({ "kind": "projects", "items": projects, "filters": {} }),
                    json_output,
                    "projects listed",
                ),
                Err(error) => return print_error(error),
            },
            Err(error) => return print_error(error),
        },
        ProjectAction::Add(args) => {
            let project = project_from_args(args);
            let fallback_project = project.clone();
            match runtime_host_or_store(&runtime, "project.upsert", &project, |store| async move {
                store.upsert_project(fallback_project).await
            })
            .await
            {
                Ok(project) => print_value(&project, json_output, "project saved"),
                Err(error) => return print_error(error),
            }
        }
        ProjectAction::Remove(IdArgs { id }) => {
            let payload = json!({ "id": id });
            let removed_id = id.clone();
            match runtime_host_or_store_unit(
                &runtime,
                "project.remove",
                &payload,
                |store| async move { store.remove_project(&id).await },
            )
            .await
            {
                Ok(()) => print_value(&json!({ "id": removed_id }), json_output, "project removed"),
                Err(error) => return print_error(error),
            }
        }
    }
    0
}

async fn run_workspace_command(command: WorkspaceCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        WorkspaceAction::List(args) => {
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            let result = if args.all {
                store.list_all_workspaces().await
            } else if let Some(project_id) = args.project_id {
                store.list_workspaces(&project_id).await
            } else {
                eprintln!("Missing --project-id or --all.");
                return USAGE_EXIT_CODE;
            };
            match result {
                Ok(workspaces) => print_value(
                    &json!({ "kind": "workspaces", "items": workspaces, "filters": {} }),
                    json_output,
                    "workspaces listed",
                ),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Add(args) => {
            let payload = match workspace_add_payload(args) {
                Ok(payload) => payload,
                Err(error) => return print_error(error),
            };
            let value: Value = match runtime_host_required(&runtime).await {
                Ok(mut client) => match client
                    .request_value("workspace.createManaged", &payload)
                    .await
                {
                    Ok(value) => value,
                    Err(error) => return print_error(error),
                },
                Err(error) => return print_error(error),
            };
            print_value(&value, json_output, "workspace created");
        }
        WorkspaceAction::Remove(args) => {
            let delete_branch = if args.delete_branch {
                Some(true)
            } else if args.keep_branch {
                Some(false)
            } else {
                None
            };
            let payload = json!({
                "id": args.id,
                "deleteBranch": delete_branch,
            });
            let value: Value = match runtime_host_required(&runtime).await {
                Ok(mut client) => match client
                    .request_value("workspace.removeManaged", &payload)
                    .await
                {
                    Ok(value) => value,
                    Err(error) => return print_error(error),
                },
                Err(error) => return print_error(error),
            };
            print_value(&value, json_output, "workspace removed");
        }
        WorkspaceAction::Register(args) => {
            let workspace = workspace_registration::from_args(args);
            let fallback_workspace = workspace.clone();
            match runtime_host_or_store(
                &runtime,
                "workspace.upsert",
                &workspace,
                |store| async move { store.upsert_workspace(fallback_workspace).await },
            )
            .await
            {
                Ok(workspace) => print_value(&workspace, json_output, "workspace registered"),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Unregister(IdArgs { id }) => {
            let payload = json!({ "id": id, "cascadeTabs": true });
            let removed_id = id.clone();
            match runtime_host_or_store_unit(
                &runtime,
                "workspace.remove",
                &payload,
                |store| async move { store.remove_workspace(&id, true).await },
            )
            .await
            {
                Ok(()) => print_value(
                    &json!({ "id": removed_id }),
                    json_output,
                    "workspace unregistered",
                ),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Pin(IdArgs { id }) => {
            return workspace_pinning::run(runtime_dir(&runtime), json_output, id, true).await
        }
        WorkspaceAction::Unpin(IdArgs { id }) => {
            return workspace_pinning::run(runtime_dir(&runtime), json_output, id, false).await
        }
        WorkspaceAction::Link(args) => {
            let payload = json!({
                "parentWorkspaceId": args.parent_workspace_id,
                "childWorkspaceId": args.child_workspace_id,
            });
            match runtime_host_or_store(
                &runtime,
                "workspaceRelation.link",
                &payload,
                |store| async move {
                    store
                        .link_workspaces(&args.parent_workspace_id, &args.child_workspace_id)
                        .await
                },
            )
            .await
            {
                Ok(relation) => print_value(&relation, json_output, "workspace linked"),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Unlink(args) => {
            let payload = json!({
                "parentWorkspaceId": args.parent_workspace_id,
                "childWorkspaceId": args.child_workspace_id,
            });
            match runtime_host_or_store_unit(
                &runtime,
                "workspaceRelation.unlink",
                &payload,
                |store| async move {
                    store
                        .unlink_workspaces(&args.parent_workspace_id, &args.child_workspace_id)
                        .await
                },
            )
            .await
            {
                Ok(()) => print_value(&payload, json_output, "workspace unlinked"),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Tag(args) => {
            let payload = json!({ "workspaceId": args.workspace_id, "tagId": args.tag_id });
            match runtime_host_or_store_unit(
                &runtime,
                "workspaceTag.assign",
                &payload,
                |store| async move { store.assign_tag(&args.workspace_id, &args.tag_id).await },
            )
            .await
            {
                Ok(()) => print_value(&payload, json_output, "tag assigned"),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Untag(args) => {
            let payload = json!({ "workspaceId": args.workspace_id, "tagId": args.tag_id });
            match runtime_host_or_store_unit(
                &runtime,
                "workspaceTag.unassign",
                &payload,
                |store| async move { store.unassign_tag(&args.workspace_id, &args.tag_id).await },
            )
            .await
            {
                Ok(()) => print_value(&payload, json_output, "tag removed"),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::CascadePreview(args) => {
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            match cascade_preview(&store, args).await {
                Ok(preview) => print_value(&preview, json_output, "cascade preview ready"),
                Err(error) => return print_error(error),
            }
        }
    }
    0
}

async fn run_tag_command(command: crate::cli::TagCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        crate::cli::TagAction::List => match open_store(&runtime).await {
            Ok(store) => match store.list_tags().await {
                Ok(tags) => print_value(
                    &json!({ "kind": "tags", "items": tags, "filters": {} }),
                    json_output,
                    "tags listed",
                ),
                Err(error) => return print_error(error),
            },
            Err(error) => return print_error(error),
        },
        crate::cli::TagAction::Upsert(args) => {
            let now = Utc::now();
            let tag = WorkspaceTag {
                id: args.id.unwrap_or_else(|| Uuid::new_v4().to_string()),
                name: args.name,
                color: args.color,
                created_at: now,
                updated_at: now,
            };
            let fallback_tag = tag.clone();
            match runtime_host_or_store(&runtime, "workspaceTag.upsert", &tag, |store| async move {
                store.upsert_tag(fallback_tag).await
            })
            .await
            {
                Ok(tag) => print_value(&tag, json_output, "tag saved"),
                Err(error) => return print_error(error),
            }
        }
        crate::cli::TagAction::Remove(IdArgs { id }) => {
            let payload = json!({ "id": id });
            let removed_id = id.clone();
            match runtime_host_or_store_unit(
                &runtime,
                "workspaceTag.remove",
                &payload,
                |store| async move { store.remove_tag(&id).await },
            )
            .await
            {
                Ok(()) => print_value(&json!({ "id": removed_id }), json_output, "tag removed"),
                Err(error) => return print_error(error),
            }
        }
    }
    0
}

async fn run_tab_command(command: TabCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        TabAction::List(args) => match open_store(&runtime).await {
            Ok(store) => match store.list_workspace_tabs(&args.workspace_id).await {
                Ok(tabs) => print_value(
                    &json!({ "kind": "tabs", "items": tabs, "filters": { "workspaceId": args.workspace_id } }),
                    json_output,
                    "tabs listed",
                ),
                Err(error) => return print_error(error),
            },
            Err(error) => return print_error(error),
        },
        TabAction::Create(args) => {
            let tab = match tab_from_args(args) {
                Ok(tab) => tab,
                Err(error) => {
                    eprintln!("{error}");
                    return USAGE_EXIT_CODE;
                }
            };
            let fallback_tab = tab.clone();
            match runtime_host_or_store(&runtime, "tab.upsert", &tab, |store| async move {
                store.upsert_workspace_tab(fallback_tab).await
            })
            .await
            {
                Ok(tab) => print_value(&tab, json_output, "tab saved"),
                Err(error) => return print_error(error),
            }
        }
        TabAction::Remove(IdArgs { id }) => {
            let payload = json!({ "id": id });
            let removed_id = id.clone();
            match runtime_host_or_store_unit(&runtime, "tab.remove", &payload, |store| async move {
                store.remove_workspace_tab(&id).await
            })
            .await
            {
                Ok(()) => print_value(&json!({ "id": removed_id }), json_output, "tab removed"),
                Err(error) => return print_error(error),
            }
        }
    }
    0
}

async fn run_ssh_target_command(command: SshTargetCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        SshTargetAction::List => match open_store(&runtime).await {
            Ok(store) => match store.list_ssh_targets().await {
                Ok(targets) => print_value(
                    &json!({ "kind": "sshTargets", "items": targets, "filters": {} }),
                    json_output,
                    "ssh targets listed",
                ),
                Err(error) => return print_error(error),
            },
            Err(error) => return print_error(error),
        },
        SshTargetAction::Add(args) => {
            let target = ssh_target_from_args(args);
            match upsert_ssh_target_from_cli(&runtime, target).await {
                Ok(target) => print_value(&target, json_output, "ssh target saved"),
                Err(error) => return print_error(error),
            }
        }
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
        SshTargetAction::Status(SshTargetStatusArgs { id }) => {
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            let value = if let Some(id) = id {
                match store.find_ssh_target(&id).await {
                    Ok(Some(target)) => json!(target),
                    Ok(None) => {
                        eprintln!("ssh target not found: {id}");
                        return 1;
                    }
                    Err(error) => return print_error(error),
                }
            } else {
                match store.list_ssh_targets().await {
                    Ok(targets) => json!(targets),
                    Err(error) => return print_error(error),
                }
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
            let value: Value = if let Some(mut client) =
                match RuntimeHostRpcClient::connect(&runtime_dir(&runtime)).await {
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

async fn run_mobile_command(command: MobileCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        MobileAction::Status => {
            let runtime_host_active =
                match RuntimeHostRpcClient::connect_mobile(&runtime_dir(&runtime)).await {
                    Ok(client) => client.is_some(),
                    Err(_) => false,
                };
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            match mobile_status(&store, Some(runtime_host_active)).await {
                Ok(status) => print_value(&status, json_output, "mobile status ready"),
                Err(error) => return print_error(error),
            }
        }
        MobileAction::Enable(args) => {
            let request = MobileSettingsUpdateRequest {
                enabled: Some(true),
                bind_host: args.bind_host,
                port: args.port,
                endpoint_mode: args.tailscale.then_some(MobileEndpointMode::Tailscale),
            };
            match mobile_runtime_host_request::<MobileAccessSettings, _>(
                &runtime,
                "mobile.settings.update",
                &request,
            )
            .await
            {
                Ok(settings) => print_value(&settings, json_output, "mobile access enabled"),
                Err(error) => return print_error(error),
            }
        }
        MobileAction::Disable => {
            let request = MobileSettingsUpdateRequest {
                enabled: Some(false),
                bind_host: None,
                port: None,
                endpoint_mode: None,
            };
            let fallback_request = request.clone();
            match mobile_runtime_host_or_store(
                &runtime,
                "mobile.settings.update",
                &request,
                |store| async move { update_mobile_settings(&store, fallback_request).await },
            )
            .await
            {
                Ok(settings) => print_value(&settings, json_output, "mobile access disabled"),
                Err(error) => return print_error(error),
            }
        }
        MobileAction::Pairing(command) => match command.action {
            MobilePairingAction::Create(args) => {
                let request = MobilePairingCreateRequest {
                    endpoint: args.endpoint,
                    device_name: args.device_name,
                    expires_minutes: args.expires_minutes,
                };
                match mobile_runtime_host_request::<MobilePairingOfferPayload, _>(
                    &runtime,
                    "mobile.pairing.create",
                    &request,
                )
                .await
                {
                    Ok(offer) => print_value(&offer, json_output, "mobile pairing offer created"),
                    Err(error) => return print_error(error),
                }
            }
            MobilePairingAction::Claim(args) => {
                let request = MobileDevicePairRequest {
                    pairing_id: args.pairing_id,
                    pairing_secret: args.pairing_secret,
                    device_name: args.device_name,
                    public_key_b64: args.public_key_b64,
                };
                let fallback_request = request.clone();
                match mobile_runtime_host_or_store(
                    &runtime,
                    "mobile.device.pair",
                    &request,
                    |store| async move { pair_mobile_device(&store, fallback_request).await },
                )
                .await
                {
                    Ok(device) => print_value(&device, json_output, "mobile device paired"),
                    Err(error) => return print_error(error),
                }
            }
            MobilePairingAction::Cancel(IdArgs { id }) => {
                let payload = json!({ "id": id });
                let cancelled_id = id.clone();
                match mobile_runtime_host_or_store_unit(
                    &runtime,
                    "mobile.pairing.cancel",
                    &payload,
                    |store| async move { cancel_mobile_pairing_offer(&store, &id).await },
                )
                .await
                {
                    Ok(()) => print_value(
                        &json!({ "id": cancelled_id }),
                        json_output,
                        "mobile pairing offer cancelled",
                    ),
                    Err(error) => return print_error(error),
                }
            }
        },
        MobileAction::Devices(command) => {
            match command.action {
                MobileDevicesAction::List(args) => {
                    let payload = json!({ "includeRevoked": args.include_revoked });
                    match mobile_runtime_host_or_store(
                    &runtime,
                    "mobile.device.list",
                    &payload,
                    |store| async move { list_mobile_devices(&store, args.include_revoked).await },
                )
                .await
                {
                    Ok(devices) => print_value(&json!({ "kind": "mobileDevices", "items": devices, "filters": { "includeRevoked": args.include_revoked } }), json_output, "mobile devices listed"),
                    Err(error) => return print_error(error),
                }
                }
                MobileDevicesAction::Rename(args) => {
                    let payload = json!({ "id": args.id, "displayName": args.name });
                    match mobile_runtime_host_or_store::<MobileDeviceSummary, _, _>(
                        &runtime,
                        "mobile.device.rename",
                        &payload,
                        |store| async move {
                            rename_mobile_device(&store, &args.id, &args.name).await
                        },
                    )
                    .await
                    {
                        Ok(device) => print_value(&device, json_output, "mobile device renamed"),
                        Err(error) => return print_error(error),
                    }
                }
                MobileDevicesAction::Revoke(IdArgs { id }) => {
                    let payload = json!({ "id": id });
                    let revoked_id = id.clone();
                    match mobile_runtime_host_or_store_unit(
                        &runtime,
                        "mobile.device.revoke",
                        &payload,
                        |store| async move { revoke_mobile_device(&store, &id).await },
                    )
                    .await
                    {
                        Ok(()) => print_value(
                            &json!({ "id": revoked_id }),
                            json_output,
                            "mobile device revoked",
                        ),
                        Err(error) => return print_error(error),
                    }
                }
            }
        }
    }
    0
}

async fn runtime_host_or_store<T, P, Fut>(
    args: &RuntimeDirArgs,
    request_type: &str,
    payload: &P,
    store_operation: impl FnOnce(RuntimeStore) -> Fut,
) -> anyhow::Result<T>
where
    T: DeserializeOwned,
    P: Serialize + ?Sized,
    Fut: Future<Output = anyhow::Result<T>>,
{
    if let Some(mut client) = RuntimeHostRpcClient::connect(&runtime_dir(args)).await? {
        return client.request(request_type, payload).await;
    }
    store_operation(open_store(args).await?).await
}

async fn runtime_host_required(args: &RuntimeDirArgs) -> anyhow::Result<RuntimeHostRpcClient> {
    RuntimeHostRpcClient::connect_or_start(&runtime_dir(args)).await
}

async fn mobile_runtime_host_required(
    args: &RuntimeDirArgs,
) -> anyhow::Result<RuntimeHostRpcClient> {
    RuntimeHostRpcClient::connect_or_start_mobile(&runtime_dir(args)).await
}

async fn mobile_runtime_host_request<T, P>(
    args: &RuntimeDirArgs,
    request_type: &str,
    payload: &P,
) -> anyhow::Result<T>
where
    T: DeserializeOwned,
    P: Serialize + ?Sized,
{
    let mut client = mobile_runtime_host_required(args).await?;
    client.request(request_type, payload).await
}

async fn mobile_runtime_host_or_store<T, P, Fut>(
    args: &RuntimeDirArgs,
    request_type: &str,
    payload: &P,
    store_operation: impl FnOnce(RuntimeStore) -> Fut,
) -> anyhow::Result<T>
where
    T: DeserializeOwned,
    P: Serialize + ?Sized,
    Fut: Future<Output = anyhow::Result<T>>,
{
    if let Some(mut client) = RuntimeHostRpcClient::connect_mobile(&runtime_dir(args)).await? {
        return client.request(request_type, payload).await;
    }
    store_operation(open_store(args).await?).await
}

async fn mobile_runtime_host_or_store_unit<P, Fut>(
    args: &RuntimeDirArgs,
    request_type: &str,
    payload: &P,
    store_operation: impl FnOnce(RuntimeStore) -> Fut,
) -> anyhow::Result<()>
where
    P: Serialize + ?Sized,
    Fut: Future<Output = anyhow::Result<()>>,
{
    if let Some(mut client) = RuntimeHostRpcClient::connect_mobile(&runtime_dir(args)).await? {
        client.request_value(request_type, payload).await?;
        return Ok(());
    }
    store_operation(open_store(args).await?).await
}

async fn upsert_ssh_target_from_cli(
    args: &RuntimeDirArgs,
    mut target: SshTarget,
) -> anyhow::Result<SshTarget> {
    if let Some(mut client) = RuntimeHostRpcClient::connect(&runtime_dir(args)).await? {
        preserve_ssh_target_install_dir_from_runtime(&mut client, &mut target).await?;
        return client.request("sshTarget.upsert", &target).await;
    }
    let store = open_store(args).await?;
    preserve_ssh_target_install_dir_from_store(&store, &mut target).await?;
    store.upsert_ssh_target(target).await
}

async fn preserve_ssh_target_install_dir_from_runtime(
    client: &mut RuntimeHostRpcClient,
    target: &mut SshTarget,
) -> anyhow::Result<()> {
    if target.install_dir.is_some() {
        return Ok(());
    }
    let targets: Vec<SshTarget> = client.request("sshTarget.list", &json!({})).await?;
    if let Some(existing) = targets
        .into_iter()
        .find(|existing| existing.id == target.id)
    {
        target.install_dir = existing.install_dir;
    }
    Ok(())
}

async fn preserve_ssh_target_install_dir_from_store(
    store: &RuntimeStore,
    target: &mut SshTarget,
) -> anyhow::Result<()> {
    if target.install_dir.is_some() {
        return Ok(());
    }
    if let Some(existing) = store.find_ssh_target(&target.id).await? {
        target.install_dir = existing.install_dir;
    }
    Ok(())
}

async fn runtime_host_or_store_unit<P, Fut>(
    args: &RuntimeDirArgs,
    request_type: &str,
    payload: &P,
    store_operation: impl FnOnce(RuntimeStore) -> Fut,
) -> anyhow::Result<()>
where
    P: Serialize + ?Sized,
    Fut: Future<Output = anyhow::Result<()>>,
{
    if let Some(mut client) = RuntimeHostRpcClient::connect(&runtime_dir(args)).await? {
        client.request_value(request_type, payload).await?;
        return Ok(());
    }
    store_operation(open_store(args).await?).await
}

async fn open_store(args: &RuntimeDirArgs) -> anyhow::Result<RuntimeStore> {
    RuntimeStore::open(&runtime_dir(args)).await
}

fn runtime_dir(args: &RuntimeDirArgs) -> PathBuf {
    if let Some(dir) = args
        .runtime_dir
        .as_ref()
        .filter(|value| !value.trim().is_empty())
    {
        return PathBuf::from(dir);
    }
    if let Ok(dir) = std::env::var("ALERA_RUNTIME_DIR") {
        if !dir.trim().is_empty() {
            return PathBuf::from(dir);
        }
    }
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());
    Path::new(&home).join(".alera").join("runtime")
}

fn project_from_args(args: ProjectAddArgs) -> Project {
    let now = Utc::now();
    Project {
        id: args.id.unwrap_or_else(|| Uuid::new_v4().to_string()),
        name: args.name,
        repo_path: args.repo_path,
        created_at: now,
        updated_at: now,
        kind: match args.kind {
            ProjectKindArg::GitRepository => ProjectKind::GitRepository,
            ProjectKindArg::Folder => ProjectKind::Folder,
        },
    }
}

fn tab_from_args(args: TabCreateArgs) -> Result<WorkspaceTabRecord, String> {
    let now = Utc::now();
    let id = Uuid::new_v4().to_string();
    let kind = SUPPORTED_TAB_KINDS
        .iter()
        .copied()
        .find(|supported| *supported == args.kind)
        .ok_or_else(|| {
            format!(
                "Unsupported tab kind \"{}\". Supported kinds: {}.",
                args.kind,
                SUPPORTED_TAB_KINDS.join(", ")
            )
        })?;
    if (args.command.is_some() || args.spawn) && kind != "terminal" {
        return Err("--command and --spawn are only supported for terminal tabs.".to_string());
    }
    let mut payload = serde_json::Map::new();
    payload.insert("terminalSessionId".to_string(), json!(id));
    if let Some(command) = args
        .command
        .as_deref()
        .map(str::trim)
        .filter(|command| !command.is_empty())
    {
        payload.insert("initialCommand".to_string(), json!(command));
    }
    if args.spawn {
        payload.insert("spawnOnCreate".to_string(), json!(true));
    }
    Ok(WorkspaceTabRecord {
        id: id.clone(),
        workspace_id: args.workspace_id,
        kind: kind.to_string(),
        title: args.title,
        created_at: now,
        updated_at: now,
        payload: Value::Object(payload),
    })
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
        auth_kind: match args.auth_kind {
            SshAuthKindArg::Password => SshAuthKind::Password,
            SshAuthKindArg::Key => SshAuthKind::Key,
            SshAuthKindArg::Agent => SshAuthKind::Agent,
        },
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
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
    })
}

fn host_accessible_optional_path(value: Option<String>) -> anyhow::Result<Option<PathBuf>> {
    value
        .map(|path| {
            std::env::current_dir().map(|current_dir| host_accessible_path(path, &current_dir))
        })
        .transpose()
        .map_err(Into::into)
}

fn host_accessible_path(value: String, current_dir: &Path) -> PathBuf {
    let path = PathBuf::from(value);
    if path.is_absolute() {
        path
    } else {
        current_dir.join(path)
    }
}

fn workspace_add_payload(args: WorkspaceAddArgs) -> anyhow::Result<Value> {
    Ok(json!({
        "id": args.id,
        "projectId": args.project_id,
        "name": args.name,
        "branch": args.branch,
        "sourceBranch": args.source_branch,
        "reuseExistingBranch": args.reuse_existing_branch,
        "workspaceRoot": host_accessible_optional_string_path(args.workspace_root)?,
        "path": host_accessible_optional_string_path(args.path)?,
        "parentWorkspaceId": args.parent_workspace_id,
    }))
}

fn host_accessible_optional_string_path(value: Option<String>) -> anyhow::Result<Option<String>> {
    let Some(value) = value else {
        return Ok(None);
    };
    let Some(path) = normalized_workspace_path_value(&value) else {
        return Ok(None);
    };
    let current_dir = std::env::current_dir()?;
    Ok(Some(
        host_accessible_path(path, &current_dir)
            .to_string_lossy()
            .into_owned(),
    ))
}

fn normalized_workspace_path_value(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

async fn cascade_preview(
    store: &RuntimeStore,
    args: CascadePreviewArgs,
) -> anyhow::Result<CascadePreview> {
    store
        .cascade_preview(
            &args.workspace_ids,
            &args.tag_ids,
            args.include_descendants,
            args.include_tags,
        )
        .await
}

pub(crate) fn print_value<T: Serialize>(value: &T, json_output: bool, message: &str) {
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".to_string())
        );
    } else {
        println!("{message}");
    }
}

pub(crate) fn print_error(error: impl std::fmt::Display) -> i32 {
    eprintln!("{error}");
    1
}

#[cfg(test)]
mod main_tests;
