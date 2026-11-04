use alera_provider_opencode::opencode_agent_sdk::{ClientConfig, Generation, OpenCodeClient};
use alera_provider_opencode::{settled_models, HttpResponse, MockHttpTransport};
use serde_json::{json, Value};
use std::time::Duration;
use tokio::time::Instant;

fn client(generation: Generation) -> OpenCodeClient<MockHttpTransport> {
    OpenCodeClient::new(
        MockHttpTransport::new(),
        ClientConfig {
            generation,
            ..ClientConfig::default()
        },
    )
}

fn model(id: &str, name: &str) -> Value {
    json!({"providerID":"opencode","id":id,"name":name,"variants":[]})
}

fn list(client: &OpenCodeClient<MockHttpTransport>, models: Vec<Value>) {
    client.transport().push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({ "data": models })).unwrap(),
    ));
}

fn names(models: &[alera_provider_opencode::opencode_agent_sdk::OpenCodeModel]) -> Vec<String> {
    models
        .iter()
        .map(|model| model.name.clone().unwrap_or_default())
        .collect()
}

fn reads(client: &OpenCodeClient<MockHttpTransport>) -> usize {
    client.transport().captured_requests().len()
}

#[tokio::test(start_paused = true)]
async fn a_growing_catalog_is_read_until_it_settles() {
    let mut client = client(Generation::V2);
    list(&client, vec![]);
    list(&client, vec![model("first", "First")]);
    list(
        &client,
        vec![model("first", "First"), model("second", "Second")],
    );
    list(
        &client,
        vec![model("second", "Second"), model("first", "First")],
    );
    let started = Instant::now();
    let models = settled_models(&mut client).await.unwrap();
    assert_eq!(names(&models), ["Second", "First"]);
    assert_eq!(reads(&client), 4);
    assert!(started.elapsed() < Duration::from_secs(1));
}

#[tokio::test(start_paused = true)]
async fn names_provider_labels_and_variants_must_settle_too() {
    let pickle =
        json!({"providerID":"opencode","id":"big-pickle","name":"Big Pickle","variants":[]});
    let renamed =
        json!({"providerID":"opencode","id":"big-pickle","name":"Bigger Pickle","variants":[]});
    let labeled = json!({"providerID":"opencode","id":"big-pickle","name":"Bigger Pickle","providerName":"OpenCode Zen","variants":[]});
    let partial = json!({"providerID":"opencode","id":"big-pickle","name":"Bigger Pickle","providerName":"OpenCode Zen","variants":[{"id":"low"}]});
    let complete = json!({"providerID":"opencode","id":"big-pickle","name":"Bigger Pickle","providerName":"OpenCode Zen","variants":[{"id":"high"},{"id":"medium"}]});
    let reordered = json!({"providerID":"opencode","id":"big-pickle","name":"Bigger Pickle","providerName":"OpenCode Zen","variants":[{"id":"medium"},{"id":"high"}]});
    let mut client = client(Generation::V2);
    for reply in [
        pickle,
        renamed,
        labeled,
        partial,
        complete,
        reordered.clone(),
    ] {
        list(&client, vec![reply]);
    }
    let models = settled_models(&mut client).await.unwrap();
    assert_eq!(reads(&client), 6);
    assert_eq!(models[0].raw, reordered);
}

#[tokio::test(start_paused = true)]
async fn an_unsettled_catalog_keeps_its_latest_nonempty_read_after_five_seconds() {
    let mut client = client(Generation::V2);
    for read in 1..=40 {
        list(&client, vec![model("pickle", &format!("Pickle {read}"))]);
    }
    let started = Instant::now();
    let models = settled_models(&mut client).await.unwrap();
    assert_eq!(started.elapsed(), Duration::from_secs(5));
    let read = reads(&client);
    assert!(read > 1);
    assert_eq!(names(&models), [format!("Pickle {read}")]);
}

#[tokio::test(start_paused = true)]
async fn a_catalog_that_stays_empty_lists_nothing() {
    let mut client = client(Generation::V2);
    for _ in 0..40 {
        list(&client, vec![]);
    }
    assert!(settled_models(&mut client).await.unwrap().is_empty());
}

#[tokio::test(start_paused = true)]
async fn a_failed_confirmation_keeps_the_fresh_read_but_a_failed_first_read_fails() {
    let mut client = client(Generation::V2);
    list(&client, vec![model("pickle", "Pickle")]);
    let models = settled_models(&mut client).await.unwrap();
    assert_eq!(names(&models), ["Pickle"]);
    assert_eq!(reads(&client), 2);
    client
        .transport()
        .push_response(HttpResponse::new(500, Vec::new()));
    assert!(settled_models(&mut client).await.is_err());
}

#[tokio::test(start_paused = true)]
async fn a_legacy_catalog_is_read_once() {
    let mut client = client(Generation::Legacy1);
    client.transport().push_response(HttpResponse::new(
        200,
        serde_json::to_vec(
            &json!({"providers":[{"id":"anthropic","models":{"claude":{"name":"Claude"}}}]}),
        )
        .unwrap(),
    ));
    let models = settled_models(&mut client).await.unwrap();
    assert_eq!(names(&models), ["Claude"]);
    assert_eq!(reads(&client), 1);
}
