use opencode_agent_sdk::{
    normalized_mcp_server_name, ClientConfig, Generation, HttpResponse, McpServerConfig,
    MockHttpTransport, OpenCodeClient,
};
use serde_json::json;
use std::collections::BTreeMap;

#[test]
fn native_namespace_preserves_hyphens_and_uses_javascript_code_units() {
    assert_eq!(normalized_mcp_server_name("foo.bar"), "foo_bar");
    assert_eq!(normalized_mcp_server_name("foo_bar"), "foo_bar");
    assert_eq!(normalized_mcp_server_name("foo-bar"), "foo-bar");
    assert_eq!(normalized_mcp_server_name("Foo/é😀"), "Foo____");
}

#[tokio::test]
async fn legacy_reads_all_native_status_map_names_in_directory_scope() {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({
            "foo.bar":{"status":"connected"},
            "offline":{"status":"disabled"},
            "failed":{"status":"failed","error":"connection failed"}
        }))
        .unwrap(),
    ));
    let mut client = OpenCodeClient::new(
        transport,
        ClientConfig {
            generation: Generation::Legacy1,
            directory: Some("/project".into()),
            ..ClientConfig::default()
        },
    );
    assert_eq!(
        client.mcp_server_names().await.unwrap(),
        ["failed", "foo.bar", "offline"]
    );
    let requests = client.transport().captured_requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].method, "GET");
    assert_eq!(
        requests[0].path,
        "http://127.0.0.1:4096/mcp?directory=%2Fproject"
    );
}

#[tokio::test]
async fn v2_reads_native_location_envelope_and_preserves_disabled_names() {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(200, serde_json::to_vec(&json!({
        "location":{"directory":"/project"},
        "data":[
            {"name":"foo.bar","status":{"status":"connected"}},
            {"name":"offline","status":{"status":"disabled"}},
            {"name":"auth","status":{"status":"needs_auth","error":"login required"},"integrationID":"integration-1"}
        ]
    })).unwrap()));
    let mut client = OpenCodeClient::new(
        transport,
        ClientConfig {
            directory: Some("/project".into()),
            ..ClientConfig::default()
        },
    );
    assert_eq!(
        client.mcp_server_names().await.unwrap(),
        ["foo.bar", "offline", "auth"]
    );
    let requests = client.transport().captured_requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].method, "GET");
    assert_eq!(
        requests[0].path,
        "http://127.0.0.1:4096/api/mcp?directory=%2Fproject"
    );
}

#[tokio::test]
async fn mcp_list_rejects_wrong_native_shapes_instead_of_assuming_empty() {
    for (generation, bodies) in [
        (
            Generation::Legacy1,
            vec![
                json!([]),
                json!({"error":"failure"}),
                json!({"docs":{"status":null}}),
            ],
        ),
        (
            Generation::V2,
            vec![
                json!([]),
                json!({"data":[]}),
                json!({"location":{"directory":"/project"},"data":[{"status":{"status":"connected"}}]}),
                json!({"location":{"directory":"/project"},"data":[{"name":"docs","status":"connected"}]}),
            ],
        ),
    ] {
        for body in bodies {
            let transport = MockHttpTransport::new();
            transport.push_response(HttpResponse::new(200, serde_json::to_vec(&body).unwrap()));
            let mut client = OpenCodeClient::new(
                transport,
                ClientConfig {
                    generation,
                    ..ClientConfig::default()
                },
            );
            assert!(client.mcp_server_names().await.is_err());
        }
    }
}

#[test]
fn mcp_debug_omits_arguments_environment_values_and_entire_remote_url() {
    let local = McpServerConfig::Local {
        command: vec!["mcp-tools".into(), "argument-secret".into()],
        cwd: Some("/project".into()),
        environment: BTreeMap::from([
            ("Z_TOKEN".into(), "env-secret".into()),
            ("A_TOKEN".into(), "other-secret".into()),
        ]),
    };
    assert_eq!(
        format!("{local:?}"),
        "Local { command: Some(\"mcp-tools\"), env_keys: [\"A_TOKEN\", \"Z_TOKEN\"], .. }"
    );
    assert_eq!(local, local.clone());
    let remote = McpServerConfig::Remote {
        url: "https://user:password@mcp.example.test/private?token=query-secret#fragment-secret"
            .into(),
        headers: BTreeMap::from([("Authorization".into(), "header-secret".into())]),
    };
    assert_eq!(
        format!("{remote:?}"),
        "Remote { header_keys: [\"Authorization\"], .. }"
    );
    assert_eq!(remote, remote.clone());
}
