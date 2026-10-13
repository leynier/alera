use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    McpServerSpec, McpTransport, Provider, ProviderError, SessionStartInput,
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

    let params = &provider.transport().writes()[2]["params"];
    assert_eq!(
        params["config"]["mcp_servers"]["local-tools"],
        json!({
            "command": "/usr/local/bin/mcp-server",
            "args": ["--stdio"],
            "env": { "MCP_TOKEN": "private" }
        })
    );
    assert_eq!(
        params["config"]["mcp_servers"]["orchestrator"],
        json!({
            "url": "http://127.0.0.1:43123/mcp",
            "http_headers": { "Authorization": "Bearer private" }
        })
    );
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
        request["params"]["config"]["mcp_servers"]["orchestrator"]["url"],
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
    assert_eq!(provider.transport().writes().len(), 2);
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
    assert_eq!(provider.transport().writes().len(), 2);
}
