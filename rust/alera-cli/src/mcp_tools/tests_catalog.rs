//! Catalog-wide guarantees: every tool builds a command the real CLI parser
//! accepts, nothing reaches an excluded command, and the access classes match
//! the decisions in `docs/mcp-parity-implementation-plan.md`.

use clap::Parser;
use serde_json::{json, Map, Value};

use super::{catalog, ToolAccess, ToolSpec, CLIENT_REQUEST_ID};
use crate::cli::Cli;

/// Commands no MCP tool may run: the security control plane, device pairing,
/// SSH credentials and sidecar installs, the runtime's own lifecycle, and the
/// decisions that only a person makes in the Alera app.
const EXCLUDED: &[(&str, Option<&str>)] = &[
    ("account", None),
    ("mcp", None),
    ("mobile", None),
    ("runtime-host", None),
    ("terminal-host", None),
    ("runtime-proxy", None),
    ("ssh-target", Some("add")),
    ("ssh-target", Some("remove")),
    ("ssh-target", Some("bootstrap")),
    ("ssh-target", Some("bootstrap-plan")),
    ("ssh-target", Some("bootstrap-cancel")),
    ("ssh-target", Some("link")),
    ("runtime", Some("start")),
    ("runtime", Some("stop")),
    ("runtime", Some("clear")),
    ("runtime", Some("rename")),
    ("orchestration", Some("gate-resolve")),
    ("orchestration", Some("run-policy-approve")),
    ("orchestration", Some("run-policy-reject")),
];

/// Tools that need the `admin` class (F1 option B and F2).
const ADMIN_TOOLS: &[&str] = &[
    "update_runtime_settings",
    "set_agent_integrations",
    "consume_codex_reset_credit",
    "list_webhooks",
    "create_webhook",
    "delete_webhook",
    "test_webhook",
    "create_agent_profile",
    "update_agent_profile",
    "remove_agent_profile",
    "reorder_agent_profiles",
    "set_default_agent_profile",
    "reset_orchestration",
    "recover_task",
    "transfer_coordinator",
    "prune_terminals",
    "apply_workflow_cleanup",
    "retry_workflow_cleanup",
    "abandon_workflow_cleanup",
    "register_workspace_record",
    "unregister_workspace_record",
    "purge_inbox",
];

/// Tools the user decided stay below `admin` (F1).
const FULL_TOOLS: &[&str] = &[
    "remove_workspace",
    "remove_project",
    "merge_pull_request",
    "merge_pull_request_stack",
    "purge_automations",
    "create_automation",
    "update_automation",
];

/// Properties whose CLI flag parses a specific format.
const FORMATTED_SAMPLES: &[(&str, &str)] = &[("expiresIn", "30m"), ("numbers", "12,13")];

/// Arguments for a tool: every property (`all`) or only the required ones,
/// each filled with a valid placeholder.
fn sample_arguments(tool: &ToolSpec, all: bool) -> Value {
    let schema = tool.schema();
    let required = schema["required"].as_array().cloned().unwrap_or_default();
    let mut arguments = Map::new();
    for (name, property) in schema["properties"].as_object().into_iter().flatten() {
        if !all && !required.iter().any(|value| value == name) {
            continue;
        }
        let value = match property["type"].as_str() {
            Some("integer") => json!(property["minimum"].as_u64().unwrap_or(1).max(1)),
            // Some values require their flag, such as branch with worktree.
            Some("boolean") => json!(true),
            Some("array") => json!([property["items"]["enum"][0].as_str().unwrap_or("item")]),
            Some("object") => json!({}),
            _ if name == CLIENT_REQUEST_ID => json!("request-0001"),
            _ => match FORMATTED_SAMPLES.iter().find(|(key, _)| key == name) {
                Some((_, sample)) => json!(sample),
                None => match property["enum"].as_array() {
                    Some(values) => values[0].clone(),
                    None => json!("sample"),
                },
            },
        };
        arguments.insert(name.clone(), value);
    }
    Value::Object(arguments)
}

fn cli_argv(invocation: super::Invocation) -> Vec<String> {
    let mut argv = vec![
        "alera".to_owned(),
        invocation.group.to_owned(),
        "--runtime-dir=/nonexistent".to_owned(),
        "--json".to_owned(),
    ];
    argv.extend(invocation.args);
    argv
}

/// Sample argument sets for a tool: every property, only the required ones,
/// and every property but one, which covers properties that exclude each
/// other, such as a path or a clone URL.
fn sample_variants(tool: &ToolSpec) -> Vec<Value> {
    let all = sample_arguments(tool, true);
    let required = tool.schema()["required"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    let mut variants = vec![all.clone(), sample_arguments(tool, false)];
    for key in all.as_object().into_iter().flatten().map(|(key, _)| key) {
        if required.iter().any(|value| value == key) {
            continue;
        }
        let mut variant = all.clone();
        variant.as_object_mut().unwrap().remove(key);
        variants.push(variant);
    }
    variants
}

/// A tool may refuse a combination of arguments itself, but any command it
/// does build must parse: the CLI never sees an argument list it rejects.
#[test]
fn every_tool_builds_a_command_the_cli_accepts() {
    for tool in catalog() {
        let mut built = 0;
        for arguments in sample_variants(&tool) {
            let Ok(invocation) = tool.invocation(&arguments) else {
                continue;
            };
            built += 1;
            let argv = cli_argv(invocation);
            if let Err(error) = Cli::try_parse_from(&argv) {
                panic!(
                    "{} builds {:?}, which the CLI rejects: {error}",
                    tool.name, argv
                );
            }
        }
        assert!(
            built > 0,
            "{} builds no command from its samples",
            tool.name
        );
    }
}

#[test]
fn no_tool_reaches_an_excluded_command() {
    for tool in catalog() {
        for arguments in sample_variants(&tool) {
            let Ok(invocation) = tool.invocation(&arguments) else {
                continue;
            };
            // The subcommand path is every word before the first flag, so a
            // nested action (`ssh-target link`) is caught wherever it sits.
            let path: Vec<&str> = invocation
                .args
                .iter()
                .map(String::as_str)
                .take_while(|word| !word.starts_with('-'))
                .collect();
            for (group, excluded_action) in EXCLUDED {
                let hit = invocation.group == *group
                    && excluded_action.is_none_or(|excluded| path.contains(&excluded));
                assert!(
                    !hit,
                    "{} runs the excluded command {group} {path:?}",
                    tool.name
                );
            }
        }
    }
}

#[test]
fn access_classes_follow_the_plan() {
    for tool in catalog() {
        if ADMIN_TOOLS.contains(&tool.name) {
            assert_eq!(
                tool.access,
                ToolAccess::Admin,
                "{} must be admin",
                tool.name
            );
        } else {
            assert_ne!(
                tool.access,
                ToolAccess::Admin,
                "{} must not be admin",
                tool.name
            );
        }
        if FULL_TOOLS.contains(&tool.name) {
            assert_eq!(
                tool.access,
                ToolAccess::Execute,
                "{} must be full",
                tool.name
            );
        }
    }
}

#[test]
fn client_request_ids_reach_the_cli() {
    for tool in catalog()
        .into_iter()
        .filter(|tool| tool.client_request_flag.is_some())
    {
        let invocation = sample_variants(&tool)
            .into_iter()
            .find_map(|mut arguments| {
                arguments[CLIENT_REQUEST_ID] = json!("request-0001");
                tool.invocation(&arguments).ok()
            })
            .unwrap();
        let flag = tool.client_request_flag.unwrap();
        assert!(
            invocation.args.contains(&format!("{flag}=request-0001")),
            "{} drops clientRequestId",
            tool.name
        );
    }
}

#[test]
fn reading_tools_are_marked_idempotent() {
    for tool in catalog()
        .into_iter()
        .filter(|tool| tool.access == ToolAccess::Read)
    {
        assert_eq!(
            tool.to_json()["annotations"]["idempotentHint"],
            true,
            "{}",
            tool.name
        );
    }
}
