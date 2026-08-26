use std::sync::Arc;

use super::*;

#[tokio::test]
async fn remote_cancellation_signals_the_running_job() {
    let (sender, receiver) = oneshot::channel();
    active_requests()
        .lock()
        .unwrap()
        .insert("remote-1".to_string(), sender);

    assert!(cancel("remote-1").unwrap());
    receiver.await.unwrap();
}

#[tokio::test]
async fn mobile_base64_audio_uses_a_temporary_file() {
    let audio =
        RemoteAudioSource::Base64(base64::engine::general_purpose::STANDARD.encode(b"audio"))
            .prepare()
            .await
            .unwrap();
    let path = audio.path.clone();

    assert!(path.is_file());
    drop(audio);
    assert!(!path.exists());
}

#[tokio::test]
async fn cancelling_openai_job_aborts_in_flight_http_work() {
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let address = listener.local_addr().unwrap();
    let request_started = Arc::new(tokio::sync::Notify::new());
    let handler_started = Arc::clone(&request_started);
    let app = axum::Router::new().route(
        "/v1/audio/transcriptions",
        axum::routing::post(move || {
            let handler_started = Arc::clone(&handler_started);
            async move {
                handler_started.notify_one();
                tokio::time::sleep(Duration::from_secs(10)).await;
                axum::Json(json!({"text": "too late"}))
            }
        }),
    );
    let server = tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    let dir = tempfile::tempdir().unwrap();
    let audio_path = dir.path().join("audio.wav");
    std::fs::write(&audio_path, b"audio").unwrap();
    let job = RemoteDictationJob::OpenAi {
        audio: RemoteAudioSource::Path(audio_path),
        base_url: format!("http://{address}"),
        model: "speech-model".to_string(),
        token: None,
        language: None,
        prompt: None,
        timeout: Duration::from_secs(30),
    };
    let (cancel_tx, cancel_rx) = oneshot::channel();
    let running = tokio::spawn(async move { job.run("remote-http", cancel_rx).await });
    request_started.notified().await;

    cancel_tx.send(()).unwrap();
    let error = tokio::time::timeout(Duration::from_secs(1), running)
        .await
        .unwrap()
        .unwrap()
        .unwrap_err();

    assert!(error.to_string().contains("cancelled"));
    server.abort();
}

#[test]
fn saved_tokens_are_bound_to_the_provider_origin() {
    let token = token_for_origin(
        Some(StoredAiDictationCredential {
            token: "secret".to_string(),
            origin: Some("https://api.example.test".to_string()),
        }),
        "https://api.example.test",
    )
    .unwrap();
    assert_eq!(token.as_deref(), Some("secret"));

    let error = token_for_origin(
        Some(StoredAiDictationCredential {
            token: "secret".to_string(),
            origin: Some("https://other.example.test".to_string()),
        }),
        "https://api.example.test",
    )
    .unwrap_err();
    assert!(error.to_string().contains("different API origin"));
}
