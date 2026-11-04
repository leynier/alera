use opencode_agent_sdk::{
    ClientConfig, Generation, HttpResponse, MockHttpTransport, OpenCodeClient, OpenCodeError,
};
use serde_json::{json, Value};

fn response(value: Value) -> HttpResponse {
    HttpResponse::new(200, serde_json::to_vec(&value).expect("JSON fixture"))
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

#[tokio::test]
async fn v2_lists_read_the_data_of_the_directory_routes() {
    let mut client = client(Generation::V2);
    client.transport().push_response(response(json!({
        "location": { "directory": "/work" },
        "data": [{ "id": "plum", "name": "plum", "path": "/work/.opencode/skills/plum/SKILL.md" }]
    })));
    client.transport().push_response(response(json!({
        "location": { "directory": "/work" },
        "data": [{ "name": "init", "description": "guided AGENTS.md setup" }]
    })));
    assert_eq!(client.list_skills().await.unwrap()[0]["id"], "plum");
    assert_eq!(client.list_commands().await.unwrap()[0]["name"], "init");
    let paths: Vec<_> = client
        .transport()
        .captured_requests()
        .into_iter()
        .map(|request| (request.method, request.path))
        .collect();
    assert_eq!(
        paths,
        [
            (
                "GET".to_owned(),
                "http://127.0.0.1:4096/api/skill?directory=%2Fwork".to_owned()
            ),
            (
                "GET".to_owned(),
                "http://127.0.0.1:4096/api/command?directory=%2Fwork".to_owned()
            ),
        ]
    );
}

#[tokio::test]
async fn legacy_lists_read_the_bare_arrays() {
    let mut client = client(Generation::Legacy1);
    client.transport().push_response(response(json!([
        { "name": "review", "description": "Review changes", "location": "/home/u/.config/opencode/skill/review/SKILL.md" }
    ])));
    client
        .transport()
        .push_response(response(json!({ "not": "a list" })));
    assert_eq!(client.list_skills().await.unwrap()[0]["name"], "review");
    assert!(matches!(
        client.list_commands().await,
        Err(OpenCodeError::Protocol(_))
    ));
    assert_eq!(
        client.transport().captured_requests()[0].path,
        "http://127.0.0.1:4096/skill?directory=%2Fwork"
    );
}

#[tokio::test]
async fn v2_prompts_name_skills_by_id_and_keep_the_text() {
    let mut client = client(Generation::V2);
    client
        .transport()
        .push_response(response(json!({ "id": "m1" })));
    client
        .prompt_parts_with_skills(
            "s1",
            vec![json!({ "type": "text", "text": "use $plum and $plum" })],
            None,
            Some("message-1"),
            &["plum".to_owned()],
        )
        .await
        .unwrap();
    let request = client.transport().captured_requests().pop().unwrap();
    assert_eq!(
        request.path,
        "http://127.0.0.1:4096/api/session/s1/prompt?directory=%2Fwork"
    );
    let body: Value = serde_json::from_slice(&request.body).unwrap();
    assert_eq!(
        body,
        json!({ "text": "use $plum and $plum", "id": "message-1", "skills": [{ "id": "plum" }] })
    );
}

#[tokio::test]
async fn legacy_prompts_cannot_name_skills() {
    let mut client = client(Generation::Legacy1);
    let result = client
        .prompt_parts_with_skills(
            "s1",
            vec![json!({ "type": "text", "text": "$plum" })],
            None,
            None,
            &["plum".to_owned()],
        )
        .await;
    assert!(matches!(result, Err(OpenCodeError::Unsupported(_))));
    assert!(client.transport().captured_requests().is_empty());
}

#[tokio::test]
async fn raw_events_include_the_ones_sessions_skip() {
    let mut client = client(Generation::V2);
    client.transport().push_stream([concat!(
        "data: {\"type\":\"skill.updated\",\"location\":{\"directory\":\"/work\"}}\n\n",
        "data: {\"type\":\"command.updated\",\"location\":{\"directory\":\"/work\"}}\n\n"
    )
    .as_bytes()
    .to_vec()]);
    client.start_events().await.unwrap();
    let first = client.next_raw_event().await.unwrap().unwrap();
    assert_eq!(first["type"], "skill.updated");
    let second = client.next_raw_event().await.unwrap().unwrap();
    assert_eq!(second["location"]["directory"], "/work");
    assert!(client.next_raw_event().await.unwrap().is_none());
}
