//! Subprocess fixtures exercise the actual deferred execution boundary without credentials.
use std::collections::HashMap;
use std::time::Duration;

use alera_core::runtime::{RuntimeAiAssistSettings, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::json;

use super::actor_test_harness::test_actor;
use super::agent_title_state::initialize;
use super::ai_assist_requests::{run_command, AiAssistCommandPlan};
use super::ServerCommand;

#[tokio::test]
async fn fake_agent_title_provider_runs_in_background_and_applies_its_result() {
    let dir = tempfile::tempdir().unwrap();
    let fixture = dir.path().join("provider.sh");
    std::fs::write(&fixture, "cat >/dev/null\nprintf 'Fix Login With Google'\n").unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let (inbox, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor
        .runtime_store
        .set_ai_assist_settings(RuntimeAiAssistSettings {
            agent: "custom".into(),
            custom_command: format!("sh '{}'", fixture.display()),
            ..Default::default()
        })
        .await
        .unwrap();
    let mut tab = WorkspaceTabRecord {
        id: "tab".into(),
        workspace_id: "workspace".into(),
        kind: "terminal".into(),
        title: "Original".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        payload: json!({}),
    };
    initialize(&mut tab, "Repair Google login");
    let request = json!({"tabId": tab.id, "expectedConversationId": tab.payload["agentTitleConversationId"], "expectedRevision": tab.payload["agentTitleRevision"]});
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    actor.request_agent_title(1, 1, &request).await.unwrap();
    let ServerCommand::AgentTitleReady { tab_id, id } = receiver.recv().await.unwrap() else {
        panic!("expected ready");
    };
    actor.start_agent_title(tab_id, id).await;
    let completion = tokio::time::timeout(Duration::from_secs(10), receiver.recv())
        .await
        .unwrap()
        .unwrap();
    let ServerCommand::AgentTitleFinished { tab_id, id, result } = completion else {
        panic!("expected result");
    };
    assert!(result.is_ok());
    actor.finish_agent_title(tab_id, id, result).await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(saved.title, "Fix Login With Google");
    assert_eq!(saved.payload["agentTitleStatus"], "idle");
    assert_eq!(
        std::fs::read_dir(dir.path().join("agent-title-jobs"))
            .unwrap()
            .count(),
        0
    );
}

fn plan(script: &str) -> AiAssistCommandPlan {
    AiAssistCommandPlan {
        binary: "sh".into(),
        arguments: vec!["-c".into(), script.into()],
        stdin_payload: None,
        label: "Fixture".into(),
        temporary_directory: None,
        environment: HashMap::from([
            (
                "ALERA_TERMINAL_SESSION_ID".into(),
                "must-not-inherit".into(),
            ),
            ("ALERA_WORKSPACE_ID".into(), "workspace".into()),
            ("ALERA_TAB_ID".into(), "tab".into()),
            ("ALERA_RUNTIME_DIR".into(), "runtime".into()),
        ]),
    }
}

#[tokio::test]
async fn internal_agent_title_provider_drops_hook_identity() {
    let dir = tempfile::tempdir().unwrap();
    let (_cancel, receiver) = tokio::sync::oneshot::channel();
    let output = run_command(plan("test -z \"$ALERA_TERMINAL_SESSION_ID$ALERA_WORKSPACE_ID$ALERA_TAB_ID$ALERA_RUNTIME_DIR\" || exit 1; printf 'Safe Provider Title'"), &dir.path().to_string_lossy(), 5, receiver).await.unwrap();
    assert_eq!(output, "Safe Provider Title");
}

#[tokio::test]
async fn agent_title_provider_honors_cancellation_and_timeout() {
    let dir = tempfile::tempdir().unwrap();
    let (cancel, receiver) = tokio::sync::oneshot::channel();
    cancel.send(()).unwrap();
    assert!(run_command(
        plan("exec sleep 30"),
        &dir.path().to_string_lossy(),
        5,
        receiver
    )
    .await
    .is_err());
    let (_cancel, receiver) = tokio::sync::oneshot::channel();
    assert!(run_command(
        plan("exec sleep 30"),
        &dir.path().to_string_lossy(),
        0,
        receiver
    )
    .await
    .is_err());
}
