//! The runtime event journal: polling with a cursor works in every MCP
//! client, including those that cannot receive notifications.

use super::{admin, no_arguments, read, wait_schema, wait_seconds, WAIT_TIMEOUT};
use crate::mcp_tools::schema::{integer, object, string, string_list};
use crate::mcp_tools::{Invocation, ToolArguments, ToolSpec};

const KINDS: &[&str] = &[
    "inbox.reply",
    "inbox.question.status",
    "agent.status",
    "terminal.exit",
    "orchestration.task.state",
    "orchestration.gate.created",
    "orchestration.escalation",
    "automation.run.state",
    "workspace.start.state",
    "workspace.lifecycle",
    "pullRequest.watch",
];

fn filter_properties() -> Vec<(&'static str, serde_json::Value)> {
    vec![
        (
            "after",
            integer(
                "Cursor from a previous result; omit to read from the oldest retained event.",
                0,
                u64::MAX >> 11,
            ),
        ),
        ("kinds", string_list("Only these event kinds.", KINDS)),
        ("workspaceId", string("Only events of this workspace.")),
        ("limit", integer("Maximum events (default 100).", 1, 500)),
    ]
}

fn filtered(invocation: Invocation, arguments: &ToolArguments) -> Invocation {
    let invocation = invocation
        .option(
            "--after",
            arguments.integer("after").unwrap_or(0).to_string(),
        )
        .option_if("--workspace-id", arguments.string("workspaceId"))
        .option_if(
            "--limit",
            arguments.integer("limit").map(|value| value.to_string()),
        );
    match arguments.list("kinds") {
        Some(kinds) => invocation.option("--kind", kinds.join(",")),
        None => invocation,
    }
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_events",
            "List Events",
            "List runtime events after a cursor, oldest first: inbox replies, question states, agent states, terminal exits, task and run changes, decision gates, automation runs, workspace starts and lifecycle, and pull request watch actions. Events carry ids and states; read details with the matching tool. Pass the returned cursor as after next time. truncated means older events were pruned.",
            || object(&filter_properties(), &[]),
            |arguments| Ok(filtered(Invocation::new("events", &["list"]), arguments)),
        ),
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "wait_for_events",
                "Wait For Events",
                "Wait up to timeoutSeconds for runtime events after a cursor, then return them with the next cursor. Use it instead of polling each question or task: one wait covers every kind you filter for. Call again with the returned cursor to keep following.",
                || {
                    let mut properties = filter_properties();
                    properties.push(("timeoutSeconds", wait_schema()));
                    object(&properties, &[])
                },
                |arguments| {
                    Ok(filtered(Invocation::new("events", &["wait"]), arguments).option(
                        "--timeout-seconds",
                        wait_seconds(arguments, 30).to_string(),
                    ))
                },
            )
        },
        read(
            "list_webhooks",
            "List Webhooks",
            "List the signed webhooks that receive runtime events through the Alera cloud for this account, with their kinds, status, and last delivery.",
            no_arguments,
            |_| Ok(Invocation::new("webhook", &["list"])),
        ),
        admin(
            "create_webhook",
            "Create Webhook",
            "Add an HTTPS webhook that receives this runtime's events as signed POST requests (Standard Webhooks). Events carry ids and states only. Returns the signing secret once. Needs a signed-in Alera account.",
            || {
                object(
                    &[
                        ("url", string("Public HTTPS endpoint. Private and loopback addresses are refused.")),
                        ("kinds", string_list("Event kinds to send (default every kind).", KINDS)),
                    ],
                    &["url"],
                )
            },
            |arguments| {
                let invocation = Invocation::new("webhook", &["add"])
                    .option("--url", arguments.required("url")?);
                Ok(match arguments.list("kinds") {
                    Some(kinds) => invocation.option("--kind", kinds.join(",")),
                    None => invocation,
                })
            },
        ),
        ToolSpec {
            destructive: true,
            idempotent: true,
            ..admin(
                "delete_webhook",
                "Delete Webhook",
                "Delete a webhook so it receives no more events.",
                || object(&[("webhookId", string("Webhook id from list_webhooks."))], &["webhookId"]),
                |arguments| {
                    Ok(Invocation::new("webhook", &["remove"])
                        .option("--id", arguments.required("webhookId")?))
                },
            )
        },
        admin(
            "test_webhook",
            "Test Webhook",
            "Send a signed test delivery to a webhook.",
            || object(&[("webhookId", string("Webhook id from list_webhooks."))], &["webhookId"]),
            |arguments| {
                Ok(Invocation::new("webhook", &["test"])
                    .option("--id", arguments.required("webhookId")?))
            },
        ),
    ]
}
