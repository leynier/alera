use serde_json::{json, Value};

use crate::cli::TerminalAction;
use crate::orchestration_terminal_commands::print_terminal_wait_result;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::{print_error, print_value};

pub(crate) fn required_capability(action: &TerminalAction) -> Option<&'static str> {
    match action {
        TerminalAction::Write(args) if args.enter || args.submit => {
            Some(crate::terminal_host::protocol::RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY)
        }
        TerminalAction::Wait(_) => {
            Some(crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY)
        }
        TerminalAction::List(_) | TerminalAction::Show(_) | TerminalAction::Prune(_) => {
            Some(
                crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
            )
        }
        _ => None,
    }
}

pub async fn run(
    client: &mut RuntimeHostRpcClient,
    action: TerminalAction,
    json_output: bool,
) -> i32 {
    match action {
        TerminalAction::List(args) => {
            let workspace = args.workspace.or_else(|| {
                std::env::var("ALERA_WORKSPACE_ID")
                    .ok()
                    .filter(|value| !value.trim().is_empty())
            });
            match client
                .request_value("orchestration.terminals", &json!({ "workspace": workspace }))
                .await
            {
                Ok(value) => {
                    print_terminal_value(&value, json_output, format_terminal_list);
                    0
                }
                Err(error) => print_error(error),
            }
        }
        TerminalAction::Show(args) => match client
            .request_value(
                "orchestration.terminalShow",
                &json!({ "handle": args.handle }),
            )
            .await
        {
            Ok(value) => {
                print_terminal_value(&value, json_output, format_terminal_show);
                0
            }
            Err(error) => print_error(error),
        },
        TerminalAction::Wait(args) => match client
            .request_value_with_deadline(
                "orchestration.terminalWait",
                &json!({
                    "terminal": args.terminal,
                    "target": args.target,
                    "timeoutMs": args.timeout_ms,
                }),
                args.timeout_ms.saturating_add(5_000),
            )
            .await
        {
            Ok(value) => {
                print_terminal_wait_result(&value, json_output)
            }
            Err(error) => print_error(error),
        },
        TerminalAction::Prune(args) => match client
            .request_value(
                "orchestration.terminalPrune",
                &json!({
                    "workspace": args.workspace.or_else(|| std::env::var("ALERA_WORKSPACE_ID").ok()),
                    "apply": args.apply,
                }),
            )
            .await
        {
            Ok(value) => {
                print_terminal_value(&value, json_output, format_terminal_prune);
                0
            }
            Err(error) => print_error(error),
        },
        TerminalAction::Read(_) | TerminalAction::Write(_) => unreachable!(),
    }
}

fn print_terminal_value(value: &Value, json_output: bool, formatter: fn(&Value) -> String) {
    if json_output {
        print_value(value, true, "");
    } else {
        println!("{}", formatter(value));
    }
}

fn format_terminal_list(value: &Value) -> String {
    let items = value
        .get("items")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    if items.is_empty() {
        return "0 terminals".to_string();
    }
    items
        .iter()
        .map(|terminal| {
            format!(
                "{}  {}  agent={}  state={}  workspace={}",
                string_field(terminal, "handle"),
                if terminal
                    .get("running")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
                {
                    "running"
                } else {
                    "stopped"
                },
                optional_string_field(terminal, "agentType"),
                optional_string_field(terminal, "agentState"),
                string_field(terminal, "workspaceId"),
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn format_terminal_show(value: &Value) -> String {
    let dispatch = value.get("dispatch").filter(|item| item.is_object());
    [
        ("Handle", string_field(value, "handle")),
        ("Workspace", string_field(value, "workspaceId")),
        ("Tab", string_field(value, "tabId")),
        (
            "Process",
            if value
                .get("running")
                .and_then(Value::as_bool)
                .unwrap_or(false)
            {
                "running"
            } else {
                "stopped"
            },
        ),
        ("Agent", optional_string_field(value, "agentType")),
        ("Agent State", optional_string_field(value, "agentState")),
        ("Startup State", string_field(value, "startupState")),
        (
            "Startup Error",
            optional_string_field(value, "startupError"),
        ),
        (
            "Dispatch",
            dispatch
                .map(|item| string_field(item, "id"))
                .unwrap_or("none"),
        ),
        (
            "Dispatch Status",
            dispatch
                .map(|item| string_field(item, "status"))
                .unwrap_or("none"),
        ),
    ]
    .into_iter()
    .map(|(label, item)| format!("{label}: {item}"))
    .collect::<Vec<_>>()
    .join("\n")
}

fn format_terminal_prune(value: &Value) -> String {
    let candidates = string_array(value, "candidates");
    let removed = string_array(value, "removed");
    if value.get("dryRun").and_then(Value::as_bool).unwrap_or(true) {
        return format!(
            "{} stopped terminal(s) would be removed. Re-run with --apply.{}",
            candidates.len(),
            format_handles(&candidates)
        );
    }
    let remaining = candidates
        .iter()
        .filter(|handle| !removed.contains(handle))
        .cloned()
        .collect::<Vec<_>>();
    let mut output = format!(
        "{} stopped terminal(s) removed.{}",
        removed.len(),
        format_handles(&removed)
    );
    if !remaining.is_empty() {
        output.push_str(&format!(
            "\n{} candidate(s) not removed.{}",
            remaining.len(),
            format_handles(&remaining)
        ));
    }
    output
}

fn string_field<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or("unknown")
}

fn optional_string_field<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or("none")
}

fn string_array(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect()
}

fn format_handles(handles: &[String]) -> String {
    handles
        .iter()
        .map(|handle| format!("\n- {handle}"))
        .collect::<Vec<_>>()
        .join("")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_list_human_output_includes_terminal_details() {
        let value = json!({
            "items": [
                {"handle": "term-1", "running": true, "agentType": "codex", "agentState": "working", "workspaceId": "ws-1"},
                {"handle": "term-2", "running": false, "agentType": null, "agentState": null, "workspaceId": "ws-2"}
            ]
        });

        let output = format_terminal_list(&value);

        assert!(output.contains("term-1  running  agent=codex  state=working  workspace=ws-1"));
        assert!(output.contains("term-2  stopped  agent=none  state=none  workspace=ws-2"));
        assert_eq!(format_terminal_list(&json!({"items": []})), "0 terminals");
    }

    #[test]
    fn terminal_show_human_output_includes_startup_failure() {
        let output = format_terminal_show(&json!({
            "handle": "term-1",
            "workspaceId": "ws-1",
            "tabId": "tab-1",
            "running": false,
            "agentType": null,
            "agentState": null,
            "startupState": "failed",
            "startupError": "agent exited",
            "dispatch": {"id": "dispatch-1", "status": "startup_failed"}
        }));

        assert!(output.contains("Agent: none"));
        assert!(output.contains("Startup State: failed"));
        assert!(output.contains("Startup Error: agent exited"));
        assert!(output.contains("Dispatch: dispatch-1"));
        assert!(output.contains("Dispatch Status: startup_failed"));
    }

    #[test]
    fn terminal_prune_human_output_distinguishes_dry_run_and_remaining() {
        let dry_run = format_terminal_prune(&json!({
            "dryRun": true,
            "candidates": ["term-1", "term-2"],
            "removed": []
        }));
        assert!(dry_run.contains("2 stopped terminal(s) would be removed"));
        assert!(dry_run.contains("--apply"));
        assert!(dry_run.contains("- term-1"));
        assert!(dry_run.contains("- term-2"));

        let applied = format_terminal_prune(&json!({
            "dryRun": false,
            "candidates": ["term-1", "term-2"],
            "removed": ["term-1"]
        }));
        assert!(applied.contains("1 stopped terminal(s) removed"));
        assert!(applied.contains("1 candidate(s) not removed"));
        assert!(applied.contains("- term-2"));
    }
}
