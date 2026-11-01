mod support;

use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput};
use serde_json::{json, Value};

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-test".into(),
        ..CodexProviderConfig::default()
    }
}

fn started(item: &str, changes: Value) -> Value {
    json!({
        "method": "item/started",
        "params": {
            "threadId": "native", "turnId": "turn",
            "item": { "id": item, "type": "fileChange", "changes": changes, "status": "inProgress" }
        }
    })
}

fn approval(id: i64, item: &str, extra: Value) -> Value {
    let mut params = json!({ "itemId": item, "threadId": "native", "turnId": "turn" });
    for (key, value) in extra.as_object().unwrap() {
        params[key] = value.clone();
    }
    json!({ "id": id, "method": "item/fileChange/requestApproval", "params": params })
}

async fn next_request(provider: &mut CodexProvider<MockTransport>) -> Value {
    loop {
        let event = support::next_event(provider).await.unwrap().unwrap();
        if event.kind == EventKind::RequestOpened {
            return event.payload;
        }
    }
}

#[tokio::test]
async fn file_change_approvals_list_the_files_their_item_changes() {
    let many = (0..22)
        .map(|index| json!({ "path": format!("src/f{index:02}.rs"), "kind": { "type": "add" } }))
        .collect::<Vec<_>>();
    let mut provider = CodexProvider::new(
        MockTransport::new([
            json!({ "id": 1, "result": { "userAgent": "test" } }),
            json!({ "id": 2, "result": { "thread": { "id": "native" } } }),
            started(
                "patch",
                json!([
                    { "path": "b.rs", "kind": { "type": "update", "move_path": "c.rs" } },
                    { "path": "a.rs", "kind": { "type": "delete" } },
                ]),
            ),
            approval(10, "patch", json!({})),
            approval(11, "unknown", json!({ "grantRoot": "/repo" })),
            approval(
                12,
                "reasoned",
                json!({ "reason": "  Needs write access  " }),
            ),
            started("many", Value::Array(many)),
            approval(13, "many", json!({})),
        ]),
        config(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();

    let first = next_request(&mut provider).await;
    assert_eq!(first["detail"], "delete a.rs\nupdate b.rs -> c.rs");
    // An item that never started borrows no other item's files.
    let unknown = next_request(&mut provider).await;
    assert_eq!(unknown["detail"], "/repo");
    let reason = next_request(&mut provider).await;
    assert_eq!(reason["detail"], "Needs write access");
    let many = next_request(&mut provider).await;
    let detail = many["detail"].as_str().unwrap();
    assert_eq!(detail.lines().count(), 21);
    assert!(detail.starts_with("add src/f00.rs\n"));
    assert!(detail.ends_with("add src/f19.rs\n+2 more"));
}
