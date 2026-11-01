mod support;

use alera_provider_protocol::{
    EventKind, InteractionMode, Provider, ProviderEvent, RuntimeMode, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use support::*;

const NOTICE: &str =
    "Alera could not confirm Claude bypass permissions here, so Full Access is running with approval checks.";

fn full_access() -> SessionStartInput {
    SessionStartInput {
        runtime_mode: RuntimeMode::FullAccess,
        ..SessionStartInput::new("app-thread")
    }
}

/// An isolated config whose user settings are [settings].
fn config_with_settings(settings: &str) -> alera_provider_claude::ClaudeProviderConfig {
    let config = isolated_config();
    let dir = std::path::PathBuf::from(&config.options.env["CLAUDE_CONFIG_DIR"]);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("settings.json"), settings).unwrap();
    config
}

async fn turn(provider: &mut impl Provider, input: TurnInput) -> Vec<ProviderEvent> {
    provider.send_turn(input).await.unwrap();
    let mut events = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        let done = event.kind == EventKind::TurnCompleted;
        events.push(event);
        if done {
            return events;
        }
    }
}

fn notices(events: &[ProviderEvent]) -> Vec<&ProviderEvent> {
    events
        .iter()
        .filter(|event| {
            event.kind == EventKind::RuntimeWarning && event.payload["message"] == NOTICE
        })
        .collect()
}

fn ack(request_id: &str) -> Value {
    json!({
        "type": "control_response",
        "response": {"subtype": "success", "request_id": request_id, "response": {}}
    })
}

#[tokio::test]
async fn full_access_under_settings_without_bypass_runs_with_checks_and_says_so_once() {
    let settings = r#"{"permissions": {"disableBypassPermissionsMode": "disable"}}"#;
    let (mut provider, _handle) = started_provider_with_config(
        [
            initialize_response(),
            result_message(false, None),
            result_message(false, None),
        ],
        config_with_settings(settings),
        full_access(),
    )
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let first = turn(&mut provider, TurnInput::text("app-thread", "one")).await;
    let notice = notices(&first);
    assert_eq!(notice.len(), 1);
    assert_eq!(notice[0].turn_id.as_deref(), Some("turn:claude:1"));
    assert_eq!(notice[0].payload["detail"]["permissionMode"], "auto");
    assert_eq!(first[0].kind, EventKind::TurnStarted);
    let second = turn(&mut provider, TurnInput::text("app-thread", "two")).await;
    assert!(notices(&second).is_empty());
}

#[tokio::test]
async fn an_init_that_reports_another_mode_is_announced() {
    let (mut provider, _handle) = started_provider_with_config(
        [
            initialize_response(),
            json!({
                "type": "system", "subtype": "init", "session_id": "native-session",
                "permissionMode": "default"
            }),
            result_message(false, None),
        ],
        isolated_config(),
        full_access(),
    )
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let events = turn(&mut provider, TurnInput::text("app-thread", "one")).await;
    assert_eq!(notices(&events).len(), 1);
}

#[tokio::test]
async fn a_refused_bypass_restore_falls_back_to_default() {
    let mut config = isolated_config();
    config.options.permission_mode = Some("bypassPermissions".into());
    let (mut provider, handle) = started_provider_with_config(
        [
            initialize_response(),
            ack("req_2"),
            result_message(false, None),
            json!({
                "type": "control_response",
                "response": {
                    "subtype": "error", "request_id": "req_3",
                    "error": "Cannot set permission mode to bypassPermissions because it is disabled by settings or configuration"
                }
            }),
            ack("req_4"),
            result_message(false, None),
        ],
        config,
        SessionStartInput::new("app-thread"),
    )
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let mut plan = TurnInput::text("app-thread", "plan");
    plan.interaction_mode = InteractionMode::Plan;
    turn(&mut provider, plan).await;
    let events = turn(&mut provider, TurnInput::text("app-thread", "build")).await;
    assert_eq!(notices(&events).len(), 1);
    let writes = handle.writes.lock().unwrap();
    let modes = writes
        .iter()
        .filter(|frame| frame["request"]["subtype"] == "set_permission_mode")
        .map(|frame| frame["request"]["mode"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    assert_eq!(modes, ["plan", "bypassPermissions", "default"]);
}
