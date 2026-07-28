use std::io::Read;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};
use serde_json::{json, Map, Value};

use crate::cli::{
    BrowserAction, BrowserCaptureArgs, BrowserClosedTabsAction, BrowserCommand,
    BrowserCookiesAction, BrowserEvalArgs, BrowserHistoryAction, BrowserPermissionDecisionArg,
    BrowserPermissionsAction, BrowserProfilesAction, BrowserRefArgs, BrowserRefTextArgs,
    BrowserSettingsAction, BrowserTimedPageArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_BROWSER_AUTOMATION_ROUTING_CAPABILITY, RUNTIME_HOST_BROWSER_PROFILES_CAPABILITY,
};

const CATALOG_DEADLINE_MS: u64 = 10_000;
const RESPONSE_GRACE_MS: u64 = 2_000;

pub async fn run(command: BrowserCommand) -> i32 {
    let runtime_dir = crate::runtime_dir(&command.runtime);
    let json_output = command.output.json;
    let action = command.action;
    let (request_type, payload) = match request_for_action(&action) {
        Ok(request) => request,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    let capability = required_capability(&action);
    let mut client = match RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &runtime_dir,
        capability,
    )
    .await
    {
        Ok(client) => client,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    let deadline_ms = action_deadline_ms(&action);
    match client
        .request_value_with_deadline(request_type, &payload, deadline_ms)
        .await
    {
        Ok(mut value) => {
            if let Err(error) = materialize_capture_output(&mut value, &action) {
                eprintln!("{error}");
                return 1;
            }
            report(&value, json_output, &action)
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn request_for_action(action: &BrowserAction) -> Result<(&'static str, Value)> {
    Ok(match action {
        BrowserAction::Capabilities => ("browser.capabilities", json!({})),
        BrowserAction::Tabs(args) => (
            "browser.tabs.list",
            json!({"workspaceId": args.workspace_id}),
        ),
        BrowserAction::Open(args) => (
            "browser.tabs.open",
            json!({
                "workspaceId": args.workspace_id,
                "url": args.url,
                "profileId": args.profile_id,
                "title": args.title,
                "pageId": args.page_id,
                "targetGroupId": args.target_group_id,
            }),
        ),
        BrowserAction::Close(args) => ("browser.tabs.close", json!({"pageId": args.page_id})),
        BrowserAction::Reopen(args) => (
            "browser.closedTabs.reopen",
            json!({"id": args.id, "targetGroupId": args.target_group_id}),
        ),
        BrowserAction::Navigate(args) => (
            "browser.navigate",
            with_page(&args.page, json!({"url": args.url})),
        ),
        BrowserAction::Back(args) => ("browser.back", page_payload(args)),
        BrowserAction::Forward(args) => ("browser.forward", page_payload(args)),
        BrowserAction::Reload(args) => ("browser.reload", page_payload(args)),
        BrowserAction::Stop(args) => ("browser.stop", page_payload(args)),
        BrowserAction::Snapshot(args) => (
            "browser.snapshot",
            with_page(
                &args.page,
                json!({
                    "interactiveOnly": args.interactive_only,
                    "maxNodes": args.max_nodes,
                }),
            ),
        ),
        BrowserAction::Click(args) => ("browser.ref.click", ref_payload(args, json!({}))),
        BrowserAction::Fill(args) => (
            "browser.ref.fill",
            ref_text_payload(args, read_text(args)?)?,
        ),
        BrowserAction::Type(args) => (
            "browser.ref.type",
            ref_text_payload(args, read_text(args)?)?,
        ),
        BrowserAction::Select(args) => (
            "browser.ref.select",
            ref_payload(&args.target, json!({"value": args.value})),
        ),
        BrowserAction::Focus(args) => ("browser.ref.focus", ref_payload(args, json!({}))),
        BrowserAction::Hover(args) => ("browser.ref.hover", ref_payload(args, json!({}))),
        BrowserAction::Scroll(args) => (
            "browser.ref.scroll",
            with_page(
                &args.page,
                json!({"ref": args.ref_id, "x": args.x, "y": args.y}),
            ),
        ),
        BrowserAction::Wait(args) => (
            "browser.wait",
            with_page(
                &args.page,
                json!({
                    "url": args.url,
                    "text": args.text,
                    "ref": args.ref_id,
                    "loadState": args.load_state.map(|state| state.as_wire()),
                }),
            ),
        ),
        BrowserAction::Eval(args) => (
            "browser.eval",
            with_page(&args.page, json!({"expression": eval_source(args)?})),
        ),
        BrowserAction::Screenshot(args) => ("browser.screenshot", capture_payload(args, false)),
        BrowserAction::FullScreenshot(args) => ("browser.screenshot", capture_payload(args, true)),
        BrowserAction::Pdf(args) => ("browser.pdf", capture_payload(args, false)),
        BrowserAction::Profiles(command) => match &command.action {
            BrowserProfilesAction::List => ("browser.profiles.list", json!({})),
        },
        BrowserAction::Settings(command) => match &command.action {
            BrowserSettingsAction::Get => ("browser.settings.get", json!({})),
            BrowserSettingsAction::Set(args) => (
                "browser.settings.set",
                json!({"searchEngine": args.search_engine.as_wire()}),
            ),
        },
        BrowserAction::History(command) => match &command.action {
            BrowserHistoryAction::List(args) => (
                "browser.history.list",
                json!({"profileId": args.profile_id, "limit": args.limit}),
            ),
            BrowserHistoryAction::Clear(args) => (
                "browser.history.clear",
                json!({"profileId": args.profile_id}),
            ),
        },
        BrowserAction::ClosedTabs(command) => match &command.action {
            BrowserClosedTabsAction::List(args) => (
                "browser.closedTabs.list",
                json!({"profileId": args.profile_id, "limit": args.limit}),
            ),
            BrowserClosedTabsAction::Remove(args) => {
                ("browser.closedTabs.remove", json!({"id": args.id}))
            }
            BrowserClosedTabsAction::Reopen(args) => (
                "browser.closedTabs.reopen",
                json!({"id": args.id, "targetGroupId": args.target_group_id}),
            ),
        },
        BrowserAction::Permissions(command) => match &command.action {
            BrowserPermissionsAction::List(args) => (
                "browser.permissions.list",
                json!({"profileId": args.profile_id, "origin": args.origin}),
            ),
            BrowserPermissionsAction::Set(args) => (
                "browser.permissions.set",
                json!({
                    "profileId": args.key.profile_id,
                    "origin": args.key.origin,
                    "permission": args.key.permission,
                    "decision": permission_decision(args.decision),
                }),
            ),
            BrowserPermissionsAction::Remove(args) => (
                "browser.permissions.remove",
                json!({
                    "profileId": args.profile_id,
                    "origin": args.origin,
                    "permission": args.permission,
                }),
            ),
        },
        BrowserAction::Cookies(command) => match &command.action {
            BrowserCookiesAction::List(args) => ("browser.cookies.list", page_payload(args)),
            BrowserCookiesAction::Delete(args) => (
                "browser.cookies.delete",
                with_page(
                    &args.page,
                    json!({
                        "name": args.name,
                        "domain": args.domain,
                        "path": args.path,
                    }),
                ),
            ),
            BrowserCookiesAction::Clear(args) => ("browser.cookies.clear", page_payload(args)),
        },
    })
}

fn required_capability(action: &BrowserAction) -> &'static str {
    match action {
        BrowserAction::Capabilities
        | BrowserAction::Navigate(_)
        | BrowserAction::Back(_)
        | BrowserAction::Forward(_)
        | BrowserAction::Reload(_)
        | BrowserAction::Stop(_)
        | BrowserAction::Snapshot(_)
        | BrowserAction::Click(_)
        | BrowserAction::Fill(_)
        | BrowserAction::Type(_)
        | BrowserAction::Select(_)
        | BrowserAction::Focus(_)
        | BrowserAction::Hover(_)
        | BrowserAction::Scroll(_)
        | BrowserAction::Wait(_)
        | BrowserAction::Eval(_)
        | BrowserAction::Screenshot(_)
        | BrowserAction::FullScreenshot(_)
        | BrowserAction::Pdf(_)
        | BrowserAction::Cookies(_) => RUNTIME_HOST_BROWSER_AUTOMATION_ROUTING_CAPABILITY,
        _ => RUNTIME_HOST_BROWSER_PROFILES_CAPABILITY,
    }
}

fn action_deadline_ms(action: &BrowserAction) -> u64 {
    page_timeout(action)
        .map(|timeout| timeout.saturating_add(RESPONSE_GRACE_MS))
        .unwrap_or(CATALOG_DEADLINE_MS)
}

fn page_timeout(action: &BrowserAction) -> Option<u64> {
    match action {
        BrowserAction::Navigate(args) => Some(args.page.timeout_ms),
        BrowserAction::Back(args)
        | BrowserAction::Forward(args)
        | BrowserAction::Reload(args)
        | BrowserAction::Stop(args) => Some(args.timeout_ms),
        BrowserAction::Snapshot(args) => Some(args.page.timeout_ms),
        BrowserAction::Click(args) | BrowserAction::Focus(args) | BrowserAction::Hover(args) => {
            Some(args.page.timeout_ms)
        }
        BrowserAction::Fill(args) | BrowserAction::Type(args) => Some(args.target.page.timeout_ms),
        BrowserAction::Select(args) => Some(args.target.page.timeout_ms),
        BrowserAction::Scroll(args) => Some(args.page.timeout_ms),
        BrowserAction::Wait(args) => Some(args.page.timeout_ms),
        BrowserAction::Eval(args) => Some(args.page.timeout_ms),
        BrowserAction::Screenshot(args)
        | BrowserAction::FullScreenshot(args)
        | BrowserAction::Pdf(args) => Some(args.page.timeout_ms),
        BrowserAction::Cookies(command) => Some(match &command.action {
            BrowserCookiesAction::List(args) | BrowserCookiesAction::Clear(args) => args.timeout_ms,
            BrowserCookiesAction::Delete(args) => args.page.timeout_ms,
        }),
        _ => None,
    }
}

fn page_payload(page: &BrowserTimedPageArgs) -> Value {
    json!({"pageId": page.page_id, "timeoutMs": page.timeout_ms})
}

fn with_page(page: &BrowserTimedPageArgs, mut value: Value) -> Value {
    let object = value.as_object_mut().expect("browser payload is an object");
    object.insert("pageId".to_string(), json!(page.page_id));
    object.insert("timeoutMs".to_string(), json!(page.timeout_ms));
    value
}

fn ref_payload(args: &BrowserRefArgs, base: Value) -> Value {
    with_page(
        &args.page,
        merge(
            base,
            json!({"ref": args.ref_id, "snapshotId": args.snapshot_id}),
        ),
    )
}

fn ref_text_payload(args: &BrowserRefTextArgs, text: String) -> Result<Value> {
    Ok(ref_payload(&args.target, json!({"text": text})))
}

fn read_text(args: &BrowserRefTextArgs) -> Result<String> {
    if args.text_stdin {
        return read_stdin();
    }
    args.text
        .clone()
        .ok_or_else(|| anyhow!("use --text or --text-stdin"))
}

fn eval_source(args: &BrowserEvalArgs) -> Result<String> {
    if args.stdin {
        return read_stdin();
    }
    if let Some(file) = &args.file {
        return std::fs::read_to_string(file)
            .with_context(|| format!("failed reading browser eval file {file}"));
    }
    args.expression
        .clone()
        .ok_or_else(|| anyhow!("use --expression, --file, or --stdin"))
}

fn read_stdin() -> Result<String> {
    let mut value = String::new();
    std::io::stdin().read_to_string(&mut value)?;
    Ok(value)
}

fn capture_payload(args: &BrowserCaptureArgs, full_page: bool) -> Value {
    with_page(&args.page, json!({"fullPage": full_page}))
}

fn absolute_path(value: &str) -> Result<PathBuf> {
    let path = Path::new(value);
    if path.is_absolute() {
        return Ok(path.to_path_buf());
    }
    Ok(std::env::current_dir()?.join(path))
}

fn materialize_capture_output(value: &mut Value, action: &BrowserAction) -> Result<()> {
    if value.get("ok").and_then(Value::as_bool) != Some(true) {
        return Ok(());
    }
    let Some(output) = requested_capture_output(action) else {
        return Ok(());
    };
    let source = value
        .get("artifact")
        .and_then(|artifact| artifact.get("path"))
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("browser capture did not return an artifact path"))?;
    let destination = absolute_path(output)?;
    if Path::new(source) != destination {
        std::fs::copy(source, &destination).with_context(|| {
            format!(
                "failed copying browser artifact to {}",
                destination.display()
            )
        })?;
    }
    value
        .as_object_mut()
        .expect("browser response is an object")
        .insert("savedTo".to_string(), json!(destination.to_string_lossy()));
    Ok(())
}

fn requested_capture_output(action: &BrowserAction) -> Option<&str> {
    match action {
        BrowserAction::Screenshot(args)
        | BrowserAction::FullScreenshot(args)
        | BrowserAction::Pdf(args) => args.output.as_deref(),
        _ => None,
    }
}

fn permission_decision(value: BrowserPermissionDecisionArg) -> &'static str {
    value.as_wire()
}

fn merge(mut left: Value, right: Value) -> Value {
    let left = left.as_object_mut().expect("browser payload is an object");
    left.extend(right.as_object().cloned().unwrap_or_else(Map::new));
    Value::Object(left.clone())
}

fn report(value: &Value, json_output: bool, action: &BrowserAction) -> i32 {
    let ok = value.get("ok").and_then(Value::as_bool).unwrap_or(false);
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".to_string())
        );
        return i32::from(!ok);
    }
    if !ok {
        let error = &value["error"];
        eprintln!(
            "{}: {}",
            error["code"].as_str().unwrap_or("browser_error"),
            error["message"]
                .as_str()
                .unwrap_or("browser request failed")
        );
        if let Some(steps) = error["nextSteps"].as_array() {
            for step in steps.iter().filter_map(Value::as_str) {
                eprintln!("  - {step}");
            }
        }
        return 1;
    }
    match action {
        BrowserAction::Tabs(_) => render_named_items(value, "tabs", "browser tabs"),
        BrowserAction::Profiles(_) => render_named_items(value, "profiles", "browser profiles"),
        BrowserAction::History(_) => render_named_items(value, "entries", "history entries"),
        BrowserAction::ClosedTabs(_) => render_named_items(value, "tabs", "closed tabs"),
        BrowserAction::Permissions(_) => {
            render_named_items(value, "permissions", "browser permissions")
        }
        BrowserAction::Cookies(_) => render_named_items(value, "cookies", "cookie metadata"),
        _ => println!(
            "{}",
            serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".to_string())
        ),
    }
    0
}

fn render_named_items(value: &Value, key: &str, label: &str) {
    if let Some(items) = value.get(key).and_then(Value::as_array) {
        if items.is_empty() {
            println!("no {label}");
            return;
        }
        for item in items {
            println!(
                "{}",
                serde_json::to_string(item).unwrap_or_else(|_| "{}".to_string())
            );
        }
    } else {
        println!(
            "{}",
            serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".to_string())
        );
    }
}

#[cfg(test)]
#[path = "browser_commands_tests.rs"]
mod tests;
