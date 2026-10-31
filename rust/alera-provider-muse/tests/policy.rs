mod support;

use alera_provider_muse::{MuseProvider, MuseProviderConfig};
use alera_provider_protocol::{Provider, RuntimeMode, SessionStartInput};
use serde_json::{json, Value};
use support::{initialize_response, response, session_response, ScriptedTransport};

async fn session_writes(runtime_mode: RuntimeMode, resume: Option<&str>) -> Vec<Value> {
    let transport = ScriptedTransport::new([
        initialize_response(),
        session_response(2, resume.unwrap_or("muse-session")),
        response(3, json!({"applyOutcome":"completed"})),
    ]);
    let writes = transport.writes.clone();
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = runtime_mode;
    input.resume_thread_id = resume.map(str::to_owned);
    provider.start_session(input).await.unwrap();
    provider.close().await.unwrap();
    let writes = writes.lock().unwrap().clone();
    writes
}

#[tokio::test]
async fn selects_the_runtime_modes_permission_profile_on_start_and_resume() {
    for (mode, profile, approval_mode) in [
        (RuntimeMode::ApprovalRequired, ":ask-me", "promptUnmatched"),
        (RuntimeMode::Auto, ":auto-review", "promptUnmatched"),
        (RuntimeMode::FullAccess, ":unrestricted", "allowAll"),
    ] {
        let started = session_writes(mode, None).await;
        assert_eq!(started[2]["method"], "session/start");
        assert_eq!(started[2]["params"]["permissionProfile"], profile);
        assert_eq!(started[2]["params"]["approvalMode"], approval_mode);
        assert!(started
            .iter()
            .all(|frame| frame["method"] != "session/setApprovalMode"));

        let resumed = session_writes(mode, Some("saved-session")).await;
        assert_eq!(resumed[2]["method"], "session/resume");
        assert_eq!(resumed[2]["params"]["permissionProfile"], profile);
        assert_eq!(resumed[3]["method"], "session/setApprovalMode");
        assert_eq!(resumed[3]["params"]["sessionId"], "saved-session");
        assert_eq!(resumed[3]["params"]["mode"], approval_mode);
    }
}
