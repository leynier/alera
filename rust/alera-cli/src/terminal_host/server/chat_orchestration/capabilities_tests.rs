use serde_json::{json, Value};

use super::test_support::{human, TestHarness};

fn provider<'a>(capabilities: &'a Value, id: &str) -> &'a Value {
    capabilities["providers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|provider| provider["providerInstanceId"] == id)
        .unwrap_or_else(|| panic!("{id} is listed"))
}

fn model_count(provider: &Value) -> usize {
    provider["models"].as_array().unwrap().len()
}

#[tokio::test]
async fn an_agent_sees_a_short_model_list_and_its_own_selection() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&chat, "go", "Pick a model.").await;
    let agent = harness.agent(&chat).await;
    let capabilities = harness
        .service
        .handle("capabilities", &json!({}), &agent)
        .await
        .unwrap();
    let opencode = provider(&capabilities, "opencode");
    assert_eq!(model_count(opencode), 8);
    assert_eq!(opencode["omittedModels"], 4);
    assert_eq!(model_count(provider(&capabilities, "codex")), 1);
    assert_eq!(capabilities["caller"]["chatId"], chat);
    assert_eq!(capabilities["caller"]["providerInstanceId"], "codex");
    assert!(capabilities["caller"].get("model").is_some());

    let searched = harness
        .service
        .handle("capabilities", &json!({"search": "model 1"}), &agent)
        .await
        .unwrap();
    let found: Vec<&str> = provider(&searched, "opencode")["models"]
        .as_array()
        .unwrap()
        .iter()
        .map(|model| model["id"].as_str().unwrap())
        .collect();
    assert_eq!(
        found,
        ["backend/model-01", "backend/model-10", "backend/model-11"]
    );
    harness.finish().await;
}

#[tokio::test]
async fn a_person_keeps_the_full_catalog_unless_they_search() {
    let harness = TestHarness::new().await;
    let person = human("desktop");
    let full = harness
        .service
        .handle("capabilities", &json!({}), &person)
        .await
        .unwrap();
    let opencode = provider(&full, "opencode");
    assert_eq!(model_count(opencode), 12);
    assert!(opencode.get("omittedModels").is_none());
    let searched = harness
        .service
        .handle("capabilities", &json!({"search": "model"}), &person)
        .await
        .unwrap();
    assert_eq!(model_count(provider(&searched, "opencode")), 8);
    assert!(harness
        .service
        .handle("capabilities", &json!({"search": "x".repeat(201)}), &person)
        .await
        .is_err());
    harness.finish().await;
}
