//! The run and recipe tools build commands the CLI parser accepts, keep
//! person-owned decisions behind the admin class, and pass retry keys through.

use clap::Parser;
use serde_json::{json, Map, Value};

use crate::cli::Cli;
use crate::mcp_tools::{find_tool, ToolAccess, ToolSpec, CLIENT_REQUEST_ID};

fn run_tools() -> Vec<ToolSpec> {
    let mut tools = super::tools();
    tools.extend(super::super::runs_manage::tools());
    tools.extend(super::super::recipes::tools());
    tools
}

fn samples(tool: &ToolSpec, all: bool) -> Value {
    let schema = tool.schema();
    let required = schema["required"].as_array().cloned().unwrap_or_default();
    let mut arguments = Map::new();
    for (name, property) in schema["properties"].as_object().into_iter().flatten() {
        if !all && !required.iter().any(|value| value == name) {
            continue;
        }
        let value = match property["type"].as_str() {
            Some("integer") => json!(property["minimum"].as_u64().unwrap_or(1).max(1)),
            Some("boolean") => json!(true),
            Some("array") => json!(["item"]),
            _ => match property["enum"].as_array() {
                Some(values) => values[0].clone(),
                None if name == CLIENT_REQUEST_ID => json!("request-0001"),
                None => json!("sample"),
            },
        };
        arguments.insert(name.clone(), value);
    }
    Value::Object(arguments)
}

fn argv(tool: &ToolSpec, arguments: &Value) -> Option<Vec<String>> {
    let invocation = tool.invocation(arguments).ok()?;
    let mut argv = vec!["alera".into(), invocation.group.into(), "--json".into()];
    argv.extend(invocation.args);
    Some(argv)
}

#[test]
fn every_run_tool_builds_a_parsable_command() {
    for tool in run_tools() {
        let built: Vec<_> = [true, false]
            .into_iter()
            .filter_map(|all| argv(&tool, &samples(&tool, all)))
            .collect();
        assert!(!built.is_empty(), "{} builds nothing", tool.name);
        for argv in built {
            if let Err(error) = Cli::try_parse_from(&argv) {
                panic!("{} builds {argv:?}: {error}", tool.name);
            }
        }
    }
}

#[test]
fn only_admin_tools_resolve_gates_or_remove_resources() {
    let decisions = [
        "resolve_run_gate",
        "apply_run_cleanup",
        "retry_run_cleanup",
        "abandon_run_cleanup",
    ];
    for tool in run_tools() {
        let built = argv(&tool, &samples(&tool, true)).unwrap_or_default();
        let decides = built.windows(2).any(|pair| {
            pair == ["gate", "resolve"]
                || pair == ["cleanup", "apply"]
                || pair == ["cleanup", "retry"]
                || pair == ["cleanup", "abandon"]
        });
        assert_eq!(decides, decisions.contains(&tool.name), "{}", tool.name);
        if decides {
            assert_eq!(tool.access, ToolAccess::Admin, "{}", tool.name);
        }
    }
}

#[test]
fn create_run_resolves_profiles_and_keeps_retry_keys() {
    let create = find_tool("create_run").unwrap();
    let built = argv(
        &create,
        &json!({
            "workspaceId": "ws",
            "objective": "Ship it",
            "coordinatorProfile": "prof_1",
            "recipe": "builtIn:feature-delivery",
            CLIENT_REQUEST_ID: "request-0001",
        }),
    )
    .unwrap();
    assert!(built.contains(&"--profile-id=prof_1".to_string()));
    assert!(built.contains(&"--template=builtIn:feature-delivery".to_string()));
    assert!(built.contains(&"--request-id=request-0001".to_string()));
}

#[test]
fn cleanup_previews_select_branches_among_their_resources() {
    let preview = find_tool("preview_run_cleanup").unwrap();
    let built = argv(
        &preview,
        &json!({"runId": "r", "workspaceIds": ["a", "b"], "deleteBranchFor": ["b"]}),
    )
    .unwrap();
    assert!(built.contains(&"--resource=a".to_string()));
    assert!(built.contains(&"--delete-branch=b".to_string()));
    assert!(preview
        .invocation(&json!({"runId": "r", "workspaceIds": ["a"], "deleteBranchFor": ["c"]}))
        .is_err());
}

#[test]
fn recipes_name_their_source() {
    let show = find_tool("show_recipe").unwrap();
    let project = argv(
        &show,
        &json!({"origin": "project", "id": "release.yaml", "workspaceId": "ws"}),
    )
    .unwrap();
    assert!(project
        .iter()
        .any(|arg| arg.contains(r#""path":"release.yaml""#)));
    assert!(show
        .invocation(&json!({"origin": "project", "id": "x"}))
        .is_err());
}
