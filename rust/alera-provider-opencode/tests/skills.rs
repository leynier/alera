use alera_provider_opencode::opencode_agent_sdk::{ClientConfig, Generation, OpenCodeClient};
use alera_provider_opencode::{
    discover_skills_with_client, HttpResponse, MockHttpTransport, OpenCodeGeneration,
    OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{Provider, SessionStartInput, TurnInput};
use serde_json::{json, Value};

fn response(value: Value) -> HttpResponse {
    HttpResponse::new(200, serde_json::to_vec(&value).unwrap())
}

fn client(generation: Generation) -> OpenCodeClient<MockHttpTransport> {
    OpenCodeClient::new(
        MockHttpTransport::new(),
        ClientConfig {
            directory: Some("/work".into()),
            generation,
            ..ClientConfig::default()
        },
    )
}

/// What a 2.x server answers for `/api/skill` in a workspace with one
/// project skill (T3 Code's recorded probe response).
fn v2_skills() -> Value {
    json!({"location":{"directory":"/work"},"data":[
        {"id":"opencode","name":"OpenCode","description":"Use this skill for any question about OpenCode itself.","path":"/builtin/opencode.md","content":"# OpenCode"},
        {"id":"report","name":"Report","description":"Use when the user wants to report an opencode issue or bug.","path":"/builtin/report.md","content":"<!-- Built-in skill. -->"},
        {"id":"plum","name":"plum","description":"plum skill","path":"/work/.opencode/skills/plum/SKILL.md","content":"Say PLUM."}
    ]})
}

fn v2_commands() -> Value {
    json!({"location":{"directory":"/work"},"data":[
        {"name":"init","description":"guided AGENTS.md setup"},
        {"name":"review","description":"review changes [commit|branch|pr], defaults to uncommitted"}
    ]})
}

fn paths(transport: &MockHttpTransport) -> Vec<String> {
    transport
        .captured_requests()
        .into_iter()
        .map(|request| format!("{} {}", request.method, request.path))
        .collect()
}

#[tokio::test]
async fn legacy_discovery_reads_the_skill_route() {
    let mut client = client(Generation::Legacy1);
    client.transport().push_response(response(json!([
        {"name":"review","description":"  Review the diff.  ","location":"/home/u/.config/opencode/skill/review/SKILL.md","content":"..."},
        {"name":"Deploy","location":"/work/.opencode/skill/deploy/SKILL.md","content":"..."},
        {"name":"broken","description":"no location","content":"..."},
        {"name":"  ","location":"/work/blank/SKILL.md"}
    ])));
    let skills = discover_skills_with_client(&mut client).await.unwrap();
    assert_eq!(
        serde_json::to_value(&skills).unwrap(),
        json!([
            {"name":"Deploy","path":"/work/.opencode/skill/deploy/SKILL.md","enabled":true},
            {
                "name":"review",
                "description":"Review the diff.",
                "path":"/home/u/.config/opencode/skill/review/SKILL.md",
                "enabled":true,
                "shortDescription":"Review the diff."
            }
        ])
    );
    assert_eq!(
        paths(client.transport()),
        ["GET http://127.0.0.1:4096/skill?directory=%2Fwork"]
    );
}

#[tokio::test]
async fn v2_discovery_names_skills_by_id_with_their_display_name() {
    let mut client = client(Generation::V2);
    client.transport().push_stream(Vec::<Vec<u8>>::new());
    client.transport().push_response(response(v2_skills()));
    client.transport().push_response(response(v2_commands()));
    let skills = discover_skills_with_client(&mut client).await.unwrap();
    let skills = serde_json::to_value(&skills).unwrap();
    assert_eq!(
        skills
            .as_array()
            .unwrap()
            .iter()
            .map(|skill| skill["name"].clone())
            .collect::<Vec<_>>(),
        [json!("opencode"), json!("plum"), json!("report")]
    );
    assert_eq!(
        skills[0],
        json!({
            "name":"opencode",
            "description":"Use this skill for any question about OpenCode itself.",
            "path":"/builtin/opencode.md",
            "enabled":true,
            "displayName":"OpenCode",
            "shortDescription":"Use this skill for any question about OpenCode itself."
        })
    );
    assert!(skills[1].get("displayName").is_none());
    assert_eq!(
        paths(client.transport()),
        [
            "GET http://127.0.0.1:4096/api/event?directory=%2Fwork",
            "GET http://127.0.0.1:4096/api/skill?directory=%2Fwork",
            "GET http://127.0.0.1:4096/api/command?directory=%2Fwork",
        ]
    );
}

#[tokio::test]
async fn v2_discovery_waits_for_a_first_scan_and_reads_again() {
    let mut client = client(Generation::V2);
    client.transport().push_stream([concat!(
        "data: {\"type\":\"skill.updated\",\"location\":{\"directory\":\"/elsewhere\"}}\n\n",
        "data: {\"type\":\"command.updated\",\"location\":{\"directory\":\"/work\"}}\n\n",
        "data: {\"type\":\"skill.updated\",\"location\":{\"directory\":\"/work\"}}\n\n"
    )
    .as_bytes()
    .to_vec()]);
    client.transport().push_response(response(
        json!({"location":{"directory":"/work"},"data":[]}),
    ));
    client.transport().push_response(response(
        json!({"location":{"directory":"/work"},"data":[]}),
    ));
    client.transport().push_response(response(v2_skills()));
    let skills = discover_skills_with_client(&mut client).await.unwrap();
    assert_eq!(skills.len(), 3);
    assert_eq!(paths(client.transport()).len(), 4);
}

#[tokio::test]
async fn v2_discovery_reports_a_failed_listing() {
    let mut client = client(Generation::V2);
    client.transport().push_stream(Vec::<Vec<u8>>::new());
    client
        .transport()
        .push_response(HttpResponse::new(500, br#"{"message":"boom"}"#.to_vec()));
    assert!(discover_skills_with_client(&mut client)
        .await
        .unwrap_err()
        .contains("OpenCode skill listing failed"));
}

async fn started(generation: OpenCodeGeneration) -> OpenCodeProvider<MockHttpTransport> {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({"id":"s1"})));
    transport.push_stream(Vec::<Vec<u8>>::new());
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation,
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.client().transport().clear_captured_requests();
    provider
}

fn last_body(provider: &OpenCodeProvider<MockHttpTransport>) -> Value {
    let request = provider
        .client()
        .transport()
        .captured_requests()
        .pop()
        .unwrap();
    serde_json::from_slice(&request.body).unwrap()
}

#[tokio::test]
async fn v2_prompts_name_the_known_skills_they_mention_and_keep_the_text() {
    let mut provider = started(OpenCodeGeneration::V2).await;
    let text = "Use $plum, then $unknown and $plum again for $25 \u{20ac}report";
    provider
        .client()
        .transport()
        .push_response(response(v2_skills()));
    provider
        .client()
        .transport()
        .push_response(response(json!({"id":"m1"})));
    provider
        .send_turn(TurnInput::text("thread", text))
        .await
        .unwrap();
    assert_eq!(
        paths(provider.client().transport()),
        [
            "GET http://127.0.0.1:4096/api/skill",
            "POST http://127.0.0.1:4096/api/session/s1/prompt",
        ]
    );
    let body = last_body(&provider);
    assert_eq!(body["text"], text);
    // `$plum,` ends at punctuation, so only the later `$plum` names it.
    assert_eq!(body["skills"], json!([{"id":"plum"},{"id":"report"}]));
}

#[tokio::test]
async fn v2_prompts_without_mentions_skip_the_listing() {
    let mut provider = started(OpenCodeGeneration::V2).await;
    provider
        .client()
        .transport()
        .push_response(response(json!({"id":"m1"})));
    provider
        .send_turn(TurnInput::text("thread", "costs $25 today"))
        .await
        .unwrap();
    assert_eq!(paths(provider.client().transport()).len(), 1);
    assert!(last_body(&provider).get("skills").is_none());
}

#[tokio::test]
async fn v2_prompts_send_no_skills_when_the_listing_fails() {
    let mut provider = started(OpenCodeGeneration::V2).await;
    provider
        .client()
        .transport()
        .push_response(HttpResponse::new(500, b"{}".to_vec()));
    provider
        .client()
        .transport()
        .push_response(response(json!({"id":"m1"})));
    provider
        .send_turn(TurnInput::text("thread", "$plum"))
        .await
        .unwrap();
    let body = last_body(&provider);
    assert_eq!(body["text"], "$plum");
    assert!(body.get("skills").is_none());
}

#[tokio::test]
async fn legacy_prompts_send_mentions_as_plain_text() {
    let mut provider = started(OpenCodeGeneration::Legacy1).await;
    provider
        .client()
        .transport()
        .push_response(response(json!({"id":"m1"})));
    provider
        .send_turn(TurnInput::text("thread", "Use $plum"))
        .await
        .unwrap();
    assert_eq!(
        paths(provider.client().transport()),
        ["POST http://127.0.0.1:4096/session/s1/prompt_async"]
    );
    assert_eq!(
        last_body(&provider)["parts"],
        json!([{"type":"text","text":"Use $plum"}])
    );
}
