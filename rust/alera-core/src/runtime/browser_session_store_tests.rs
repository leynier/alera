use chrono::Utc;
use serde_json::json;

use super::{
    normalize_browser_title, BrowserClosedTab, BrowserHistoryEntry, RuntimeStore,
    BROWSER_TITLE_MAX_BYTES,
};

#[tokio::test]
async fn normalizes_page_controlled_titles_at_the_sqlite_boundary() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let raw_title = format!(" \u{0}Docs\n{}\t ", "🚀".repeat(300));
    let expected = normalize_browser_title(&raw_title);

    let history = store
        .record_browser_history(BrowserHistoryEntry {
            id: "bounded-history".to_string(),
            profile_id: "work".to_string(),
            workspace_id: None,
            tab_id: None,
            url: "https://example.com/docs".to_string(),
            title: raw_title.clone(),
            visit_count: 1,
            visited_at: Utc::now(),
        })
        .await
        .unwrap();
    let closed = store
        .record_closed_browser_tab(BrowserClosedTab {
            id: "bounded-closed".to_string(),
            profile_id: "work".to_string(),
            workspace_id: "workspace".to_string(),
            url: "https://example.com/docs".to_string(),
            title: raw_title.clone(),
            payload: json!({
                "browserUrl": "https://example.com/docs",
                "browserRuntimeTitle": raw_title,
            }),
            closed_at: Utc::now(),
        })
        .await
        .unwrap();

    assert_eq!(expected.len(), BROWSER_TITLE_MAX_BYTES);
    assert!(!expected.chars().any(char::is_control));
    assert_eq!(history.title, expected);
    assert_eq!(closed.title, expected);
    assert_eq!(closed.payload["browserRuntimeTitle"], expected);
    assert_eq!(
        store.list_browser_history(None, 10).await.unwrap()[0].title,
        expected
    );
    assert_eq!(
        store.list_closed_browser_tabs(None, 10).await.unwrap()[0].title,
        expected
    );
}
