//! Project registration, cloning, hosts, branches, and configuration, and the
//! SSH targets projects can live on.

use serde_json::Value;

use super::{execute, no_arguments, read, LAUNCH_TIMEOUT};
use crate::mcp_tools::schema::{object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

const CONFIG_LIMIT: u64 = 65_536;

fn project_id() -> Value {
    string("Project id from list_projects.")
}

fn project_schema() -> Value {
    object(&[("projectId", project_id())], &["projectId"])
}

fn kind() -> Value {
    one_of(
        "gitRepository (default) or folder for a plain folder without Git.",
        &["gitRepository", "folder"],
    )
}

fn kind_flag(arguments: &ToolArguments) -> Option<&'static str> {
    arguments.string("kind").map(|kind| match kind.as_str() {
        "folder" => "folder",
        _ => "git-repository",
    })
}

fn host_schema() -> Value {
    object(
        &[
            ("projectId", project_id()),
            ("hostId", string("SSH target id from list_ssh_targets.")),
        ],
        &["projectId", "hostId"],
    )
}

fn clone_job_schema() -> Value {
    object(
        &[("cloneId", string("Clone job id from clone_project."))],
        &["cloneId"],
    )
}

fn project(
    action: &[&str],
    flag: &str,
    arguments: &ToolArguments,
) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("project", action).option(flag, arguments.required("projectId")?))
}

fn long(tool: ToolSpec) -> ToolSpec {
    ToolSpec {
        timeout_seconds: LAUNCH_TIMEOUT,
        ..tool
    }
}

fn idempotent(tool: ToolSpec) -> ToolSpec {
    ToolSpec {
        idempotent: true,
        ..tool
    }
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        execute(
            "register_project",
            "Register Project",
            "Add an existing folder on this machine as an Alera project. The folder is not changed.",
            || {
                object(
                    &[
                        ("path", string("Absolute path of the project folder.")),
                        ("name", string("Display name. Defaults to the folder name.")),
                        ("kind", kind()),
                    ],
                    &["path"],
                )
            },
            |arguments| {
                Ok(Invocation::new("project", &["add"])
                    .option("--repo-path", arguments.required("path")?)
                    .option_if("--name", arguments.string("name"))
                    .option_if("--kind", kind_flag(arguments)))
            },
        ),
        execute(
            "clone_project",
            "Clone Project",
            "Clone a Git repository into a new folder on this machine and register it as a project. Returns a clone job at once; follow it with get_project_clone.",
            || {
                object(
                    &[
                        ("url", text("Repository URL.", 2_048)),
                        ("parentPath", string("Existing folder the clone goes into.")),
                        ("directoryName", string("New folder name. Defaults to the repository name.")),
                        ("name", string("Project display name.")),
                    ],
                    &["url", "parentPath"],
                )
            },
            |arguments| {
                Ok(Invocation::new("project", &["clone", "start"])
                    .option("--url", arguments.required("url")?)
                    .option("--parent-path", arguments.required("parentPath")?)
                    .option_if("--directory-name", arguments.string("directoryName"))
                    .option_if("--name", arguments.string("name")))
            },
        ),
        read(
            "get_project_clone",
            "Get Project Clone",
            "Show a clone job: its status, progress, message, and the project it registered when done.",
            clone_job_schema,
            |arguments| {
                Ok(Invocation::new("project", &["clone", "show"])
                    .option("--id", arguments.required("cloneId")?))
            },
        ),
        read(
            "list_project_clones",
            "List Project Clones",
            "List the clone jobs of this runtime, running and finished.",
            no_arguments,
            |_| Ok(Invocation::new("project", &["clone", "list"])),
        ),
        ToolSpec {
            destructive: true,
            ..idempotent(execute(
                "cancel_project_clone",
                "Cancel Project Clone",
                "Stop a running clone and delete its partial folder.",
                clone_job_schema,
                |arguments| {
                    Ok(Invocation::new("project", &["clone", "cancel"])
                        .option("--id", arguments.required("cloneId")?))
                },
            ))
        },
        long(execute(
            "register_remote_project",
            "Register Remote Project",
            "Add a project that lives only on an SSH host, from an existing folder there (path) or by cloning a repository into the host's projects folder (cloneUrl).",
            || {
                object(
                    &[
                        ("hostId", string("SSH target id from list_ssh_targets.")),
                        ("path", string("Existing folder on the host.")),
                        ("cloneUrl", text("Repository URL to clone on the host.", 2_048)),
                        ("name", string("Display name.")),
                        ("kind", kind()),
                    ],
                    &["hostId"],
                )
            },
            |arguments| {
                let (path, clone_url) = (arguments.string("path"), arguments.string("cloneUrl"));
                if path.is_some() && clone_url.is_some() {
                    return Err(ToolInputError("Pass path or cloneUrl, not both.".into()));
                }
                Ok(Invocation::new("project", &["add-remote"])
                    .option("--host-id", arguments.required("hostId")?)
                    .option_if("--path", path)
                    .option_if("--clone-url", clone_url)
                    .option_if("--name", arguments.string("name"))
                    .option_if("--kind", kind_flag(arguments)))
            },
        )),
        long(execute(
            "register_project_checkout",
            "Register Project Checkout",
            "Register an existing folder on an SSH host as a project's checkout there, or clone into that new folder first with cloneUrl.",
            || {
                object(
                    &[
                        ("projectId", project_id()),
                        ("hostId", string("SSH target id from list_ssh_targets.")),
                        ("path", string("Folder on the host.")),
                        ("cloneUrl", text("Repository URL to clone into path first.", 2_048)),
                    ],
                    &["projectId", "hostId", "path"],
                )
            },
            |arguments| {
                Ok(project(&["register-checkout"], "--project-id", arguments)?
                    .option("--host-id", arguments.required("hostId")?)
                    .option("--path", arguments.required("path")?)
                    .option_if("--clone-url", arguments.string("cloneUrl")))
            },
        )),
        idempotent(execute(
            "rename_project",
            "Rename Project",
            "Change a project's display name. Its folder is not touched.",
            || object(&[("projectId", project_id()), ("name", text("New name.", 200))], &["projectId", "name"]),
            |arguments| Ok(project(&["rename"], "--id", arguments)?.option("--name", arguments.required("name")?)),
        )),
        read(
            "preview_project_removal",
            "Preview Project Removal",
            "Show what remove_project would affect: workspaces, tabs, live sessions, the automations it would pause, and whether settings override the repository's. Changes nothing.",
            project_schema,
            |arguments| project(&["remove-preview"], "--id", arguments),
        ),
        ToolSpec {
            destructive: true,
            ..long(execute(
                "remove_project",
                "Remove Project",
                "Remove a project from Alera as the app does: dependent automations are paused and their runs cancelled, then the project and its workspace records go. No file is deleted: the project folder and its worktrees stay on disk.",
                project_schema,
                |arguments| {
                    Ok(project(&["remove"], "--id", arguments)?
                        .flag("--pause-automations-and-cancel-runs"))
                },
            ))
        },
        read(
            "list_project_hosts",
            "List Project Hosts",
            "List the hosts a project is on, with its folder on each.",
            project_schema,
            |arguments| project(&["hosts", "list"], "--project-id", arguments),
        ),
        long(execute(
            "add_project_host",
            "Add Project Host",
            "Add a project to an SSH host: register an existing folder there (path), or clone the project's Git remote (or cloneUrl) into the host's projects folder.",
            || {
                object(
                    &[
                        ("projectId", project_id()),
                        ("hostId", string("SSH target id from list_ssh_targets.")),
                        ("path", string("Existing folder on the host.")),
                        ("cloneUrl", text("Repository URL to clone instead of the project's remote.", 2_048)),
                    ],
                    &["projectId", "hostId"],
                )
            },
            |arguments| {
                Ok(project(&["hosts", "add"], "--project-id", arguments)?
                    .option("--host-id", arguments.required("hostId")?)
                    .option_if("--path", arguments.string("path"))
                    .option_if("--clone-url", arguments.string("cloneUrl")))
            },
        )),
        ToolSpec {
            destructive: true,
            ..idempotent(execute(
                "remove_project_host",
                "Remove Project Host",
                "Forget a project's folder on a host. No file is deleted.",
                host_schema,
                |arguments| {
                    Ok(project(&["hosts", "remove"], "--project-id", arguments)?
                        .option("--host-id", arguments.required("hostId")?))
                },
            ))
        },
        long(read(
            "list_project_branches",
            "List Project Branches",
            "List the branches of a project's folder on a host, which are the choices for a new worktree's sourceBranch, and the project's preferred source branch when one is set.",
            || {
                object(
                    &[
                        ("projectId", project_id()),
                        ("hostId", string("SSH target id, or `local` (default).")),
                    ],
                    &["projectId"],
                )
            },
            |arguments| {
                Ok(project(&["branches"], "--project-id", arguments)?
                    .option_if("--host-id", arguments.string("hostId")))
            },
        )),
        read(
            "get_project_config",
            "Get Project Settings",
            "Show a project's effective settings (New Workspace prompt and source branch, worktree copy rules and setup commands, pull request provider) and whether they come from the app or from the repository's alera.toml.",
            project_schema,
            |arguments| project(&["config", "show"], "--project-id", arguments),
        ),
        idempotent(execute(
            "update_project_config",
            "Update Project Settings",
            "Save project settings as the app's settings dialog does, overriding the repository's alera.toml. config is a JSON object with any of worktree {copy: [{from, to, overwrite}], setup: [commands]}, newWorkspace {promptAppend, sourceBranch}, and gitHostingProvider (auto to detect it). Each part given replaces that part; the others stay.",
            || {
                object(
                    &[
                        ("projectId", project_id()),
                        ("config", text("Settings as a JSON object.", CONFIG_LIMIT)),
                    ],
                    &["projectId", "config"],
                )
            },
            |arguments| {
                Ok(project(&["config", "set"], "--project-id", arguments)?
                    .flag("--config-stdin")
                    .stdin(arguments.required("config")?))
            },
        )),
        ToolSpec {
            destructive: true,
            ..idempotent(execute(
                "reset_project_config",
                "Reset Project Settings",
                "Remove the settings saved in the app so the repository's alera.toml, or the defaults, apply again.",
                project_schema,
                |arguments| project(&["config", "remove"], "--project-id", arguments),
            ))
        },
        read(
            "list_ssh_targets",
            "List SSH Targets",
            "List the SSH hosts this runtime knows, with their platform, installed runtime, and bootstrap state. Credentials are never included.",
            no_arguments,
            |_| Ok(Invocation::new("ssh-target", &["list"])),
        ),
        long(read(
            "ssh_target_status",
            "SSH Target Status",
            "Check whether SSH hosts are reachable and which runtime they have installed: one host by targetId, or all of them.",
            || object(&[("targetId", string("SSH target id from list_ssh_targets."))], &[]),
            |arguments| {
                Ok(Invocation::new("ssh-target", &["status"])
                    .option_if("--id", arguments.string("targetId")))
            },
        )),
    ]
}
