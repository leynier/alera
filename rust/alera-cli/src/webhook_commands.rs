//! `alera webhook`: manage the signed webhooks that receive runtime events.

use serde_json::{json, Value};

use crate::cli::{WebhookAction, WebhookCommand};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_RUNTIME_EVENTS_CAPABILITY;
use crate::{print_error, print_value, runtime_dir};

/// Cloud calls can take longer than local requests.
const CLOUD_DEADLINE_MS: u64 = 30_000;

pub async fn run(command: WebhookCommand) -> i32 {
    let json_output = command.output.json;
    let (request, payload) = match &command.action {
        WebhookAction::List => ("webhook.list", json!({})),
        WebhookAction::Add(args) => {
            let mut payload = json!({ "url": args.url });
            if !args.kinds.is_empty() {
                payload["kinds"] = json!(args.kinds);
            }
            if !args.runtime_ids.is_empty() {
                payload["runtimeIds"] = json!(args.runtime_ids);
            }
            ("webhook.create", payload)
        }
        WebhookAction::Remove(args) => ("webhook.delete", json!({ "id": args.id })),
        WebhookAction::Test(args) => ("webhook.test", json!({ "id": args.id })),
    };
    let result = async {
        let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
            &runtime_dir(&command.runtime),
            RUNTIME_HOST_RUNTIME_EVENTS_CAPABILITY,
        )
        .await?;
        client
            .request_value_with_deadline(request, &payload, CLOUD_DEADLINE_MS)
            .await
    }
    .await;
    match result {
        Ok(value) => {
            print_value(&value, json_output, &message(&command.action, &value));
            0
        }
        Err(error) => print_error(error),
    }
}

fn message(action: &WebhookAction, value: &Value) -> String {
    match action {
        WebhookAction::List => format!(
            "{} webhook(s)",
            value["webhooks"].as_array().map_or(0, Vec::len)
        ),
        WebhookAction::Add(_) => format!(
            "webhook {} added; signing secret (shown once): {}",
            value["webhook"]["id"].as_str().unwrap_or("?"),
            value["secret"].as_str().unwrap_or("?")
        ),
        WebhookAction::Remove(args) => format!("webhook {} removed", args.id),
        WebhookAction::Test(args) => format!("test delivery queued for webhook {}", args.id),
    }
}
