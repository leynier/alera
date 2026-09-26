use super::*;

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    (directory, store)
}

async fn link(store: &RuntimeStore, number: i64, dismissed: bool) {
    store
        .upsert_linked_review(LinkedReview {
            workspace_id: "ws-1".into(),
            dismissed,
            provider: Some("github".into()),
            number: Some(number),
            url: Some(format!("https://github.com/o/r/pull/{number}")),
            linked_at: Utc::now(),
        })
        .await
        .unwrap();
}

#[test]
fn summaries_stay_where_they_are_asked() {
    assert!(is_forwarded_pull_request_verb(
        "mobile.pullRequest.snapshot"
    ));
    assert!(is_forwarded_pull_request_verb("mobile.pullRequest.merge"));
    assert!(!is_forwarded_pull_request_verb(
        "mobile.pullRequest.summaries"
    ));
    assert!(!is_forwarded_pull_request_verb("mobile.git.status"));
}

#[tokio::test]
async fn forwarded_payload_carries_the_hub_link_or_an_explicit_null() {
    let (_directory, store) = store().await;
    let payload = json!({"workspaceId": "ws-1"});
    let empty = hub_pull_request_payload(&store, "ws-1", &payload)
        .await
        .unwrap();
    assert!(empty.get(HUB_LINKED_REVIEW_KEY).unwrap().is_null());
    link(&store, 7, false).await;
    let linked = hub_pull_request_payload(&store, "ws-1", &payload)
        .await
        .unwrap();
    assert_eq!(linked[HUB_LINKED_REVIEW_KEY]["number"], 7);
    assert_eq!(linked[HUB_LINKED_REVIEW_KEY]["dismissed"], false);
    assert_eq!(linked["workspaceId"], "ws-1");
}

#[tokio::test]
async fn satellite_adopts_the_hub_link_and_leaves_local_clients_alone() {
    let (_directory, store) = store().await;
    link(&store, 3, false).await;
    // A phone paired to this runtime sends no hub record: nothing changes.
    adopt_hub_linked_review(&store, "ws-1", &json!({"workspaceId": "ws-1"}))
        .await
        .unwrap();
    assert_eq!(
        store
            .find_linked_review("ws-1")
            .await
            .unwrap()
            .unwrap()
            .number,
        Some(3)
    );
    adopt_hub_linked_review(
        &store,
        "ws-1",
        &json!({HUB_LINKED_REVIEW_KEY: {"number": 9, "dismissed": true, "provider": "github"}}),
    )
    .await
    .unwrap();
    let adopted = store.find_linked_review("ws-1").await.unwrap().unwrap();
    assert_eq!(adopted.number, Some(9));
    assert!(adopted.dismissed);
    // An explicit null means the hub has no link, so a stale copy goes away.
    adopt_hub_linked_review(&store, "ws-1", &json!({HUB_LINKED_REVIEW_KEY: null}))
        .await
        .unwrap();
    assert!(store.find_linked_review("ws-1").await.unwrap().is_none());
}

#[tokio::test]
async fn hub_adopts_the_satellite_link_only_after_a_link_changing_verb() {
    let (_directory, store) = store().await;
    let response = json!({"linkedReview": {"number": 12, "url": "u", "dismissed": false}});
    adopt_satellite_linked_review(&store, "ws-1", "mobile.pullRequest.comment", &response).await;
    assert!(store.find_linked_review("ws-1").await.unwrap().is_none());
    adopt_satellite_linked_review(&store, "ws-1", "mobile.pullRequest.create", &response).await;
    assert_eq!(
        store
            .find_linked_review("ws-1")
            .await
            .unwrap()
            .unwrap()
            .number,
        Some(12)
    );
    // The mutation applied but the refresh failed: keep what the hub has.
    adopt_satellite_linked_review(
        &store,
        "ws-1",
        "mobile.pullRequest.unlink",
        &json!({"mutationApplied": true, "refreshError": "gh timed out"}),
    )
    .await;
    assert!(store.find_linked_review("ws-1").await.unwrap().is_some());
}
