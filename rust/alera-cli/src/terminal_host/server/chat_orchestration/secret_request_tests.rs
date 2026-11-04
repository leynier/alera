use std::path::Path;

use serde_json::{json, Value};

use crate::terminal_host::diagnostics::redaction::redact;

use super::authorization::OrchestrationCaller;
use super::delegation_tests::delegate_payload;
use super::test_support::{error_code, human, TestHarness};

/// Synthetic, and long enough for the log redaction to register it.
const VALUE: &str = "synthetic-test-value-0042";

async fn ask(harness: &TestHarness, caller: &OrchestrationCaller, delivery: &str) -> Value {
    harness
        .service
        .handle(
            "requestSecret",
            &json!({"label": "Deploy token", "reason": "To deploy.", "delivery": delivery}),
            caller,
        )
        .await
        .unwrap()
}

async fn provide(harness: &TestHarness, chat: &str, request: &str, action: Value) -> Value {
    let mut payload = json!({"chatId": chat, "runtimeRequestId": request});
    for (key, value) in action.as_object().unwrap() {
        payload[key] = value.clone();
    }
    harness
        .service
        .provide_secret(&payload, human("desktop").ctx)
        .await
        .unwrap()
}

/// Whether any stored file outside the delivered secret files holds `VALUE`.
fn leaked_into(directory: &Path) -> bool {
    let mut stack = vec![directory.to_owned()];
    while let Some(path) = stack.pop() {
        if path.ends_with("files") {
            continue;
        }
        if path.is_dir() {
            stack.extend(
                std::fs::read_dir(&path)
                    .unwrap()
                    .flatten()
                    .map(|e| e.path()),
            );
        } else if let Ok(bytes) = std::fs::read(&path) {
            if bytes
                .windows(VALUE.len())
                .any(|window| window == VALUE.as_bytes())
            {
                return true;
            }
        }
    }
    false
}

#[tokio::test]
async fn a_ref_secret_reaches_the_agent_once_and_nowhere_else() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&chat, "live", "Deploy it.").await;
    let agent = harness.agent(&chat).await;

    let pending = ask(&harness, &agent, "ref").await;
    assert_eq!(pending["status"], "pending");
    let request = pending["requestId"].as_str().unwrap().to_owned();
    assert!(pending["next"].as_str().unwrap().contains("requestId"));
    let snapshot = harness.runtime.snapshot(&chat).await.unwrap();
    let card = &snapshot["pendingRequests"][0];
    assert_eq!(card["kind"], "secret_input");
    assert_eq!(card["masked"], true);
    assert_eq!(snapshot["session"]["status"], "waiting");

    assert_eq!(
        provide(&harness, &chat, &request, json!({"value": VALUE})).await["status"],
        "saved"
    );
    let saved = harness
        .service
        .handle(
            "requestSecret",
            &json!({"secretRequestId": request}),
            &agent,
        )
        .await
        .unwrap();
    assert_eq!(saved["status"], "saved");
    let secret_ref = saved["secretRef"].as_str().unwrap().to_owned();
    assert!(secret_ref.starts_with("secret-ref:"));
    assert!(saved.get("value").is_none());

    let snapshot = harness.runtime.snapshot(&chat).await.unwrap();
    assert!(snapshot["pendingRequests"].as_array().unwrap().is_empty());
    assert!(!snapshot.to_string().contains(VALUE));
    assert!(!redact(&format!("token {VALUE} logged")).contains(VALUE));

    let read = harness
        .service
        .handle("readSecret", &json!({"secretRef": secret_ref}), &agent)
        .await
        .unwrap();
    assert!(read["value"].as_str() == Some(VALUE));
    let again = harness
        .service
        .handle("readSecret", &json!({"secretRef": secret_ref}), &agent)
        .await
        .unwrap_err();
    assert_eq!(error_code(&again), "secretRefUnavailable");
    // A restart flushes the chat's history and snapshot to the store.
    let harness = harness.restart().await;
    assert!(!leaked_into(harness.directory.path()));
    harness.finish().await;
}

#[tokio::test]
async fn a_file_secret_is_owner_only_and_a_decline_settles_the_card() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&chat, "live", "Deploy it.").await;
    let agent = harness.agent(&chat).await;

    let request = ask(&harness, &agent, "file").await["requestId"]
        .as_str()
        .unwrap()
        .to_owned();
    provide(&harness, &chat, &request, json!({"value": VALUE})).await;
    let saved = harness
        .service
        .handle(
            "requestSecret",
            &json!({"secretRequestId": request}),
            &agent,
        )
        .await
        .unwrap();
    let file = saved["file"].as_str().unwrap();
    assert!(std::fs::read_to_string(file).unwrap() == VALUE);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = |path: &Path| std::fs::metadata(path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(Path::new(file)), 0o600);
        assert_eq!(mode(Path::new(file).parent().unwrap()), 0o700);
    }

    let declined = ask(&harness, &agent, "file").await["requestId"]
        .as_str()
        .unwrap()
        .to_owned();
    provide(&harness, &chat, &declined, json!({"action": "decline"})).await;
    let answer = harness
        .service
        .handle(
            "requestSecret",
            &json!({"secretRequestId": declined}),
            &agent,
        )
        .await
        .unwrap();
    assert_eq!(answer["status"], "declined");
    let late = harness
        .service
        .provide_secret(
            &json!({"chatId": chat, "runtimeRequestId": declined, "value": VALUE}),
            human("desktop").ctx,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&late), "request_resolved");
    harness.finish().await;
}

#[tokio::test]
async fn only_a_person_answers_a_child_secret_card() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&parent, "live", "Delegate.").await;
    let parent_agent = harness.agent(&parent).await;
    let response = harness
        .service
        .handle(
            "delegate",
            &delegate_payload(
                "secret-child",
                json!({"workspace": {"workspaceId": "ws-a"}}),
            ),
            &parent_agent,
        )
        .await
        .unwrap();
    let child = response["childChatId"].as_str().unwrap().to_owned();
    let child_agent = harness.agent(&child).await;
    let request = ask(&harness, &child_agent, "file").await["requestId"]
        .as_str()
        .unwrap()
        .to_owned();

    for caller in [&parent_agent, &human("desktop")] {
        let refused = harness
            .service
            .handle(
                "respond",
                &json!({"requestId": format!("answer-{}", caller.bound.is_some()),
                    "chatId": child, "runtimeRequestId": request,
                    "response": {"type": "userInput", "answers": {"value": [VALUE]}}}),
                caller,
            )
            .await
            .unwrap_err();
        assert_eq!(error_code(&refused), "unsupported");
    }
    let refused = harness
        .service
        .handle(
            "requestSecret",
            &json!({"secretRequestId": request}),
            &parent_agent,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&refused), "request_resolved");
    let snapshot = harness.runtime.snapshot(&child).await.unwrap();
    assert_eq!(snapshot["pendingRequests"].as_array().unwrap().len(), 1);
    harness.finish().await;
}
