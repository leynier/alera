use alera_provider_pi::{PiProvider, PiProviderConfig};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput, TurnInput};

#[tokio::test]
async fn spawn_uses_jsonl_handshake_and_terminal_probe() {
    let executable = std::env::var("CARGO_BIN_EXE_pi_jsonl_fixture")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| {
            std::env::current_exe()
                .expect("test executable path")
                .parent()
                .and_then(std::path::Path::parent)
                .expect("target debug directory")
                .join(if cfg!(windows) {
                    "pi-jsonl-fixture.exe"
                } else {
                    "pi-jsonl-fixture"
                })
        });
    let config = PiProviderConfig {
        executable,
        request_timeout: std::time::Duration::from_secs(2),
        ..PiProviderConfig::default()
    };
    let mut provider = PiProvider::spawn(config).await.unwrap();
    provider
        .start_session(SessionStartInput::new("fixture-thread"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::SessionStarted
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider
        .send_turn(TurnInput::text("fixture-thread", "hello"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ContentDelta
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnCompleted
    );
    provider.close().await.unwrap();
}
