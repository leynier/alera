mod support;

use alera_provider_claude::{ClaudeProvider, ClaudeProviderConfig};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput};
use support::*;

fn config_with_transcript(lines: &[&str]) -> ClaudeProviderConfig {
    let config = isolated_config();
    let project = std::path::PathBuf::from(&config.options.env["CLAUDE_CONFIG_DIR"])
        .join("projects")
        .join("-workspace");
    std::fs::create_dir_all(&project).unwrap();
    std::fs::write(project.join("native-saved.jsonl"), lines.join("\n")).unwrap();
    config
}

async fn start(config: ClaudeProviderConfig) -> (ClaudeProvider, ScriptedTransportHandle) {
    let (transport, handle) = ScriptedTransport::new([initialize_response()]);
    let mut provider = ClaudeProvider::with_transport(transport, config).unwrap();
    provider.initialize().await.unwrap();
    let session = SessionStartInput {
        resume_thread_id: Some("native-saved".into()),
        ..SessionStartInput::new("app-thread")
    };
    provider.start_session(session).await.unwrap();
    (provider, handle)
}

#[tokio::test]
async fn a_session_that_never_saved_a_message_starts_fresh_with_a_notice() {
    let config = config_with_transcript(&[r#"{"type":"last-prompt"}"#, r#"{"type":"cost-state"}"#]);
    let (mut provider, _handle) = start(config).await;
    assert!(provider
        .session()
        .unwrap()
        .native_thread_id
        .starts_with("pending:"));
    let mut notice = None;
    for _ in 0..3 {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::RuntimeWarning {
            notice = Some(event);
        }
    }
    assert_eq!(
        notice.unwrap().payload["message"],
        "The earlier Claude session never saved a message, so a new session continues this chat."
    );
}

#[tokio::test]
async fn a_saved_session_resumes() {
    let config = config_with_transcript(&[r#"{"type":"user","message":{}}"#]);
    let (provider, _handle) = start(config).await;
    assert_eq!(provider.session().unwrap().native_thread_id, "native-saved");
}
