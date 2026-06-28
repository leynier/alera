mod cli;
mod runtime_host_client;
mod terminal_host;

use std::future::Future;
use std::path::{Path, PathBuf};

use alera_core::runtime::{
    CascadePreview, Project, ProjectKind, RuntimeStore, SshAuthKind, SshTarget, Workspace,
    WorkspaceKind, WorkspaceStatus, WorkspaceTabRecord, WorkspaceTag, LOCAL_HOST_ID,
    RUNTIME_DATABASE_FILE_NAME,
};
use chrono::Utc;
use clap::Parser;
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::json;
use uuid::Uuid;

use crate::cli::TerminalHostArgs;
use crate::cli::{
    CascadePreviewArgs, Cli, Command, IdArgs, ProjectAction, ProjectAddArgs, ProjectCommand,
    ProjectKindArg, RuntimeAction, RuntimeCommand, RuntimeDirArgs, SshAuthKindArg, SshTargetAction,
    SshTargetAddArgs, SshTargetCommand, TabAction, TabCommand, TabCreateArgs, WorkspaceAction,
    WorkspaceAddArgs, WorkspaceCommand, WorkspaceKindArg,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
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
        Command::TerminalHost(args) => run_terminal_host(args).await,
        Command::Runtime(command) => run_runtime_command(command).await,
        Command::Project(command) => run_project_command(command).await,
        Command::Workspace(command) => run_workspace_command(command).await,
        Command::Tag(command) => run_tag_command(command).await,
        Command::Tab(command) => run_tab_command(command).await,
        Command::SshTarget(command) => run_ssh_target_command(command).await,
    }
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

async fn run_runtime_command(command: RuntimeCommand) -> i32 {
    let store = match open_store(&command.runtime).await {
        Ok(store) => store,
        Err(error) => return print_error(error),
    };
    match command.action {
        RuntimeAction::Status => {
            let runtime_dir = runtime_dir(&command.runtime);
            let payload = json!({
                "runtimeDir": runtime_dir.display().to_string(),
                "database": runtime_dir.join(RUNTIME_DATABASE_FILE_NAME).display().to_string(),
                "status": "ok",
            });
            print_value(&payload, command.output.json, "runtime ok");
            drop(store);
            0
        }
    }
}

async fn run_project_command(command: ProjectCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        ProjectAction::List => match open_store(&runtime).await {
            Ok(store) => match store.list_projects().await {
                Ok(projects) => print_value(&projects, json_output, "projects listed"),
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
                Ok(workspaces) => print_value(&workspaces, json_output, "workspaces listed"),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Add(args) => {
            let workspace = workspace_from_args(args);
            let fallback_workspace = workspace.clone();
            match runtime_host_or_store(
                &runtime,
                "workspace.upsert",
                &workspace,
                |store| async move { store.upsert_workspace(fallback_workspace).await },
            )
            .await
            {
                Ok(workspace) => print_value(&workspace, json_output, "workspace saved"),
                Err(error) => return print_error(error),
            }
        }
        WorkspaceAction::Remove(IdArgs { id }) => {
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
                    "workspace removed",
                ),
                Err(error) => return print_error(error),
            }
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
                Ok(tags) => print_value(&tags, json_output, "tags listed"),
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
                Ok(tabs) => print_value(&tabs, json_output, "tabs listed"),
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
                Ok(targets) => print_value(&targets, json_output, "ssh targets listed"),
                Err(error) => return print_error(error),
            },
            Err(error) => return print_error(error),
        },
        SshTargetAction::Add(args) => {
            let target = ssh_target_from_args(args);
            let fallback_target = target.clone();
            match runtime_host_or_store(&runtime, "sshTarget.upsert", &target, |store| async move {
                store.upsert_ssh_target(fallback_target).await
            })
            .await
            {
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
        SshTargetAction::BootstrapPlan(IdArgs { id }) => {
            let store = match open_store(&runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            let targets = match store.list_ssh_targets().await {
                Ok(targets) => targets,
                Err(error) => return print_error(error),
            };
            let Some(target) = targets.into_iter().find(|target| target.id == id) else {
                eprintln!("ssh target not found: {id}");
                return 1;
            };
            let remote_dir = if target.platform.as_deref() == Some("windows") {
                "%LOCALAPPDATA%\\Alera\\runtime".to_string()
            } else {
                "~/.alera/runtime".to_string()
            };
            print_value(
                &json!({
                    "targetId": target.id,
                    "alias": target.alias,
                    "host": target.host,
                    "port": target.port,
                    "username": target.username,
                    "remoteInstallDir": remote_dir,
                    "artifactPattern": "alera-runtime-<version>-<os>-<arch>",
                    "status": "planned",
                }),
                json_output,
                "ssh bootstrap plan ready",
            );
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

fn workspace_from_args(args: WorkspaceAddArgs) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: args.id.unwrap_or_else(|| Uuid::new_v4().to_string()),
        instance_id: args
            .instance_id
            .unwrap_or_else(|| Uuid::new_v4().to_string()),
        host_id: args.host_id.unwrap_or_else(|| LOCAL_HOST_ID.to_string()),
        project_id: args.project_id,
        name: args.name,
        branch: args.branch,
        path: args.path,
        created_at: now,
        updated_at: now,
        kind: match args.kind {
            WorkspaceKindArg::Main => WorkspaceKind::Main,
            WorkspaceKindArg::Linked => WorkspaceKind::Linked,
        },
        status: WorkspaceStatus::Active,
        source_branch: args.source_branch,
        reuses_existing_branch: args.reuses_existing_branch,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        child_count: 0,
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
    Ok(WorkspaceTabRecord {
        id: id.clone(),
        workspace_id: args.workspace_id,
        kind: kind.to_string(),
        title: args.title,
        created_at: now,
        updated_at: now,
        payload: json!({ "terminalSessionId": id }),
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

fn print_value<T: Serialize>(value: &T, json_output: bool, message: &str) {
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".to_string())
        );
    } else {
        println!("{message}");
    }
}

fn print_error(error: impl std::fmt::Display) -> i32 {
    eprintln!("{error}");
    1
}
