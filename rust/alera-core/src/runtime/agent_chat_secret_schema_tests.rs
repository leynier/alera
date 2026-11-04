use serde_json::{json, Value};

use super::agent_chat_test_support::*;

fn request(schema: Value) -> Value {
    json!({
        "requestId": "form", "kind": "mcp_elicitation_approval",
        "elicitation": {"mode": "form", "schema": schema},
    })
}

#[tokio::test]
async fn elicitation_property_and_definition_names_are_schema_metadata() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let schema = json!({
        "type": "object", "required": ["password", "apiKey"],
        "properties": {
            "password": {"type": "string", "format": "password"},
            "apiKey": {"type": "string", "description": "API key input"},
            "bearer_token": {"$ref": "#/$defs/credentials"},
            "nested": {"type": "object", "properties": {"client_secret": {"type": "string"}}},
        },
        "$defs": {"credentials": {"type": "string"}},
        "definitions": {"password": {"type": "string", "format": "password"}},
    });
    let requests = json!([request(schema)]);
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["pendingRequests"] = requests.clone();
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"requests": requests}),
            None,
        )
        .await
        .unwrap();
    let view = store.agent_chat(&chat_id).await.unwrap().unwrap().snapshot;
    assert_eq!(view["pendingRequests"], requests);
    assert_eq!(
        store
            .agent_chat_events(&chat_id, 0, 1)
            .await
            .unwrap()
            .events[0]
            .delta["requests"],
        requests
    );
}

#[tokio::test]
async fn elicitation_schema_exceptions_do_not_accept_credential_values_or_defaults() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    for schema in [
        json!({"type": "object", "properties": {"password": "credential-value"}}),
        json!({"type": "object", "properties": {"password": {"value": "credential-value"}}}),
        json!({"type": "object", "properties": {"password": {"type": "string", "default": "credential-value"}}}),
        json!({"type": "object", "properties": {"apiKey": {"type": "string", "enum": ["credential-value"]}}}),
        json!({"type": "object", "properties": {"password": {"anyOf": [{"type": "string", "default": "credential-value"}]}}}),
        json!({"type": "object", "default": {"password": "credential-value"}}),
        json!({"type": "object", "properties": {"field": {"type": "object", "default": {"api_key": "credential-value"}}}}),
        json!({"definitions": {"credentials": {"type": "string", "const": "credential-value"}}}),
        json!({"password": "credential-value"}),
    ] {
        let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
        next["pendingRequests"] = json!([request(schema)]);
        assert!(store
            .commit_agent_chat(
                &chat_id,
                cursor,
                &next,
                &json!({"requests": next["pendingRequests"]}),
                None
            )
            .await
            .is_err());
    }
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 0);
}

#[tokio::test]
async fn unrelated_schema_objects_and_host_metadata_keep_strict_secret_checks() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    for fields in [
        json!({"schema": {"properties": {"password": {"type": "string"}}}}),
        json!({"password": "credential-value"}),
        json!({"env": {"api_key": "credential-value"}}),
        json!({"mcpServers": [{"command": "x"}]}),
    ] {
        let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
        next["hostFields"] = fields.clone();
        assert!(store
            .commit_agent_chat(
                &chat_id,
                cursor,
                &next,
                &json!({"hostFields": fields}),
                None
            )
            .await
            .is_err());
    }
    for metadata in [
        json!({"schema": {"properties": {"password": {"type": "string"}}}}),
        json!({"pendingRequests": [request(json!({"properties": {"password": {"type": "string"}}}))]}),
        json!({"env": {"clientSecret": "credential-value"}}),
        json!({"mcpServers": []}),
    ] {
        assert!(store
            .set_agent_chat_metadata(&chat_id, Some(&metadata))
            .await
            .is_err());
    }
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 0);
}
