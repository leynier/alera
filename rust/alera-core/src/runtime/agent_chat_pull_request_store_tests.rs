use serde_json::json;

use super::RuntimeStore;

const URL: &str = "https://github.com/acme/app/pull/7";

#[tokio::test]
async fn a_chat_links_watches_and_unlinks_a_pull_request() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let (row, already) = store
        .link_agent_chat_pull_request("chat-a", "github", 7, URL, Some("acme/app"))
        .await
        .unwrap();
    assert!(!already);
    assert!(!row.watching);
    let (_, already) = store
        .link_agent_chat_pull_request("chat-a", "github", 7, URL, None)
        .await
        .unwrap();
    assert!(already);
    assert!(store
        .set_agent_chat_pull_request_watch("chat-a", URL, true, Some(&json!({"streak": 1})))
        .await
        .unwrap());
    assert!(!store
        .set_agent_chat_pull_request_watch("chat-b", URL, true, None)
        .await
        .unwrap());
    let watched = store.list_watched_agent_chat_pull_requests().await.unwrap();
    assert_eq!(watched.len(), 1);
    assert_eq!(watched[0].watch_state, Some(json!({"streak": 1})));
    assert_eq!(watched[0].repository.as_deref(), Some("acme/app"));
    assert_eq!(
        store
            .list_agent_chat_pull_requests("chat-a")
            .await
            .unwrap()
            .len(),
        1
    );
    assert!(store
        .unlink_agent_chat_pull_request("chat-a", URL)
        .await
        .unwrap());
    assert!(!store
        .unlink_agent_chat_pull_request("chat-a", URL)
        .await
        .unwrap());
    assert!(store
        .list_watched_agent_chat_pull_requests()
        .await
        .unwrap()
        .is_empty());
}
