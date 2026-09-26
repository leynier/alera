mod agent_profile_commands;
mod agent_profile_input;
mod agent_profile_launch;
mod agent_prompt_stdin_script;
mod agent_quota;
mod agent_status;
mod automation_autostart;
mod automation_commands;
mod automation_declaration;
mod automation_ssh_precheck;
mod cli;
mod cli_async_runtime;
#[cfg(test)]
mod cli_help_tests;
mod cli_orchestration;
mod cli_orchestration_runs;
mod cli_orchestration_terminal;
mod cli_orchestration_timeouts;
#[cfg(test)]
mod cli_tests;
mod cli_workflow_plans;
mod cli_workflow_recipes;
mod host_tools;
mod hosted_review_retention;
mod hub_federation;
mod issue_commands;
mod issue_tracking;
mod linked_issue_service;
mod login_shell_environment;
mod managed_workspace;
mod managed_workspace_handoff;
#[cfg(test)]
mod managed_workspace_removal_tests;
mod managed_workspace_slug;
mod mobile_access;
mod native_credential_entry;
mod netbird;
mod opencode_auth;
mod orchestration_command_summaries;
mod orchestration_commands;
mod orchestration_contract_commands;
mod orchestration_delegate;
mod orchestration_terminal_commands;
mod owner_precheck_checkout;
mod process_identity;
mod project_branch_catalog;
mod project_checkout_clone;
mod project_checkout_inspection;
mod project_checkout_worktree;
mod project_config_toml;
mod project_file_catalog;
mod project_hosts;
mod project_management;
#[cfg(windows)]
mod pty_job_bootstrap;
mod relocation_owned_worktree;
mod relocation_setup_process;
mod remote_managed_workspace;
mod remote_managed_workspace_remove;
mod remote_managed_workspace_remove_script;
mod remote_owner_enrollment;
mod remote_owner_precheck;
mod remote_owner_recovery;
mod remote_owner_relocation;
mod remote_owner_retirement;
mod remote_owner_setup;
mod remote_owner_terminal;
mod remote_owner_terminal_launch;
mod remote_owner_terminal_lifecycle;
mod remote_owner_terminal_ownership;
mod remote_project_checkout;
mod remote_relocation_recovery;
mod remote_relocation_setup;
mod remote_shared_retirement;
mod remote_terminal_bridge;
mod remote_workspace_files;
mod remote_workspace_owner;
mod remote_workspace_relocation;
mod runtime_archive;
mod runtime_attach;
mod runtime_clear;
mod runtime_commands;
mod runtime_host_client;
mod runtime_host_command;
mod setup_process_cancellation;
mod shared_workspace;
mod shared_workspace_removal;
mod ssh_bootstrap;
mod ssh_remote;
mod ssh_target_status;
mod ssh_windows_command;
mod tab_record_factory;
mod tailscale;
mod terminal_alias_commands;
mod terminal_host;
mod terminal_stdio_mode;
mod voice_commands;
mod windows_path_form;
mod workflow_plan_commands;
mod workflow_recipe_commands;
mod workspace_add;
mod workspace_archive;
mod workspace_buffer_guard_request;
mod workspace_context;
mod workspace_handoff;
mod workspace_issue_commands;
mod workspace_pinning;
mod workspace_pr_watch_commands;
mod workspace_registration;
mod workspace_relocation_recovery;
mod workspace_relocation_setup;
mod workspace_removal_dependencies;
mod workspace_rename;
mod workspace_sections;
mod workspace_setup_command;
mod workspace_start;
mod worktree_copy;
mod worktree_include;
mod worktree_setup;
mod worktree_setup_process;
mod worktree_setup_script;
use std::future::Future;
use std::io::Read;
use std::path::{Path, PathBuf};

use alera_core::runtime::{
    CascadePreview, MobileAccessSettings, MobileEndpointMode, ProjectKind, RuntimeStore,
    SshAuthKind, SshTarget, WorkspaceTag,
};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use chrono::Utc;
use clap::Parser;
use serde::{de::DeserializeOwned, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::cli::{
    CascadePreviewArgs, Cli, Command, IdArgs, ProjectAction, ProjectCommand, ProjectKindArg,
    RuntimeDirArgs, SshAuthKindArg, SshTargetAction, SshTargetAddArgs, SshTargetBootstrapArgs,
    SshTargetBootstrapPlanArgs, SshTargetCommand, SshTargetLinkArgs, SshTargetStatusArgs,
    TabAction, TabCommand, WorkspaceAction, WorkspaceCommand,
};
use crate::cli::{MobileAction, MobileCommand, MobileDevicesAction, MobilePairingAction};
use crate::cli::{TerminalAction, TerminalCommand};
use crate::mobile_access::{
    cancel_mobile_pairing_offer, delete_mobile_device, list_mobile_devices, mobile_status,
    pair_mobile_device, rename_mobile_device, revoke_mobile_device, update_mobile_settings,
    MobileDevicePairRequest, MobileDeviceSummary, MobilePairingCreateRequest,
    MobilePairingOfferPayload, MobileSettingsUpdateRequest,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::ssh_bootstrap::{
    build_ssh_bootstrap_plan, new_bootstrap_job_id, reject_password_ssh_bootstrap_auth,
    run_ssh_bootstrap, SshTargetBootstrapRequest,
};
use crate::ssh_target_status::{collect_ssh_target_status, LiveSshTargetProbe};
use crate::tab_record_factory::tab_from_args;

/// Usage-error exit code, matching the Dart CLI (`_usageExitCode`).
const USAGE_EXIT_CODE: i32 = 64;

fn main() {
    #[cfg(windows)]
    if pty_job_bootstrap::is_invocation() {
        std::process::exit(pty_job_bootstrap::run());
    }
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error) => {
            let _ = error.print();
            std::process::exit(if error.use_stderr() {
                USAGE_EXIT_CODE
            } else {
                0
            });
        }
    };
    let runtime = match cli_async_runtime::build(&cli.command) {
        Ok(runtime) => runtime,
        Err(error) => {
            eprintln!("Failed to initialize the Alera async runtime: {error}");
            std::process::exit(1);
        }
    };
    std::process::exit(runtime.block_on(run(cli)));
}

async fn run(cli: Cli) -> i32 {
    match cli.command {
        Command::RuntimeHost(args) => runtime_host_command::run(args).await,
        Command::AutomationHost(args) => runtime_host_command::run_automation_host(args).await,
        Command::RuntimeProxy => agent_quota::run_runtime_proxy().await,
        Command::RuntimeAttach(args) => match runtime_attach::run(args).await {
            Ok(code) => code,
            Err(error) => print_error(error),
        },
        Command::Version(command) => run_version_command(command).await,
        Command::TerminalHost(args) => runtime_host_command::run(args).await,
        Command::Runtime(command) => runtime_commands::run_runtime_command(command).await,
        Command::Project(command) => run_project_command(command).await,
        Command::Workspace(command) => run_workspace_command(command).await,
        Command::Issue(command) => issue_commands::run(command).await,
        Command::Tag(command) => run_tag_command(command).await,
        Command::Tab(command) => run_tab_command(command).await,
        Command::Terminal(command) => run_terminal_command(command).await,
        Command::SshTarget(command) => run_ssh_target_command(command).await,
        Command::Mobile(command) => run_mobile_command(command).await,

        Command::Automation(command) => automation_commands::run(command).await,
        Command::AgentProfile(command) => agent_profile_commands::run(command).await,
        Command::Orchestration(command) => {
            orchestration_commands::run_orchestration_command(command).await
        }
        Command::Voice(command) => voice_commands::run(command).await,
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

fn required_option_error(value: &str, name: &str) -> Option<i32> {
    if value.is_empty() {
        eprintln!("Missing required option --{name}.");
        Some(USAGE_EXIT_CODE)
    } else {
        None
    }
}

mod main_project_commands;
use main_project_commands::run_project_command;

async fn run_workspace_command(command: WorkspaceCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        WorkspaceAction::List(args) => {
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            if !args.all && args.project_id.is_none() {
                eprintln!("Missing --project-id or --all.");
                return USAGE_EXIT_CODE;
            }
            match crate::hub_federation::read_from_hub(
                &runtime,
                &store,
                "workspace.list",
                json!({ "projectId": args.project_id, "hostId": args.host_id }),
            )
            .await
            {
                Ok(Some(answer)) => {
                    print_value(
                        &json!({
                            "kind": "workspaces",
                            "items": answer["items"],
                            "filters": { "hostId": args.host_id },
                            "source": "hub",
                            "originHostId": answer["originHostId"],
                        }),
                        json_output,
                        "workspaces listed",
                    );
                    return 0;
                }
                Err(error) => return print_error(error),
                Ok(None) => {}
            }
            let result = if args.all {
                store.list_all_workspaces().await
            } else if let Some(project_id) = args.project_id {
                store.list_workspaces(&project_id).await
            } else {
                eprintln!("Missing --project-id or --all.");
                return USAGE_EXIT_CODE;
            };
            let host_id = args
                .host_id
                .as_deref()
                .map(|host_id| crate::ssh_remote::normalized_host_id(Some(host_id)));
            match result {
                Ok(mut workspaces) => {
                    if let Some(host_id) = &host_id {
                        workspaces.retain(|workspace| &workspace.host_id == host_id);
                    }
                    print_value(
                        &json!({
                            "kind": "workspaces",
                            "items": workspaces,
                            "filters": { "hostId": host_id },
                        }),
                        json_output,
                        "workspaces listed",
                    )
                }
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Start(args) => {
            return workspace_start::run(runtime, args, json_output).await;
        }
        WorkspaceAction::HandOff(args) => {
            return workspace_handoff::run_hand_off(runtime, args, json_output).await;
        }
        WorkspaceAction::HandOn(args) => {
            return workspace_handoff::run_hand_on(runtime, args, json_output).await;
        }
        WorkspaceAction::Add(args) => {
            return workspace_add::run(runtime, args, json_output).await;
        }
        WorkspaceAction::Issue(command) => {
            return workspace_issue_commands::run(runtime, command, json_output).await;
        }
        WorkspaceAction::PrWatch(command) => {
            return workspace_pr_watch_commands::run(runtime, command, json_output).await;
        }
        WorkspaceAction::Section(command) => {
            return workspace_sections::run(runtime, command, json_output).await;
        }
        WorkspaceAction::Setup(args) => {
            let client = match runtime_host_required(&runtime).await {
                Ok(client) => client,
                Err(error) => return print_error(error),
            };
            match workspace_setup_command::run(client, args, json_output).await {
                Ok(()) => {}
                Err(exit_code) => return exit_code,
            }
        }
        WorkspaceAction::Recovery(args) => {
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            match store.find_workspace(&args.id).await {
                Ok(Some(workspace)) if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID => {
                    return match remote_relocation_recovery::inspect(
                        &store,
                        workspace,
                        20,
                        &ssh_remote::LiveSshRemoteHost,
                    )
                    .await
                    {
                        Ok(report) => {
                            remote_relocation_recovery::print(&report, json_output);
                            0
                        }
                        Err(error) => print_error(error),
                    };
                }
                Err(error) => return print_error(error),
                _ => {}
            }
            match workspace_relocation_recovery::inspect(&store, &args.id, 20).await {
                Ok(items) => workspace_setup_command::print_recovery(&items, json_output),
                Err(error) => return print_error(error),
            }
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
                "closeSessions": args.close_sessions,
            });
            let value: Value = match runtime_host_required(&runtime).await {
                Ok(mut client) => {
                    let workspace: Value = match client
                        .request_value("workspace.find", &json!({"id": args.id}))
                        .await
                    {
                        Ok(workspace) => workspace,
                        Err(error) => return print_error(error),
                    };
                    if let Err(error) =
                        workspace_removal_dependencies::prepare_cli_removal_dependencies(
                            &mut client,
                            &args.id,
                            args.pause_automations_and_cancel_runs,
                        )
                        .await
                    {
                        return print_error(error);
                    }
                    let operation = if workspace.get("kind").and_then(Value::as_str) == Some("main")
                    {
                        "workspace.removeShared"
                    } else {
                        "workspace.removeManaged"
                    };
                    let removed = if operation == "workspace.removeShared" {
                        workspace_buffer_guard_request::request_with_workspace_buffer_guard(
                            &mut client,
                            "removeShared",
                            &payload,
                        )
                        .await
                    } else {
                        client.request_value(operation, &payload).await
                    };
                    match removed {
                        Ok(value) => value,
                        Err(error) => return print_error(error),
                    }
                }
                Err(error) => return print_error(error),
            };
            print_value(&value, json_output, "workspace removed");
        }
        WorkspaceAction::Register(args) => {
            let workspace = match workspace_registration::from_args(args) {
                Ok(workspace) => workspace,
                Err(error) => return print_error(error),
            };
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
                |store| async move { hosted_review_retention::remove_workspace(store, &id).await },
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
        WorkspaceAction::Rename(args) => {
            return workspace_rename::run(&runtime, args, json_output).await;
        }
        WorkspaceAction::Pin(IdArgs { id }) => {
            return workspace_pinning::run(runtime_dir(&runtime), json_output, id, true).await;
        }
        WorkspaceAction::Unpin(IdArgs { id }) => {
            return workspace_pinning::run(runtime_dir(&runtime), json_output, id, false).await;
        }
        WorkspaceAction::Archive(IdArgs { id }) => {
            return workspace_archive::run(runtime_dir(&runtime), json_output, id, true).await;
        }
        WorkspaceAction::Unarchive(IdArgs { id }) => {
            return workspace_archive::run(runtime_dir(&runtime), json_output, id, false).await;
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
            Ok(store) => match crate::hub_federation::read_from_hub(
                &runtime,
                &store,
                "workspaceTag.list",
                json!({}),
            )
            .await
            {
                Ok(Some(tags)) => print_value(
                    &json!({ "kind": "tags", "items": tags, "filters": {}, "source": "hub" }),
                    json_output,
                    "tags listed",
                ),
                Err(error) => return print_error(error),
                Ok(None) => match store.list_tags().await {
                    Ok(tags) => print_value(
                        &json!({ "kind": "tags", "items": tags, "filters": {} }),
                        json_output,
                        "tags listed",
                    ),
                    Err(error) => return print_error(error),
                },
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
                if let Some(tab) = store.find_workspace_tab(&id).await? {
                    if tab.kind == "terminal" {
                        if let Some(workspace) = store.find_workspace(&tab.workspace_id).await? {
                            if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
                                anyhow::bail!("The Home runtime must be available to verify SSH terminal closure before removing this tab");
                            }
                        }
                    }
                }
                let retentions = hosted_review_retention::for_tab(&store, &id).await;
                store.remove_workspace_tab(&id).await?;
                hosted_review_retention::release(retentions);
                Ok(())
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
            if let Err(error) = reject_password_ssh_bootstrap_auth(target.auth_kind) {
                return print_error(error);
            }
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
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            let value =
                match collect_ssh_target_status(&store, id.as_deref(), &LiveSshTargetProbe).await {
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

mod main_mobile_commands;
use main_mobile_commands::run_mobile_command;

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

pub(crate) async fn runtime_host_required(
    args: &RuntimeDirArgs,
) -> anyhow::Result<RuntimeHostRpcClient> {
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

pub(crate) fn runtime_dir(args: &RuntimeDirArgs) -> PathBuf {
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
        projects_dir: args
            .projects_dir
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
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

pub(crate) fn host_accessible_optional_string_path(
    value: Option<String>,
) -> anyhow::Result<Option<String>> {
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

pub(crate) fn normalized_workspace_path_value(value: &str) -> Option<String> {
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
