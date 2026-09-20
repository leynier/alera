use super::*;
use reqwest::StatusCode;
use serde_json::json;

#[test]
fn routes_documented_models_to_the_matching_endpoint() {
    assert_eq!(route_for_model("grok-4.6"), OpenCodeGoRoute::Responses);
    assert_eq!(route_for_model("gpt-5.6-luna"), OpenCodeGoRoute::Responses);
    assert_eq!(
        route_for_model("muse-spark-1.3-contributor"),
        OpenCodeGoRoute::Responses
    );
    assert_eq!(route_for_model("minimax-m2.7"), OpenCodeGoRoute::Messages);
    assert_eq!(route_for_model("qwen3.8-flash"), OpenCodeGoRoute::Messages);
    assert_eq!(
        route_for_model("glm-5.3-flash"),
        OpenCodeGoRoute::ChatCompletions
    );
    assert_eq!(
        route_for_model("unknown-model"),
        OpenCodeGoRoute::ChatCompletions
    );
}

#[test]
fn extracts_chat_completion_message_text() {
    let body = json!({
        "choices": [{"message": {"content": "feat: add go assist"}}]
    })
    .to_string();
    assert_eq!(
        extract_chat_completions_text(&body).as_deref(),
        Some("feat: add go assist")
    );
}

#[test]
fn extracts_chat_completion_sse_deltas() {
    let body = "data: {\"choices\":[{\"delta\":{\"content\":\"feat\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\": go\"}}]}\n\ndata: [DONE]\n";
    assert_eq!(
        extract_chat_completions_text(body).as_deref(),
        Some("feat: go")
    );
}

#[test]
fn extracts_responses_output_text_and_sse() {
    let json_body = json!({
        "output_text": "Title from responses"
    })
    .to_string();
    assert_eq!(
        extract_responses_text(&json_body).as_deref(),
        Some("Title from responses")
    );

    let sse = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello\"}\n\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\" world\"}\n\n";
    assert_eq!(extract_responses_text(sse).as_deref(), Some("Hello world"));
}

#[test]
fn extracts_anthropic_message_text() {
    let body = json!({
        "content": [{"type": "text", "text": "Cleaned speech"}]
    })
    .to_string();
    assert_eq!(
        extract_messages_text(&body).as_deref(),
        Some("Cleaned speech")
    );
}

#[test]
fn maps_auth_failures_to_quota_wording() {
    assert_eq!(
        map_go_http_error(StatusCode::UNAUTHORIZED)
            .unwrap()
            .wire_message(),
        "OpenCode Go API key was rejected"
    );
    assert_eq!(
        map_go_http_error(StatusCode::FORBIDDEN)
            .unwrap()
            .wire_message(),
        "OpenCode Go subscription is not active"
    );
    assert!(map_go_http_error(StatusCode::OK).is_none());
}

#[test]
fn interpret_completion_rejects_empty_success_bodies() {
    let error = interpret_completion(
        OpenCodeGoRoute::ChatCompletions,
        StatusCode::OK,
        json!({"choices":[{"message":{"content":"   "}}]}).to_string(),
    )
    .unwrap_err();
    assert_eq!(error.wire_message(), "OpenCode Go returned no text.");
}

#[test]
fn parse_models_catalog_reads_openai_style_data() {
    let models = parse_models_catalog(&json!({
        "data": [
            {"id": "glm-5.3-flash", "name": "GLM-5.3-Flash"},
            {"id": "glm-5.3-flash"},
            {"id": "kimi-k3"}
        ]
    }));
    assert_eq!(models.len(), 2);
    assert_eq!(models[0].id, "glm-5.3-flash");
    assert_eq!(models[0].label, "GLM-5.3-Flash");
    assert_eq!(models[1].id, "kimi-k3");
    assert_eq!(models[1].label, "kimi-k3");
}

#[test]
fn user_agent_identifies_alera() {
    assert!(user_agent().starts_with("alera/"));
}

#[test]
fn request_bodies_match_documented_routes() {
    let completions = request_body(OpenCodeGoRoute::ChatCompletions, "glm-5.3-flash", "hello");
    assert_eq!(completions["model"], "glm-5.3-flash");
    assert_eq!(completions["stream"], false);
    assert_eq!(completions["messages"][0]["content"], "hello");

    let responses = request_body(OpenCodeGoRoute::Responses, "grok-4.6", "hello");
    assert_eq!(responses["input"], "hello");
    assert_eq!(responses["store"], false);
    assert_eq!(responses["stream"], true);

    let messages = request_body(OpenCodeGoRoute::Messages, "minimax-m2.7", "hello");
    assert_eq!(messages["max_tokens"], 4096);
    assert_eq!(messages["stream"], false);
}

#[test]
fn completion_urls_follow_the_documented_go_routes() {
    assert_eq!(
        completion_url(OpenCodeGoRoute::ChatCompletions),
        "https://opencode.ai/zen/go/v1/chat/completions"
    );
    assert_eq!(
        completion_url(OpenCodeGoRoute::Responses),
        "https://opencode.ai/zen/go/v1/responses"
    );
    assert_eq!(
        completion_url(OpenCodeGoRoute::Messages),
        "https://opencode.ai/zen/go/v1/messages"
    );
}

#[test]
fn interpret_completion_accepts_a_fake_http_success() {
    let text = interpret_completion(
        OpenCodeGoRoute::ChatCompletions,
        StatusCode::OK,
        json!({"choices":[{"message":{"content":"feat: add go assist"}}]}).to_string(),
    )
    .unwrap();
    assert_eq!(text, "feat: add go assist");
}

#[tokio::test]
async fn cancel_aborts_body_read_after_headers() {
    use std::time::Duration;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;
    use tokio::sync::oneshot;
    use tokio::time::timeout;

    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let address = listener.local_addr().unwrap();
    let (headers_sent_tx, headers_sent_rx) = oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        let mut buf = vec![0_u8; 4096];
        let _ = stream.read(&mut buf).await;
        stream
            .write_all(
                b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n",
            )
            .await
            .unwrap();
        stream.flush().await.unwrap();
        let _ = headers_sent_tx.send(());
        tokio::time::sleep(Duration::from_secs(30)).await;
    });

    let (cancel_tx, cancel_rx) = oneshot::channel();
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .unwrap();
    let request = client
        .post(format!("http://{address}/v1/responses"))
        .header("content-type", "application/json")
        .body("{}");
    let running = tokio::spawn(async move { send_and_read_cancellable(request, cancel_rx).await });
    headers_sent_rx.await.unwrap();
    // Headers already reached the client, so send() has finished and the body is open.
    tokio::time::sleep(Duration::from_millis(50)).await;
    let _ = cancel_tx.send(());
    let error = timeout(Duration::from_secs(2), running)
        .await
        .expect("cancel must abort the stalled body")
        .unwrap()
        .unwrap_err();
    assert_eq!(error.wire_message(), "Generation canceled.");
    server.abort();
}
