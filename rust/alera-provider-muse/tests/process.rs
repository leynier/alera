use alera_provider_muse::{MuseProvider, MuseProviderConfig};
use alera_provider_protocol::{EventKind, InterruptInput, Provider, SessionStartInput, TurnInput};
use std::path::PathBuf;
use std::time::Duration;

fn fixture() -> PathBuf {
    std::env::var("CARGO_BIN_EXE_muse-msp-fixture")
        .or_else(|_| std::env::var("CARGO_BIN_EXE_muse_msp_fixture"))
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            std::env::current_exe()
                .expect("test executable path")
                .parent()
                .and_then(std::path::Path::parent)
                .expect("target debug directory")
                .join(if cfg!(windows) {
                    "muse-msp-fixture.exe"
                } else {
                    "muse-msp-fixture"
                })
        })
}

#[tokio::test]
async fn process_transport_completes_handshake_turn_and_interrupt() {
    let mut config = MuseProviderConfig::with_executable(fixture());
    config.options.request_timeout = Duration::from_secs(2);
    config.options.shutdown_timeout = Duration::from_secs(2);
    let mut provider = MuseProvider::new(config).unwrap();
    provider.initialize().await.unwrap();
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

    let turn = provider
        .send_turn(TurnInput::text("fixture-thread", "hello"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    provider
        .interrupt(InterruptInput {
            thread_id: "fixture-thread".into(),
            turn_id: Some(turn.turn_id),
        })
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnCompleted
    );
    provider.close().await.unwrap();
}
