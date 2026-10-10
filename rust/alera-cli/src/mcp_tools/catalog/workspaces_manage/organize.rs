//! Sidebar organization (sections, tags, parent and child links) and the
//! issue a workspace was created for.

use serde_json::{json, Value};

use super::{workspace_id, NAME_LIMIT};
use crate::mcp_tools::catalog::{execute, no_arguments, read, LAUNCH_TIMEOUT};
use crate::mcp_tools::schema::{boolean, object, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

const URL_LIMIT: u64 = 2_048;

fn ids(description: &str) -> Value {
    json!({
        "type": "array",
        "items": { "type": "string", "minLength": 1 },
        "minItems": 1,
        "uniqueItems": true,
        "description": description,
    })
}

fn tree() -> Value {
    boolean("Also apply to every descendant workspace, like the sidebar's Tree actions.")
}

fn section(action: &'static str, arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("workspace", &["section", action])
        .option("--workspace-id", arguments.required("workspaceId")?)
        .flag_if("--tree", arguments.flag("tree")))
}

fn relation_schema() -> Value {
    object(
        &[
            ("parentWorkspaceId", string("Parent workspace id.")),
            ("childWorkspaceId", string("Child workspace id.")),
        ],
        &["parentWorkspaceId", "childWorkspaceId"],
    )
}

fn relation(action: &'static str, arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("workspace", &[action])
        .option(
            "--parent-workspace-id",
            arguments.required("parentWorkspaceId")?,
        )
        .option(
            "--child-workspace-id",
            arguments.required("childWorkspaceId")?,
        ))
}

fn tag_schema() -> Value {
    object(
        &[
            ("workspaceId", workspace_id()),
            ("tagId", string("Tag id from list_tags.")),
        ],
        &["workspaceId", "tagId"],
    )
}

fn tagging(action: &'static str, arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("workspace", &[action])
        .option("--workspace-id", arguments.required("workspaceId")?)
        .option("--tag-id", arguments.required("tagId")?))
}

fn issue(action: &'static str, arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("workspace", &["issue", action])
        .option("--workspace-id", arguments.required("workspaceId")?))
}

fn workspace_only() -> Value {
    object(&[("workspaceId", workspace_id())], &["workspaceId"])
}

fn idempotent(tool: ToolSpec) -> ToolSpec {
    ToolSpec {
        idempotent: true,
        ..tool
    }
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_sections",
            "List Sections",
            "List the sidebar sections workspaces are grouped in. A workspace without a section is in Others.",
            no_arguments,
            |_| Ok(Invocation::new("workspace", &["section", "list"])),
        ),
        execute(
            "create_section",
            "Create Section",
            "Create a sidebar section and put a first workspace in it.",
            || {
                object(
                    &[
                        ("name", text("Section name.", NAME_LIMIT)),
                        ("workspaceId", workspace_id()),
                        ("tree", tree()),
                    ],
                    &["name", "workspaceId"],
                )
            },
            |arguments| {
                Ok(section("create", arguments)?.option("--name", arguments.required("name")?))
            },
        ),
        idempotent(execute(
            "set_workspace_section",
            "Set Workspace Section",
            "Move a workspace to a section, given by sectionId or by its unique name.",
            || {
                object(
                    &[
                        ("workspaceId", workspace_id()),
                        ("sectionId", string("Section id from list_sections.")),
                        ("section", string("Section name, matched without case.")),
                        ("tree", tree()),
                    ],
                    &["workspaceId"],
                )
            },
            |arguments| {
                let (id, name) = (arguments.string("sectionId"), arguments.string("section"));
                if id.is_some() == name.is_some() {
                    return Err(ToolInputError("Pass sectionId or section.".into()));
                }
                Ok(section("set", arguments)?
                    .option_if("--section-id", id)
                    .option_if("--section", name))
            },
        )),
        idempotent(execute(
            "clear_workspace_section",
            "Clear Workspace Section",
            "Move a workspace to Others, out of any section.",
            || object(&[("workspaceId", workspace_id()), ("tree", tree())], &["workspaceId"]),
            |arguments| section("clear", arguments),
        )),
        ToolSpec {
            destructive: true,
            ..idempotent(execute(
                "remove_section",
                "Remove Section",
                "Delete a sidebar section. Its workspaces are kept and move to Others.",
                || object(&[("sectionId", string("Section id from list_sections."))], &["sectionId"]),
                |arguments| {
                    Ok(Invocation::new("workspace", &["section", "remove"])
                        .option("--id", arguments.required("sectionId")?))
                },
            ))
        },
        read(
            "list_tags",
            "List Tags",
            "List the workspace tags defined in this runtime.",
            no_arguments,
            |_| Ok(Invocation::new("tag", &["list"])),
        ),
        idempotent(execute(
            "upsert_tag",
            "Create Or Update Tag",
            "Create a workspace tag, or rename or recolor one when tagId is given.",
            || {
                object(
                    &[
                        ("name", text("Tag name.", NAME_LIMIT)),
                        ("tagId", string("Existing tag id to update.")),
                        ("color", string("Tag color, such as #3B82F6.")),
                    ],
                    &["name"],
                )
            },
            |arguments| {
                Ok(Invocation::new("tag", &["upsert"])
                    .option("--name", arguments.required("name")?)
                    .option_if("--id", arguments.string("tagId"))
                    .option_if("--color", arguments.string("color")))
            },
        )),
        ToolSpec {
            destructive: true,
            ..idempotent(execute(
                "remove_tag",
                "Remove Tag",
                "Delete a workspace tag and take it off every workspace.",
                || object(&[("tagId", string("Tag id from list_tags."))], &["tagId"]),
                |arguments| {
                    Ok(Invocation::new("tag", &["remove"]).option("--id", arguments.required("tagId")?))
                },
            ))
        },
        idempotent(execute(
            "tag_workspace",
            "Tag Workspace",
            "Add a tag to a workspace.",
            tag_schema,
            |arguments| tagging("tag", arguments),
        )),
        idempotent(execute(
            "untag_workspace",
            "Untag Workspace",
            "Take a tag off a workspace.",
            tag_schema,
            |arguments| tagging("untag", arguments),
        )),
        idempotent(execute(
            "link_workspaces",
            "Link Workspaces",
            "Make one workspace the child of another, so it nests under it in the sidebar.",
            relation_schema,
            |arguments| relation("link", arguments),
        )),
        idempotent(execute(
            "unlink_workspaces",
            "Unlink Workspaces",
            "Remove a parent and child link between two workspaces.",
            relation_schema,
            |arguments| relation("unlink", arguments),
        )),
        read(
            "preview_workspace_cascade",
            "Preview Workspace Cascade",
            "List the workspaces an action would reach from some workspaces, optionally adding their descendants and every workspace sharing the given tags.",
            || {
                object(
                    &[
                        ("workspaceIds", ids("Starting workspace ids.")),
                        ("tagIds", ids("Tag ids whose workspaces are included.")),
                        ("descendants", boolean("Include the descendants of the starting workspaces.")),
                        ("tags", boolean("Include every workspace with the given tags.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                let mut invocation = Invocation::new("workspace", &["cascade-preview"]);
                for id in arguments.list("workspaceIds").unwrap_or_default() {
                    invocation = invocation.option("--workspace-id", id);
                }
                for id in arguments.list("tagIds").unwrap_or_default() {
                    invocation = invocation.option("--tag-id", id);
                }
                Ok(invocation
                    .flag_if("--descendants", arguments.flag("descendants"))
                    .flag_if("--tags", arguments.flag("tags")))
            },
        ),
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..read(
                "show_workspace_issue",
                "Show Workspace Issue",
                "Show the issue linked to a workspace, fetched fresh from GitHub, GitLab, or Azure DevOps, or only its saved title and state with cached.",
                || object(&[("workspaceId", workspace_id()), ("cached", boolean("Skip the forge and show the saved title and state."))], &["workspaceId"]),
                |arguments| Ok(issue("show", arguments)?.flag_if("--cached", arguments.flag("cached"))),
            )
        },
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..idempotent(execute(
                "link_workspace_issue",
                "Link Workspace Issue",
                "Link an issue URL to a workspace, replacing its linked issue. Trackers Alera does not know are kept as a plain link.",
                || object(&[("workspaceId", workspace_id()), ("url", text("Issue URL.", URL_LIMIT))], &["workspaceId", "url"]),
                |arguments| Ok(issue("link", arguments)?.flag("--").flag(&arguments.required("url")?)),
            ))
        },
        idempotent(execute(
            "unlink_workspace_issue",
            "Unlink Workspace Issue",
            "Remove the issue linked to a workspace.",
            workspace_only,
            |arguments| issue("unlink", arguments),
        )),
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..read(
                "fetch_issue",
                "Fetch Issue",
                "Read an issue or work item from GitHub, GitLab, or Azure DevOps by URL, with its title, state, labels, assignees, and body, through the forge CLI on this machine.",
                || object(&[("url", text("Issue or work item URL.", URL_LIMIT))], &["url"]),
                |arguments| Ok(Invocation::new("issue", &["show"]).flag("--").flag(&arguments.required("url")?)),
            )
        },
    ]
}
