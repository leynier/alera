//! The workflow tools build commands the CLI parser accepts, keep decisions
//! out of reach, and pass retry keys through.

use clap::Parser;
use serde_json::{json, Map, Value};

use crate::cli::Cli;
use crate::mcp_tools::{ToolAccess, ToolSpec, CLIENT_REQUEST_ID};

fn workflow_tools() -> Vec<ToolSpec> {
    super::tools()
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
fn every_workflow_tool_builds_a_parsable_command() {
    for tool in workflow_tools() {
        let built: Vec<_> = [true, false]
            .into_iter()
            .filter_map(|all| argv(&tool, &samples(&tool, all)))
            .collect();
        assert!(!built.is_empty(), "{} builds nothing", tool.name);
        for argv in built {
            if let Err(error) = Cli::try_parse_from(&argv) {
                panic!("{} builds {argv:?}: {error}", tool.name);
            }
            let reaches_decision = argv.iter().any(|arg| {
                ["approve", "reject", "decide", "review", "sign", "challenge"]
                    .contains(&arg.as_str())
            });
            assert!(!reaches_decision, "{} reaches a human decision", tool.name);
        }
    }
}

#[test]
fn request_keys_are_generated_or_passed_through() {
    let tool = workflow_tools()
        .into_iter()
        .find(|tool| tool.name == "launch_workflow_task")
        .unwrap();
    let mut arguments = samples(&tool, false);
    arguments.as_object_mut().unwrap().remove(CLIENT_REQUEST_ID);
    let generated = argv(&tool, &arguments).unwrap();
    assert_eq!(
        generated
            .iter()
            .filter(|arg| arg.starts_with("--request-id=mcp-"))
            .count(),
        1
    );
    arguments[CLIENT_REQUEST_ID] = json!("request-0001");
    let passed = argv(&tool, &arguments).unwrap();
    assert!(passed.contains(&"--request-id=request-0001".to_owned()));
    assert_eq!(
        passed
            .iter()
            .filter(|arg| arg.starts_with("--request-id"))
            .count(),
        1
    );
}

#[test]
fn cleanup_execution_is_admin_and_recipes_name_their_source() {
    for tool in workflow_tools() {
        let admin = tool.name.ends_with("_workflow_cleanup")
            && !tool.name.starts_with("preview")
            && !tool.name.starts_with("get");
        assert_eq!(tool.access == ToolAccess::Admin, admin, "{}", tool.name);
    }
    let show = workflow_tools()
        .into_iter()
        .find(|tool| tool.name == "show_recipe")
        .unwrap();
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
