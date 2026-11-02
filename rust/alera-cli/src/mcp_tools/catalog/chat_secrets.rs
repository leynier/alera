//! `request_secret` (`agentChatSecretRequestsV1`): ask the person for a
//! secret in a masked card. The agent never sees the value; it gets an
//! owner-only file path or a one-use `secretRef`.

use super::{execute, WAIT_TIMEOUT};
use crate::mcp_tools::schema::{object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut request = execute(
        "request_secret",
        "Request a Secret",
        "Ask the person to enter a secret in a private card and wait up to 45 seconds. You never see the value. Prefer delivery \"file\" (the default and recommended mode): you get an owner-only file path to read inside a shell command, e.g. TOKEN=\"$(cat <file>)\" wrangler whoami; never print it. delivery \"ref\" gives a one-use secretRef to spend with TOKEN=\"$(alera chat secret read --ref <ref>)\". Both expire after 24 hours. On status pending, call again with the returned requestId to keep waiting. Only a person answers: never ask for a secret in chat or invent one, and a parent agent cannot answer for you.",
        || {
            object(
                &[
                    ("label", text("Card title, such as 'GitHub webhook secret'.", 200)),
                    ("reason", text("What it is for and where to get it.", 2_000)),
                    ("placeholder", string("Hint shown in the empty field.")),
                    (
                        "delivery",
                        one_of(
                            "file (default, recommended) for a shell command; ref for alera chat secret read.",
                            &["file", "ref"],
                        ),
                    ),
                    (
                        "requestId",
                        string("The requestId a pending answer returned; keeps waiting on that card."),
                    ),
                ],
                &[],
            )
        },
        |arguments| {
            let invocation = Invocation::new("chat", &["request-secret"]);
            if let Some(request_id) = arguments.string("requestId") {
                return Ok(invocation.option("--secret-request-id", request_id));
            }
            Ok(invocation
                .option("--label", arguments.required("label")?)
                .option("--reason", arguments.required("reason")?)
                .option_if("--placeholder", arguments.string("placeholder"))
                .option_if("--delivery", arguments.string("delivery")))
        },
    );
    request.timeout_seconds = WAIT_TIMEOUT;
    vec![request]
}
