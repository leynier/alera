use alera_core::runtime::AgentChatNativeIdInput;
use serde_json::json;

use super::super::commands::CallerCtx;
use super::tests::{add_turn, fixture, NativeBoundaryProvider};

const USAGE: &str = r#"{"tokens": {"used": 4200, "limit": 200000}, "windows": [{"id": "5h"}]}"#;

async fn native_source(turns: &[&str]) -> (tempfile::TempDir, super::ChatSession) {
    let (root, mut session, _) = fixture().await;
    for turn in turns {
        add_turn(&mut session, turn, "prompt").await;
    }
    session.header.usage = Some(serde_json::from_str(USAGE).unwrap());
    session
        .deps
        .store
        .bind_agent_chat_native_thread(&session.header.chat_id, 1, Some("native-thread"))
        .await
        .unwrap();
    session.native_thread = Some("native-thread".into());
    for turn in turns {
        session
            .deps
            .store
            .map_agent_chat_native_id(&AgentChatNativeIdInput {
                chat_id: session.header.chat_id.clone(),
                generation: 1,
                kind: "turn".into(),
                native_id: json!(format!("native-{turn}")),
                app_id: Some((*turn).into()),
            })
            .await
            .unwrap();
    }
    session.provider = Some(Box::new(NativeBoundaryProvider));
    (root, session)
}

async fn fork_usage(session: &mut super::ChatSession, turn: &str) -> serde_json::Value {
    let fork = uuid::Uuid::new_v4().to_string();
    session
        .fork_history(
            turn,
            &fork,
            &format!("tab-{fork}"),
            None,
            &CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    session
        .deps
        .store
        .agent_chat(&fork)
        .await
        .unwrap()
        .unwrap()
        .snapshot["usage"]
        .clone()
}

#[tokio::test]
async fn a_native_fork_at_the_latest_turn_keeps_the_token_usage() {
    let (_root, mut session) = native_source(&["a", "b"]).await;
    assert_eq!(
        fork_usage(&mut session, "b").await,
        json!({"tokens": {"used": 4200, "limit": 200000}})
    );
    // An earlier turn's context is smaller than the source's usage says.
    assert!(fork_usage(&mut session, "a").await.is_null());
    // A transcript fork starts a fresh context.
    session.provider = None;
    assert!(fork_usage(&mut session, "b").await.is_null());
}

#[tokio::test]
async fn a_transcript_fallback_drops_the_copied_usage() {
    let (_root, mut session) = native_source(&["a"]).await;
    session.complete_native_fork().await.unwrap();
    assert!(session.header.usage.is_some());
    session.clear_native_fork("transcriptFork").await.unwrap();
    assert!(session.header.usage.is_none());
}
