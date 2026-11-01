use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    McpServerSpec, McpTransport, NativeForkInput, Provider, ProviderError, SessionStartInput,
};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;

fn initialize_response() -> Value {
    json!({
        "id": 1,
        "result": { "codexHome": "/tmp/codex" }
    })
}

fn thread_response() -> Value {
    json!({ "id": 2, "result": { "thread": { "id": "native-thread" } } })
}

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-mcp".into(),
        ..CodexProviderConfig::default()
    }
}

fn stdio(name: &str) -> McpServerSpec {
    McpServerSpec {
        name: name.into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("/usr/local/bin/mcp-server"),
            args: vec!["--stdio".into()],
            env: BTreeMap::from([(String::from("MCP_TOKEN"), String::from("private"))]),
            cwd: None,
        },
    }
}

fn http(name: &str) -> McpServerSpec {
    McpServerSpec {
        name: name.into(),
        transport: McpTransport::Http {
            url: "http://127.0.0.1:43123/mcp".into(),
            headers: BTreeMap::from([(
                String::from("Authorization"),
                String::from("Bearer private"),
            )]),
        },
    }
}

#[tokio::test]
async fn thread_start_projects_stdio_and_http_mcp_config() {
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers = vec![stdio("local-tools"), http("orchestrator")];
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize_response(), thread_response()]),
        config(),
    );

    provider.start_session(input).await.unwrap();

    let config = &provider.transport().writes()[2]["params"]["config"];
    assert_eq!(
        config["mcp_servers.local-tools"],
        json!({
            "command": "/usr/local/bin/mcp-server",
            "args": ["--stdio"],
            "env": { "MCP_TOKEN": "private" }
        })
    );
    assert_eq!(
        config["mcp_servers.orchestrator"],
        json!({
            "url": "http://127.0.0.1:43123/mcp",
            "http_headers": { "Authorization": "Bearer private" }
        })
    );
    // A whole table would replace the servers Codex was launched with.
    assert!(config.get("mcp_servers").is_none());
}

#[tokio::test]
async fn thread_resume_projects_mcp_config_without_dropping_caller_config() {
    let mut input = SessionStartInput::new("app-thread");
    input.resume_thread_id = Some("native-resume".into());
    input.options.insert(
        "config".into(),
        json!({ "tools.update_plan.enabled": true }),
    );
    input.mcp_servers = vec![http("orchestrator")];
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize_response(), thread_response()]),
        config(),
    );

    provider.start_session(input).await.unwrap();

    let request = &provider.transport().writes()[2];
    assert_eq!(request["method"], "thread/resume");
    assert_eq!(request["params"]["threadId"], "native-resume");
    assert_eq!(
        request["params"]["config"]["tools.update_plan.enabled"],
        true
    );
    assert_eq!(
        request["params"]["config"]["mcp_servers.orchestrator"]["url"],
        "http://127.0.0.1:43123/mcp"
    );
}

#[tokio::test]
async fn caller_mcp_name_collision_is_rejected_before_thread_request() {
    let mut input = SessionStartInput::new("app-thread");
    let mut config_options = Map::new();
    config_options.insert(
        "mcp_servers".into(),
        json!({ "orchestrator": { "url": "http://caller.invalid/mcp" } }),
    );
    input
        .options
        .insert("config".into(), Value::Object(config_options));
    input.mcp_servers = vec![http("orchestrator")];
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize_response(), thread_response()]),
        config(),
    );

    let error = provider.start_session(input).await.unwrap_err();

    assert!(matches!(error, ProviderError::Validation(message) if message.contains("collides")));
    assert!(provider.transport().writes().is_empty());
}

#[tokio::test]
async fn unsupported_stdio_cwd_is_rejected_explicitly() {
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers = vec![McpServerSpec {
        name: "local-tools".into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("mcp-server"),
            args: Vec::new(),
            env: BTreeMap::new(),
            cwd: Some(PathBuf::from("/workspace")),
        },
    }];
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize_response(), thread_response()]),
        config(),
    );

    let error = provider.start_session(input).await.unwrap_err();

    assert!(matches!(error, ProviderError::Unsupported(message) if message.contains("stdio cwd")));
    assert!(provider.transport().writes().is_empty());
}

#[tokio::test]
async fn thread_requests_send_update_plan_and_mcp_startup_grace() {
    for resume in [false, true] {
        let mut input = SessionStartInput::new("app-thread");
        input.resume_thread_id = resume.then(|| "native-resume".into());
        let mut provider = CodexProvider::new(
            MockTransport::new([initialize_response(), thread_response()]),
            config(),
        );

        provider.start_session(input).await.unwrap();

        let config = &provider.transport().writes()[2]["params"]["config"];
        assert_eq!(config["tools.update_plan.enabled"], true);
        assert_eq!(config["mcp_optional_startup_grace_ms"], 10_000);
    }
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize_response(), thread_response()]),
        config(),
    );
    provider
        .fork_session(NativeForkInput {
            source_native_thread_id: "source-native".into(),
            session: SessionStartInput::new("app-fork"),
            boundary: None,
        })
        .await
        .unwrap();
    let request = &provider.transport().writes()[2];
    assert_eq!(request["method"], "thread/fork");
    assert_eq!(
        request["params"]["config"]["tools.update_plan.enabled"],
        true
    );
    assert_eq!(
        request["params"]["config"]["mcp_optional_startup_grace_ms"],
        10_000
    );
}

#[tokio::test]
async fn caller_thread_config_overrides_defaults() {
    for (caller, key, expected) in [
        (
            json!({ "tools.update_plan.enabled": false, "mcp_optional_startup_grace_ms": 2000 }),
            "tools.update_plan.enabled",
            json!(false),
        ),
        (
            json!({ "tools.update_plan": { "enabled": false } }),
            "tools.update_plan",
            json!({ "enabled": false }),
        ),
        (
            json!({ "tools": { "update_plan": { "enabled": false } } }),
            "tools",
            json!({ "update_plan": { "enabled": false } }),
        ),
        (
            json!({ "tools": { "web_search": true } }),
            "tools",
            json!({ "web_search": true, "update_plan": { "enabled": true } }),
        ),
    ] {
        let mut input = SessionStartInput::new("app-thread");
        input.options.insert("config".into(), caller.clone());
        let mut provider = CodexProvider::new(
            MockTransport::new([initialize_response(), thread_response()]),
            config(),
        );

        provider.start_session(input).await.unwrap();

        let config = &provider.transport().writes()[2]["params"]["config"];
        assert_eq!(config[key], expected, "{caller}");
        assert_eq!(
            config["mcp_optional_startup_grace_ms"],
            caller
                .get("mcp_optional_startup_grace_ms")
                .cloned()
                .unwrap_or(json!(10_000))
        );
        if key != "tools.update_plan.enabled" {
            assert!(
                config.get("tools.update_plan.enabled").is_none(),
                "{caller}"
            );
        }
    }
}

#[tokio::test]
async fn dotted_caller_key_collision_is_rejected() {
    for key in ["mcp_servers.orchestrator", "mcp_servers.orchestrator.url"] {
        let mut input = SessionStartInput::new("app-thread");
        input
            .options
            .insert("config".into(), json!({ key: "http://caller.invalid/mcp" }));
        input.mcp_servers = vec![http("orchestrator")];
        let mut provider = CodexProvider::new(
            MockTransport::new([initialize_response(), thread_response()]),
            config(),
        );

        let error = provider.start_session(input).await.unwrap_err();

        assert!(
            matches!(&error, ProviderError::Validation(message) if message.contains("collides")),
            "{key}: {error}"
        );
        assert!(provider.transport().writes().is_empty());
    }
}

#[tokio::test]
async fn caller_server_with_a_longer_name_is_not_a_collision() {
    let mut input = SessionStartInput::new("app-thread");
    input.options.insert(
        "config".into(),
        json!({ "mcp_servers.orchestrator-2.url": "http://caller.invalid/mcp" }),
    );
    input.mcp_servers = vec![http("orchestrator")];
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize_response(), thread_response()]),
        config(),
    );

    provider.start_session(input).await.unwrap();

    let config = &provider.transport().writes()[2]["params"]["config"];
    assert_eq!(
        config["mcp_servers.orchestrator-2.url"],
        "http://caller.invalid/mcp"
    );
    assert_eq!(
        config["mcp_servers.orchestrator"]["url"],
        "http://127.0.0.1:43123/mcp"
    );
}

#[tokio::test]
async fn caller_mcp_table_keeps_nested_projection() {
    let mut input = SessionStartInput::new("app-thread");
    input.options.insert(
        "config".into(),
        json!({ "mcp_servers": { "own": { "url": "http://caller.invalid/mcp" } } }),
    );
    input.mcp_servers = vec![http("orchestrator")];
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize_response(), thread_response()]),
        config(),
    );

    provider.start_session(input).await.unwrap();

    let config = &provider.transport().writes()[2]["params"]["config"];
    assert_eq!(
        config["mcp_servers"]["own"]["url"],
        "http://caller.invalid/mcp"
    );
    assert_eq!(
        config["mcp_servers"]["orchestrator"]["url"],
        "http://127.0.0.1:43123/mcp"
    );
    assert!(config.get("mcp_servers.orchestrator").is_none());
}

#[tokio::test]
async fn dotted_server_name_uses_nested_form() {
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers = vec![http("a.b"), stdio("local-tools")];
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize_response(), thread_response()]),
        config(),
    );

    provider.start_session(input).await.unwrap();

    let config = &provider.transport().writes()[2]["params"]["config"];
    assert_eq!(
        config["mcp_servers"]["a.b"]["url"],
        "http://127.0.0.1:43123/mcp"
    );
    assert_eq!(
        config["mcp_servers"]["local-tools"]["command"],
        "/usr/local/bin/mcp-server"
    );
    assert!(config.get("mcp_servers.a.b").is_none());
    assert!(config.get("mcp_servers.local-tools").is_none());
}
