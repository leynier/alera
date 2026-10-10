//! Workspaces: listing, creating, starting agents in new ones, and sleeping.

use super::{execute, profile_schema, read, with_profile, LAUNCH_TIMEOUT, PROMPT_LIMIT};
use crate::mcp_tools::schema::{boolean, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

/// The creation flags shared by `workspace add` and `workspace start`. A
/// branch only exists on a worktree, so naming one without it is refused here
/// rather than by the CLI.
fn workspace_creation(
    invocation: Invocation,
    arguments: &ToolArguments,
) -> Result<Invocation, ToolInputError> {
    let names_branch =
        arguments.string("branch").is_some() || arguments.string("sourceBranch").is_some();
    if names_branch && !arguments.flag("worktree") {
        return Err(ToolInputError(
            "branch and sourceBranch need worktree: true.".into(),
        ));
    }
    Ok(invocation
        .flag_if("--worktree", arguments.flag("worktree"))
        .option_if("--name", arguments.string("name"))
        .option_if("--branch", arguments.string("branch"))
        .option_if("--source-branch", arguments.string("sourceBranch"))
        .option_if("--host-id", arguments.string("hostId"))
        .option_if("--issue", arguments.string("issueUrl"))
        .option_if("--section", arguments.string("section")))
}

fn workspace_creation_properties() -> Vec<(&'static str, serde_json::Value)> {
    vec![
        (
            "worktree",
            boolean("Create an exclusive Git worktree instead of sharing the project folder."),
        ),
        ("name", string("Workspace display name.")),
        ("branch", string("Branch to create or use.")),
        ("sourceBranch", string("Branch the new branch starts from.")),
        (
            "hostId",
            string("SSH target that owns the worktree. Omit for this machine."),
        ),
        ("issueUrl", string("Issue URL to link to the workspace.")),
        ("section", string("Sidebar section name.")),
    ]
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_workspaces",
            "List Workspaces",
            "List workspaces (tasks with their branch and worktree) of one project, or of every project when projectId is omitted. Filter by host, section, tag, archive state, or parent.",
            || {
                object(
                    &[
                        ("projectId", string("Project id from list_projects.")),
                        ("hostId", string("SSH target id, or `local`.")),
                        (
                            "sectionId",
                            string("Section id from list_sections, or `none` for workspaces in Others."),
                        ),
                        ("tagId", string("Tag id from list_tags.")),
                        (
                            "archived",
                            one_of(
                                "all (default), only archived, or only visible workspaces.",
                                &["all", "archived", "visible"],
                            ),
                        ),
                        ("parentWorkspaceId", string("Only the children of this workspace.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                let project = arguments.string("projectId");
                let all = project.is_none();
                let archived = match arguments.string("archived").as_deref() {
                    Some("archived") => Some("true"),
                    Some("visible") => Some("false"),
                    _ => None,
                };
                Ok(Invocation::new("workspace", &["list"])
                    .option_if("--project-id", project)
                    .option_if("--host-id", arguments.string("hostId"))
                    .option_if("--section-id", arguments.string("sectionId"))
                    .option_if("--tag-id", arguments.string("tagId"))
                    .option_if("--archived", archived)
                    .option_if(
                        "--parent-workspace-id",
                        arguments.string("parentWorkspaceId"),
                    )
                    .flag_if("--all", all))
            },
        ),
        execute(
            "create_workspace",
            "Create Workspace",
            "Create a workspace (task) in a project, on the project folder or on its own Git worktree and branch, as the app's manual New Workspace form does. A worktree on a new branch also needs sourceBranch, such as main. No agent is started.",
            || {
                let mut properties = vec![("projectId", string("Project id from list_projects."))];
                properties.extend(workspace_creation_properties());
                properties.extend([
                    ("sectionId", string("Section id from list_sections. Use instead of section.")),
                    ("parentWorkspaceId", string("Workspace to nest the new one under.")),
                    (
                        "reuseExistingBranch",
                        boolean("Check out an existing branch in the worktree instead of creating it."),
                    ),
                    ("path", string("Exact folder for the worktree.")),
                    (
                        "workspaceRoot",
                        string("Folder under which Alera names the worktree. Defaults to the runtime's workspace folder."),
                    ),
                ]);
                object(&properties, &["projectId"])
            },
            create_workspace,
        ),
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "start_agent_workspace",
                "Start Agent In New Workspace",
                "Create a workspace and launch an agent profile in it with a prompt. Pass projectId, or workspaceId to infer the project and source branch from an existing workspace. A worktree created from projectId also needs sourceBranch.",
                || {
                    let mut properties = vec![
                        ("profile", profile_schema()),
                        ("prompt", text("Prompt delivered to the agent.", PROMPT_LIMIT)),
                        ("projectId", string("Project id from list_projects.")),
                        ("workspaceId", string("Existing workspace used to infer the project.")),
                    ];
                    properties.extend(workspace_creation_properties());
                    object(&properties, &["profile", "prompt"])
                },
                start_agent_workspace,
            )
        },
        ToolSpec {
            destructive: true,
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "sleep_workspace",
                "Sleep Workspace",
                "Stop a workspace's terminal sessions while keeping its tabs, branch, and files. Opening it again wakes it.",
                || object(&[("workspaceId", string("Workspace id."))], &["workspaceId"]),
                |arguments| {
                    Ok(Invocation::new("workspace", &["sleep"])
                        .option("--id", arguments.required("workspaceId")?))
                },
            )
        },
    ]
}

fn create_workspace(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let worktree = arguments.flag("worktree");
    let (path, root) = (arguments.string("path"), arguments.string("workspaceRoot"));
    if path.is_some() && root.is_some() {
        return Err(ToolInputError(
            "Pass path or workspaceRoot, not both.".into(),
        ));
    }
    if arguments.string("section").is_some() && arguments.string("sectionId").is_some() {
        return Err(ToolInputError(
            "Pass section or sectionId, not both.".into(),
        ));
    }
    let worktree_only = arguments.flag("reuseExistingBranch") || path.is_some() || root.is_some();
    if worktree_only && !worktree {
        return Err(ToolInputError(
            "reuseExistingBranch, path, and workspaceRoot need worktree.".into(),
        ));
    }
    let invocation = Invocation::new("workspace", &["add"])
        .option("--project-id", arguments.required("projectId")?)
        .option_if("--section-id", arguments.string("sectionId"))
        .option_if(
            "--parent-workspace-id",
            arguments.string("parentWorkspaceId"),
        )
        .flag_if(
            "--reuse-existing-branch",
            arguments.flag("reuseExistingBranch"),
        )
        .option_if("--path", path)
        .option_if("--workspace-root", root);
    workspace_creation(invocation, arguments)
}

fn start_agent_workspace(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let project = arguments.string("projectId");
    let workspace = arguments.string("workspaceId");
    if project.is_none() && workspace.is_none() {
        return Err(ToolInputError("Pass projectId or workspaceId.".into()));
    }
    let invocation = with_profile(
        Invocation::new("workspace", &["start"]),
        arguments.required("profile")?,
    )
    .flag("--prompt-stdin")
    .flag("--no-parent")
    .option_if("--project-id", project)
    .option_if("--workspace", workspace)
    .stdin(arguments.required("prompt")?);
    workspace_creation(invocation, arguments)
}
