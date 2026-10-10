//! Pull requests on GitHub, GitLab, and Azure DevOps, over `alera pr` and
//! `alera workspace pr-watch`. The runtime runs `gh`, `glab`, or `az` on the
//! host that owns the checkout; a missing or signed-out CLI answers
//! `provider_unavailable`, and stacks outside GitHub `provider_unsupported`.

use serde_json::Value;

use super::{execute, read, LAUNCH_TIMEOUT, PROMPT_LIMIT};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

#[path = "pull_requests_flow.rs"]
mod flow;

/// Forge CLIs answer in seconds, but a write also reads the pull request back.
const FORGE_TIMEOUT: u64 = LAUNCH_TIMEOUT;
pub(super) const NUMBER_MAX: u64 = 1 << 31;
pub(super) const MERGE_METHODS: &[&str] = &["mergeCommit", "squash", "rebase", "providerDefault"];

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = vec![
        slow(read(
            "get_pull_request",
            "Get Pull Request",
            "Show the pull request of a workspace on GitHub, GitLab, or Azure DevOps: state, draft, mergeability, head SHA, checks (pipelines or policies on GitLab and Azure DevOps), the conversation and review threads with their ids, the merge methods the forge allows, and the base branches. It is the linked pull request, or the open one for the current branch.",
            workspace_only,
            |arguments| pr(arguments, &["show"]),
        )),
        slow(read(
            "list_pull_request_summaries",
            "List Pull Request Summaries",
            "List one compact row per active workspace that has a pull request: number, title, state, and the rolled-up check status with failing check names.",
            || object(&[("workspaceId", string("Only this workspace."))], &[]),
            |arguments| {
                Ok(Invocation::new("pr", &["summaries"])
                    .option_if("--workspace-id", arguments.string("workspaceId")))
            },
        )),
        slow(execute(
            "generate_pull_request_details",
            "Generate Pull Request Details",
            "Write a pull request title and description for the workspace branch against a base branch with AI Assist, the same generator the apps use. It changes nothing on the forge; AI Assist must be enabled.",
            || object(&[workspace(), base_branch()], &["workspaceId", "baseBranch"]),
            |arguments| {
                Ok(pr(arguments, &["generate-details"])?
                    .option("--base", arguments.required("baseBranch")?))
            },
        )),
        slow(execute(
            "create_pull_request",
            "Create Pull Request",
            "Open a pull request (a merge request on GitLab) from the workspace's current branch into a base branch, optionally as a draft, and link it to the workspace. Push the branch first. Returns the refreshed pull request.",
            || {
                object(
                    &[
                        workspace(),
                        base_branch(),
                        ("title", text("Pull request title.", 512)),
                        ("body", text("Pull request description in Markdown.", PROMPT_LIMIT)),
                        ("draft", boolean("Open it as a draft.")),
                    ],
                    &["workspaceId", "baseBranch", "title"],
                )
            },
            |arguments| {
                let invocation = pr(arguments, &["create"])?
                    .option("--base", arguments.required("baseBranch")?)
                    .option("--title", arguments.required("title")?)
                    .flag_if("--draft", arguments.flag("draft"));
                Ok(with_body(invocation, arguments.string("body")))
            },
        )),
        slow(execute(
            "link_pull_request",
            "Link Pull Request",
            "Link an existing pull request of the workspace repository by number or URL, so the workspace shows it instead of branch detection.",
            || {
                object(
                    &[workspace(), ("reference", string("Pull request number, #number, or URL of this repository."))],
                    &["workspaceId", "reference"],
                )
            },
            |arguments| {
                // After `--` a reference is never read as a flag.
                Ok(pr(arguments, &["link"])?
                    .flag("--")
                    .flag(&arguments.required("reference")?))
            },
        )),
        idempotent(slow(execute(
            "unlink_pull_request",
            "Unlink Pull Request",
            "Unlink the workspace's pull request, so branch detection stops showing that one until it is linked again. The pull request itself is not changed.",
            || object(&[workspace(), number()], &["workspaceId"]),
            |arguments| numbered(arguments, &["unlink"]),
        ))),
        slow(execute(
            "comment_pull_request",
            "Comment On Pull Request",
            "Post a comment on the pull request, or reply to a comment with replyToCommentId. On GitLab and Azure DevOps a reply joins that comment's discussion or thread; pass its threadId from get_pull_request when known.",
            || {
                object(
                    &[
                        workspace(),
                        number(),
                        ("body", text("Comment in Markdown.", PROMPT_LIMIT)),
                        ("replyToCommentId", integer("Comment id to reply to.", 1, u64::MAX >> 11)),
                        ("threadId", string("Thread or discussion id of that comment.")),
                    ],
                    &["workspaceId", "body"],
                )
            },
            |arguments| {
                let invocation = numbered(arguments, &["comment"])?
                    .option_if("--reply-to", arguments.integer("replyToCommentId").map(|id| id.to_string()))
                    .option_if("--thread-id", arguments.string("threadId"));
                Ok(with_body(invocation, arguments.string("body")))
            },
        )),
        slow(execute(
            "edit_pull_request_comment",
            "Edit Pull Request Comment",
            "Replace the text of one of your comments. Use the id, source, and threadId the comment has in get_pull_request.",
            || {
                object(
                    &[
                        workspace(),
                        number(),
                        ("commentId", integer("Comment id.", 1, u64::MAX >> 11)),
                        ("source", one_of("Where the comment lives.", &["conversation", "reviewSummary", "reviewThread"])),
                        ("threadId", string("Thread or discussion id (GitLab and Azure DevOps).")),
                        ("body", text("New comment text in Markdown.", PROMPT_LIMIT)),
                    ],
                    &["workspaceId", "commentId", "source", "body"],
                )
            },
            |arguments| {
                let invocation = numbered(arguments, &["comment-edit"])?
                    .option("--comment-id", arguments.integer("commentId").unwrap_or(0).to_string())
                    .option("--source", arguments.required("source")?)
                    .option_if("--thread-id", arguments.string("threadId"));
                Ok(with_body(invocation, arguments.string("body")))
            },
        )),
        idempotent(slow(execute(
            "set_pull_request_draft",
            "Set Pull Request Draft",
            "Mark the pull request as a draft (draft true) or ready for review (draft false).",
            || {
                object(
                    &[workspace(), number(), ("draft", boolean("true for draft, false for ready for review."))],
                    &["workspaceId", "draft"],
                )
            },
            |arguments| {
                Ok(numbered(arguments, &["draft"])?.flag_if("--ready", !arguments.flag("draft")))
            },
        ))),
        destructive(slow(execute(
            "close_pull_request",
            "Close Pull Request",
            "Close the pull request without merging it (abandon on Azure DevOps).",
            || object(&[workspace(), number()], &["workspaceId"]),
            |arguments| numbered(arguments, &["close"]),
        ))),
        destructive(slow(execute(
            "merge_pull_request",
            "Merge Pull Request",
            "Merge the pull request. Methods per forge: GitHub mergeCommit, squash, or rebase as the repository allows; GitLab providerDefault (the project's merge setting) or squash; Azure DevOps mergeCommit (no fast-forward) or squash. Without method the forge's preferred allowed method is used. Pass expectedHeadSha to merge only if nobody pushed since you checked.",
            || {
                object(
                    &[
                        workspace(),
                        number(),
                        ("method", one_of("Merge method from mergeMethods in get_pull_request.", MERGE_METHODS)),
                        ("expectedHeadSha", string("Merge only while the head commit is this SHA.")),
                    ],
                    &["workspaceId"],
                )
            },
            |arguments| {
                Ok(numbered(arguments, &["merge"])?
                    .option_if("--method", arguments.string("method"))
                    .option_if("--expected-head", arguments.string("expectedHeadSha")))
            },
        ))),
    ];
    tools.extend(flow::tools());
    tools
}

fn slow(tool: ToolSpec) -> ToolSpec {
    ToolSpec {
        timeout_seconds: FORGE_TIMEOUT,
        ..tool
    }
}

fn idempotent(tool: ToolSpec) -> ToolSpec {
    ToolSpec {
        idempotent: true,
        ..tool
    }
}

fn destructive(tool: ToolSpec) -> ToolSpec {
    ToolSpec {
        destructive: true,
        ..tool
    }
}

pub(super) fn workspace() -> (&'static str, Value) {
    ("workspaceId", string("Workspace id."))
}

pub(super) fn number() -> (&'static str, Value) {
    (
        "number",
        integer(
            "Pull request number. Defaults to the workspace's linked or detected pull request.",
            1,
            NUMBER_MAX,
        ),
    )
}

fn base_branch() -> (&'static str, Value) {
    (
        "baseBranch",
        string("Base branch the pull request targets, such as main."),
    )
}

fn workspace_only() -> Value {
    object(&[workspace()], &["workspaceId"])
}

/// `alera pr <action...> --workspace-id=<id>`.
pub(super) fn pr(arguments: &ToolArguments, action: &[&str]) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("pr", action).option("--workspace-id", arguments.required("workspaceId")?))
}

/// [pr] plus the optional `--number`.
pub(super) fn numbered(
    arguments: &ToolArguments,
    action: &[&str],
) -> Result<Invocation, ToolInputError> {
    Ok(pr(arguments, action)?.option_if(
        "--number",
        arguments.integer("number").map(|number| number.to_string()),
    ))
}

/// Long text travels on stdin.
fn with_body(invocation: Invocation, body: Option<String>) -> Invocation {
    match body {
        Some(body) => invocation.flag("--body-stdin").stdin(body),
        None => invocation,
    }
}
