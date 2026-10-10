//! `alera events`: read the runtime event journal by cursor.

use std::time::{Duration, Instant};

use anyhow::Result;
use serde_json::{json, Value};

use crate::cli::{EventsAction, EventsCommand, EventsFilterArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_RUNTIME_EVENTS_CAPABILITY;
use crate::{print_error, print_value, runtime_dir};

const POLL_INTERVAL: Duration = Duration::from_millis(500);

pub async fn run(command: EventsCommand) -> i32 {
    let json_output = command.output.json;
    let result = async {
        let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
            &runtime_dir(&command.runtime),
            RUNTIME_HOST_RUNTIME_EVENTS_CAPABILITY,
        )
        .await?;
        match command.action {
            EventsAction::List(args) => list(&mut client, &args.filter).await,
            EventsAction::Wait(args) => {
                wait(
                    &mut client,
                    &args.filter,
                    Duration::from_secs(args.timeout_seconds),
                )
                .await
            }
        }
    }
    .await;
    match result {
        Ok(page) => {
            let count = page["events"].as_array().map_or(0, Vec::len);
            let message = format!("{count} event(s), cursor {}", page["cursor"]);
            print_value(&page, json_output, &message);
            0
        }
        Err(error) => print_error(error),
    }
}

fn payload(filter: &EventsFilterArgs) -> Value {
    json!({
        "after": filter.after,
        "kinds": filter.kinds,
        "workspaceId": filter.workspace_id,
        "limit": filter.limit,
    })
}

async fn list(client: &mut RuntimeHostRpcClient, filter: &EventsFilterArgs) -> Result<Value> {
    client
        .request_value("runtimeEvents.list", &payload(filter))
        .await
}

/// Polls from the cursor until a matching event arrives or the time is up.
/// The cursor still advances past events the filter skips.
async fn wait(
    client: &mut RuntimeHostRpcClient,
    filter: &EventsFilterArgs,
    timeout: Duration,
) -> Result<Value> {
    let deadline = Instant::now() + timeout;
    let mut request = payload(filter);
    loop {
        let page = client.request_value("runtimeEvents.list", &request).await?;
        let found = page["events"]
            .as_array()
            .is_some_and(|events| !events.is_empty());
        let now = Instant::now();
        if found || page["truncated"] == true || now >= deadline {
            let mut page = page;
            page["timedOut"] = json!(!found && now >= deadline);
            return Ok(page);
        }
        request["after"] = page["cursor"].clone();
        tokio::time::sleep(POLL_INTERVAL.min(deadline - now)).await;
    }
}
