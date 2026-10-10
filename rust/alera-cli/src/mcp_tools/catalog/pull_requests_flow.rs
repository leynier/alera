//! Ship Changes, agent dispatch (Restack, Fix Failed Checks), Watch and Fix,
//! and GitHub stacks.

use serde_json::{json, Value};

use super::super::{execute, read, LAUNCH_TIMEOUT};
use super::{numbered, pr, workspace, MERGE_METHODS, NUMBER_MAX};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        slow(execute(
            "ship_changes",
            "Ship Changes",
            "Ship the workspace like the Ship Changes button: stage (all changes or only staged ones), commit with an AI Assist message, move work off a shared base branch to a ship/ branch, push, and open a pull request with AI Assist details on GitHub, GitLab, or Azure DevOps. With followUpWatch it then starts Watch and Fix (mode fix) or Watch, Fix and Merge (mode fixAndMerge) on the new pull request with the given agent. Needs AI Assist. If the call times out the ship keeps running; read get_pull_request for the result.",
            || {
                object(
                    &[
                        workspace(),
                        ("baseBranch", string("Base branch for the pull request, such as main.")),
                        ("scope", one_of("all (default) stages every change; staged ships only staged changes.", &["all", "staged"])),
                        ("draft", boolean("Open the pull request as a draft.")),
                        ("followUpWatch", json!({
                            "type": "object",
                            "additionalProperties": false,
                            "description": "Watch the new pull request afterwards.",
                            "properties": {
                                "mode": { "type": "string", "enum": ["fix", "fixAndMerge"], "description": "fix sends problems to the agent; fixAndMerge also merges once clear." },
                                "handle": { "type": "string", "minLength": 1, "description": "Running agent terminal handle to send fixes to." },
                                "profile": { "type": "string", "minLength": 1, "description": "Agent profile id or name for a new tab when no terminal is running." },
                                "checks": { "type": "boolean", "description": "Watch failing checks (default true)." },
                                "comments": { "type": "boolean", "description": "Watch unresolved review threads (default true)." },
                                "conflicts": { "type": "boolean", "description": "Watch merge conflicts (default true)." }
                            }
                        })),
                    ],
                    &["workspaceId", "baseBranch"],
                )
            },
            ship,
        )),
        slow(execute(
            "restack_pull_request",
            "Restack Pull Request",
            "Ask an agent to rewrite the workspace's committed and uncommitted changes into logical, easy-to-review commits without pushing, like the Restack button. Send it to a running agent (handle) or open a tab from a profile; with preview true only the prompt is returned.",
            || dispatch_schema(false),
            |arguments| dispatch(arguments, "restack"),
        )),
        slow(execute(
            "fix_pull_request_checks",
            "Fix Pull Request Checks",
            "Ask an agent to fix the failed checks of the workspace's pull request, like the Fix Failed Checks button. Send it to a running agent (handle) or open a tab from a profile; with preview true only the prompt is returned.",
            || dispatch_schema(true),
            |arguments| dispatch(arguments, "fix-checks"),
        )),
        read(
            "show_pull_request_watch",
            "Show Pull Request Watch",
            "Show the active Watch and Fix session of a workspace: the pull request, mode, watched problems, and agent. Returns watch null when nothing is watched.",
            || object(&[workspace()], &["workspaceId"]),
            |arguments| watch(arguments, "show"),
        ),
        execute(
            "start_pull_request_watch",
            "Start Pull Request Watch",
            "Start Watch and Fix on the workspace's pull request (GitHub, GitLab, or Azure DevOps). The runtime sends failing checks, merge conflicts, and unresolved review threads to the agent; mode fixAndMerge also merges once checks pass and nothing is open. Replaces the workspace's current watch.",
            || {
                object(
                    &[
                        workspace(),
                        ("mode", one_of("fix (default) or fixAndMerge.", &["fix", "fixAndMerge"])),
                        ("reviewNumber", integer("Pull request number. Defaults to the linked pull request.", 1, NUMBER_MAX)),
                        ("handle", string("Running agent terminal handle.")),
                        ("profile", string("Agent profile id or name used when the terminal is gone.")),
                        ("checks", boolean("Watch failing checks (default true).")),
                        ("comments", boolean("Watch unresolved review threads (default true).")),
                        ("conflicts", boolean("Watch merge conflicts (default true).")),
                    ],
                    &["workspaceId"],
                )
            },
            |arguments| {
                let invocation = watch(arguments, "start")?
                    .flag_if("--merge", arguments.string("mode").as_deref() == Some("fixAndMerge"))
                    .option_if("--review-number", arguments.integer("reviewNumber").map(|n| n.to_string()))
                    .option_if("--handle", arguments.string("handle"))
                    .flag_if("--no-checks", arguments.optional_flag("checks") == Some(false))
                    .flag_if("--no-comments", arguments.optional_flag("comments") == Some(false))
                    .flag_if("--no-conflicts", arguments.optional_flag("conflicts") == Some(false));
                Ok(with_profile(invocation, arguments.string("profile")))
            },
        ),
        ToolSpec {
            idempotent: true,
            ..execute(
                "stop_pull_request_watch",
                "Stop Pull Request Watch",
                "Stop Watch and Fix for a workspace. A merge the forge already accepted is not undone.",
                || object(&[workspace()], &["workspaceId"]),
                |arguments| watch(arguments, "stop"),
            )
        },
        slow(read(
            "get_pull_request_stack",
            "Get Pull Request Stack",
            "Show the GitHub stack that holds the workspace's pull request, bottom layer first, and whether the gh-stack extension is installed. Stacks exist only on GitHub.",
            || object(&[workspace(), super::number()], &["workspaceId"]),
            |arguments| numbered(arguments, &["stack", "show"]),
        )),
        slow(execute(
            "create_pull_request_stack",
            "Create Pull Request Stack",
            "Build a GitHub stack from local workspaces, bottom to top: push each branch, open the pull requests they lack (each targeting the layer below), link them to their workspaces, and stack them with gh stack. The current workspace must be one of the layers of a new stack; with an existing stack the layers are appended. Needs the gh-stack extension.",
            || {
                object(
                    &[
                        workspace(),
                        ("baseBranch", string("Base branch of a new stack, such as main.")),
                        ("workspaceIds", strings("Workspace of each layer, bottom to top.")),
                        ("titles", strings("Title for each layer that needs a new pull request, in layer order.")),
                        ("draft", boolean("Open new pull requests as drafts.")),
                    ],
                    &["workspaceId", "workspaceIds"],
                )
            },
            |arguments| {
                let mut invocation = pr(arguments, &["stack", "create"])?
                    .option_if("--base", arguments.string("baseBranch"))
                    .flag_if("--draft", arguments.flag("draft"));
                for layer in arguments.list("workspaceIds").unwrap_or_default() {
                    invocation = invocation.option("--layer", layer);
                }
                for title in arguments.list("titles").unwrap_or_default() {
                    invocation = invocation.option("--title", title);
                }
                Ok(invocation)
            },
        )),
        slow(execute(
            "link_pull_request_stack",
            "Link Pull Request Stack",
            "Stack existing GitHub pull requests, bottom to top, or append them to the stack of the workspace's pull request. A new stack needs at least two and must include the workspace's pull request; every branch must descend from the one below. Needs the gh-stack extension.",
            || {
                object(
                    &[workspace(), ("numbers", string("Pull request numbers, bottom to top, separated by commas, such as 12,13."))],
                    &["workspaceId", "numbers"],
                )
            },
            |arguments| {
                Ok(pr(arguments, &["stack", "link"])?.option("--numbers", arguments.required("numbers")?))
            },
        )),
        ToolSpec {
            destructive: true,
            ..slow(execute(
                "merge_pull_request_stack",
                "Merge Pull Request Stack",
                "Merge the GitHub stack atomically through the workspace's pull request: every layer at or below it merges. Every affected layer must be open and ready. Without method the first allowed one is used.",
                || {
                    object(
                        &[
                            workspace(),
                            super::number(),
                            ("method", one_of("Merge method.", &MERGE_METHODS[..3])),
                        ],
                        &["workspaceId"],
                    )
                },
                |arguments| {
                    Ok(numbered(arguments, &["stack", "merge"])?
                        .option_if("--method", arguments.string("method")))
                },
            ))
        },
    ]
}

fn slow(tool: ToolSpec) -> ToolSpec {
    ToolSpec {
        timeout_seconds: LAUNCH_TIMEOUT,
        ..tool
    }
}

fn strings(description: &str) -> Value {
    json!({
        "type": "array",
        "items": { "type": "string", "minLength": 1 },
        "minItems": 1,
        "description": description,
    })
}

fn with_profile(invocation: Invocation, profile: Option<String>) -> Invocation {
    match profile {
        Some(profile) if profile.starts_with("prof_") => invocation.option("--profile-id", profile),
        Some(profile) => invocation.option("--profile", profile),
        None => invocation,
    }
}

fn watch(arguments: &ToolArguments, action: &str) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("workspace", &["pr-watch", action])
        .option("--workspace-id", arguments.required("workspaceId")?))
}

fn dispatch_schema(with_number: bool) -> Value {
    let mut properties = vec![workspace()];
    if with_number {
        properties.push(super::number());
    }
    properties.extend([
        ("handle", string("Running agent terminal handle to send the prompt to.")),
        ("tabId", string("Terminal tab to send the prompt to.")),
        ("profile", string("Agent profile id or name to open a new tab with when no terminal is given or running.")),
        ("preview", boolean("Only return the prompt; send nothing.")),
    ]);
    object(&properties, &["workspaceId"])
}

fn dispatch(arguments: &ToolArguments, action: &str) -> Result<Invocation, ToolInputError> {
    let invocation = numbered(arguments, &[action])?
        .option_if("--handle", arguments.string("handle"))
        .option_if("--tab-id", arguments.string("tabId"))
        .flag_if("--preview", arguments.flag("preview"));
    if !arguments.flag("preview")
        && arguments.string("handle").is_none()
        && arguments.string("tabId").is_none()
        && arguments.string("profile").is_none()
    {
        return Err(ToolInputError(
            "Pass handle, tabId, or profile, or preview true.".into(),
        ));
    }
    Ok(with_profile(invocation, arguments.string("profile")))
}

fn ship(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let invocation = pr(arguments, &["ship"])?
        .option("--base", arguments.required("baseBranch")?)
        .option_if("--scope", arguments.string("scope"))
        .flag_if("--draft", arguments.flag("draft"));
    let Some(follow) = arguments.object("followUpWatch") else {
        return Ok(invocation);
    };
    let text = |key: &str| follow.get(key).and_then(Value::as_str).map(str::to_owned);
    let off = |key: &str| follow.get(key).and_then(Value::as_bool) == Some(false);
    let mode = text("mode").unwrap_or_else(|| "fix".into());
    if !matches!(mode.as_str(), "fix" | "fixAndMerge") {
        return Err(ToolInputError(
            "followUpWatch.mode must be fix or fixAndMerge.".into(),
        ));
    }
    let invocation = invocation
        .option("--follow-up-watch", mode)
        .option_if("--handle", text("handle"))
        .flag_if("--no-checks", off("checks"))
        .flag_if("--no-comments", off("comments"))
        .flag_if("--no-conflicts", off("conflicts"));
    Ok(with_profile(invocation, text("profile")))
}
