use std::collections::HashMap;

use alera_core::runtime::{normalize_browser_title, WorkspaceTabRecord, BROWSER_TITLE_MAX_BYTES};
use chrono::Utc;
use serde_json::json;

use super::*;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::test_actor;
use crate::terminal_host::server::ClientState;

#[test]
fn history_requires_an_explicit_completed_navigation() {
    assert_eq!(
        completed_history_url(Some("https://example.com/".to_string()), false),
        None
    );
    assert_eq!(
        completed_history_url(Some("https://example.com/".to_string()), true),
        Some("https://example.com/".to_string())
    );
    assert_eq!(
        completed_history_url(Some("about:blank".to_string()), true),
        None
    );
}

#[test]
fn control_only_page_titles_are_omitted() {
    let (title, may_persist) =
        normalized_page_title(&json!({"title": "\u{0}\n\t"}), Some("https://example.com"));

    assert!(may_persist);
    assert_eq!(title, None);
}

#[test]
fn page_titles_require_their_current_url() {
    let (title, may_persist) = normalized_page_title(&json!({"title": "Private Account"}), None);

    assert!(!may_persist);
    assert_eq!(title, None);
}

#[tokio::test]
async fn driver_normalizes_titles_before_publication_and_preserves_manual_titles() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _outbound) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(7, ClientState::local(handle, true))]),
        HashMap::new(),
    )
    .await;
    actor
        .runtime_store
        .ensure_default_browser_profile()
        .await
        .unwrap();
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "page-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "browser".to_string(),
            title: "New Tab".to_string(),
            created_at: now,
            updated_at: now,
            payload: json!({"browserProfileId": "default"}),
        })
        .await
        .unwrap();
    actor
        .register_browser_driver(
            7,
            &json!({
                "appInstanceId": "app",
                "driverInstanceId": "driver",
                "engine": "test",
                "platform": "test",
                "capabilities": ["stableGate"],
            }),
        )
        .unwrap();

    let raw_title = format!(" \u{0}Docs\n{}\t ", "🚀".repeat(300));
    let expected = normalize_browser_title(&raw_title);
    let sync = actor
        .sync_browser_driver(
            7,
            &json!({
                "driverInstanceId": "driver",
                "pages": [{
                    "pageId": "page-1",
                    "workspaceId": "workspace-1",
                    "profileId": "default",
                    "url": "https://example.com/docs",
                    "title": raw_title,
                }],
            }),
        )
        .await
        .unwrap();
    let generation = sync["pages"][0]["generation"].as_u64().unwrap();
    assert_eq!(
        actor.browser.page("page-1").unwrap().title.as_deref(),
        Some(expected.as_str())
    );
    assert_eq!(expected.len(), BROWSER_TITLE_MAX_BYTES);
    assert!(!expected.chars().any(char::is_control));

    let changed = actor
        .browser_driver_page_changed(
            7,
            &json!({
                "driverInstanceId": "driver",
                "pageId": "page-1",
                "generation": generation,
                "url": "https://example.com/docs",
                "title": raw_title,
                "navigationCompleted": true,
            }),
        )
        .await
        .unwrap();

    assert_eq!(changed["page"]["title"], expected);
    let safe_stored = actor
        .runtime_store
        .find_workspace_tab("page-1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(safe_stored.title, expected);
    assert_eq!(safe_stored.payload["browserRuntimeTitle"], expected);

    let sensitive = actor
        .browser_driver_page_changed(
            7,
            &json!({
                "driverInstanceId": "driver",
                "pageId": "page-1",
                "generation": generation,
                "url": "https://example.com/oauth/callback?code=secret",
                "title": "Private Account 123",
                "navigationCompleted": true,
            }),
        )
        .await
        .unwrap();
    assert_eq!(sensitive["page"]["title"], expected);
    let sanitized = actor
        .runtime_store
        .find_workspace_tab("page-1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sanitized.title, expected);
    assert!(sanitized.payload.get("browserRuntimeTitle").is_none());

    actor
        .runtime_store
        .rename_workspace_tab("page-1", "Pinned Title")
        .await
        .unwrap();
    actor
        .browser_driver_page_changed(
            7,
            &json!({
                "driverInstanceId": "driver",
                "pageId": "page-1",
                "generation": generation,
                "url": "https://example.com/?SAMLResponse=secret",
                "title": "Private SAML Account",
                "navigationCompleted": true,
            }),
        )
        .await
        .unwrap();
    let manual = actor
        .runtime_store
        .find_workspace_tab("page-1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(manual.title, "Pinned Title");
    assert_eq!(manual.payload["manualTitle"], true);
    assert!(manual.payload.get("browserRuntimeTitle").is_none());
    let history = actor
        .runtime_store
        .list_browser_history(Some("default"), 10)
        .await
        .unwrap();
    assert!(history.iter().any(|entry| entry.title == expected));
    assert!(history.iter().all(|entry| !entry.title.contains("Private")));
}
