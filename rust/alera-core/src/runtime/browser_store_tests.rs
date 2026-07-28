use chrono::{Duration, Utc};
use serde_json::json;

use super::{
    BrowserClosedTab, BrowserHistoryEntry, BrowserPermission, BrowserPermissionDecision,
    BrowserProfile, BrowserProfileSource, BrowserProfileSourceFamily, BrowserSearchEngine,
    BrowserSettings, RuntimeStore, DEFAULT_BROWSER_PROFILE_ID,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn profile(id: &str, name: &str) -> BrowserProfile {
    let now = Utc::now();
    BrowserProfile {
        id: id.to_string(),
        name: name.to_string(),
        persistent: true,
        is_default: false,
        source: None,
        created_at: now,
        updated_at: now,
    }
}

#[tokio::test]
async fn creates_one_default_profile_idempotently() {
    let (_dir, store) = store().await;
    let first = store.ensure_default_browser_profile().await.unwrap();
    let second = store.ensure_default_browser_profile().await.unwrap();

    assert_eq!(first.id, DEFAULT_BROWSER_PROFILE_ID);
    assert!(first.is_default);
    assert_eq!(first.id, second.id);
    assert_eq!(store.list_browser_profiles().await.unwrap().len(), 1);
}

#[tokio::test]
async fn browser_settings_default_to_google_and_store_only_the_typed_engine() {
    let (_dir, store) = store().await;
    assert_eq!(
        store.browser_settings().await.unwrap().search_engine,
        BrowserSearchEngine::Google
    );

    let saved = store
        .set_browser_settings(BrowserSettings {
            search_engine: BrowserSearchEngine::Kagi,
        })
        .await
        .unwrap();
    assert_eq!(saved.search_engine, BrowserSearchEngine::Kagi);
    assert_eq!(store.browser_settings().await.unwrap(), saved);
}

#[tokio::test]
async fn profile_names_are_unique_and_default_identity_is_fixed() {
    let (_dir, store) = store().await;
    store.ensure_default_browser_profile().await.unwrap();
    store
        .upsert_browser_profile(profile("work", "Work"))
        .await
        .unwrap();

    let mut personal = profile("personal", "Personal");
    personal.is_default = true;
    assert!(store.upsert_browser_profile(personal).await.is_err());

    let profiles = store.list_browser_profiles().await.unwrap();
    assert_eq!(profiles[0].id, DEFAULT_BROWSER_PROFILE_ID);
    assert_eq!(profiles.iter().filter(|item| item.is_default).count(), 1);

    let error = store
        .upsert_browser_profile(profile("duplicate", " work "))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("already exists"));
}

#[tokio::test]
async fn default_profile_is_persistent_and_cannot_be_removed() {
    let (_dir, store) = store().await;
    let mut malicious_default = profile(DEFAULT_BROWSER_PROFILE_ID, "Default");
    malicious_default.persistent = false;
    malicious_default.is_default = false;
    let repaired = store
        .upsert_browser_profile(malicious_default)
        .await
        .unwrap();
    assert!(repaired.persistent);
    assert!(repaired.is_default);

    let mut invalid = profile("invalid", "Invalid");
    invalid.is_default = true;
    assert!(store.upsert_browser_profile(invalid).await.is_err());

    store.ensure_default_browser_profile().await.unwrap();
    let error = store
        .remove_browser_profile(DEFAULT_BROWSER_PROFILE_ID)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("cannot be removed"));
}

#[tokio::test]
async fn history_is_newest_first_and_can_be_cleared_per_profile() {
    let (_dir, store) = store().await;
    let now = Utc::now();
    for (id, profile_id, offset) in [
        ("old", "work", -2),
        ("new", "work", 0),
        ("other", "personal", -1),
    ] {
        store
            .record_browser_history(BrowserHistoryEntry {
                id: id.to_string(),
                profile_id: profile_id.to_string(),
                workspace_id: Some(" workspace ".to_string()),
                tab_id: Some(" tab ".to_string()),
                url: format!(" https://example.com/{id} "),
                title: id.to_string(),
                visit_count: 1,
                visited_at: now + Duration::minutes(offset),
            })
            .await
            .unwrap();
    }

    let work = store.list_browser_history(Some("work"), 50).await.unwrap();
    assert_eq!(
        work.iter().map(|item| item.id.as_str()).collect::<Vec<_>>(),
        ["new", "old"]
    );
    assert_eq!(work[0].workspace_id.as_deref(), Some("workspace"));
    assert_eq!(work[0].url, "https://example.com/new");
    assert_eq!(store.clear_browser_history(Some("work")).await.unwrap(), 2);
    assert_eq!(store.list_browser_history(None, 50).await.unwrap().len(), 1);
}

#[tokio::test]
async fn session_store_sanitizes_sensitive_urls_at_the_persistence_boundary() {
    let (_dir, store) = store().await;
    let history = store
        .record_browser_history(BrowserHistoryEntry {
            id: "sensitive-history".to_string(),
            profile_id: "work".to_string(),
            workspace_id: None,
            tab_id: None,
            url: "https://example.com/callback?SAMLResponse=secret".to_string(),
            title: "Private Account".to_string(),
            visit_count: 1,
            visited_at: Utc::now(),
        })
        .await
        .unwrap();
    assert_eq!(history.url, "https://example.com/");
    assert!(history.title.is_empty());

    let closed = store
        .record_closed_browser_tab(BrowserClosedTab {
            id: "sensitive-closed".to_string(),
            profile_id: "work".to_string(),
            workspace_id: "workspace".to_string(),
            url: "https://example.com/?session_id=secret".to_string(),
            title: String::new(),
            payload: json!({
                "browserUrl": "https://example.com/?customAccessToken=secret",
                "browserRuntimeTitle": "Private Account",
            }),
            closed_at: Utc::now(),
        })
        .await
        .unwrap();
    assert_eq!(closed.url, "https://example.com/");
    assert_eq!(closed.payload["browserUrl"], json!("https://example.com/"));
    assert!(closed.payload.get("browserRuntimeTitle").is_none());

    assert!(store
        .record_browser_history(BrowserHistoryEntry {
            id: "local-history".to_string(),
            profile_id: "work".to_string(),
            workspace_id: None,
            tab_id: None,
            url: "file:///tmp/private".to_string(),
            title: String::new(),
            visit_count: 1,
            visited_at: Utc::now(),
        })
        .await
        .is_err());
}

#[tokio::test]
async fn history_deduplicates_by_profile_and_url_and_keeps_latest_two_hundred() {
    let (_dir, store) = store().await;
    let now = Utc::now();
    for index in 0..205 {
        store
            .record_browser_history(BrowserHistoryEntry {
                id: format!("entry-{index}"),
                profile_id: "work".to_string(),
                workspace_id: None,
                tab_id: None,
                url: format!("https://example.com/{index}"),
                title: index.to_string(),
                visit_count: 1,
                visited_at: now + Duration::seconds(index),
            })
            .await
            .unwrap();
    }
    let repeated = store
        .record_browser_history(BrowserHistoryEntry {
            id: "replacement-id".to_string(),
            profile_id: "work".to_string(),
            workspace_id: None,
            tab_id: None,
            url: "https://example.com/204".to_string(),
            title: "Repeated".to_string(),
            visit_count: 1,
            visited_at: now + Duration::seconds(500),
        })
        .await
        .unwrap();

    let history = store
        .list_browser_history(Some("work"), 1_000)
        .await
        .unwrap();
    assert_eq!(history.len(), 200);
    assert_eq!(repeated.id, "entry-204");
    assert_eq!(repeated.visit_count, 2);
    assert_eq!(history[0].title, "Repeated");
}

#[tokio::test]
async fn closed_tabs_keep_restore_payload_and_respect_limit() {
    let (_dir, store) = store().await;
    let now = Utc::now();
    for (id, offset) in [("older", -1), ("newer", 0)] {
        store
            .record_closed_browser_tab(BrowserClosedTab {
                id: id.to_string(),
                profile_id: "work".to_string(),
                workspace_id: "workspace".to_string(),
                url: format!("https://example.com/{id}"),
                title: id.to_string(),
                payload: json!({"zoom": 1.25}),
                closed_at: now + Duration::minutes(offset),
            })
            .await
            .unwrap();
    }

    let tabs = store
        .list_closed_browser_tabs(Some("work"), 1)
        .await
        .unwrap();
    assert_eq!(tabs.len(), 1);
    assert_eq!(tabs[0].id, "newer");
    assert_eq!(tabs[0].payload, json!({"zoom": 1.25}));
    assert!(store.remove_closed_browser_tab("newer").await.unwrap());
    assert!(!store.remove_closed_browser_tab("missing").await.unwrap());
}

#[tokio::test]
async fn closed_tabs_are_pruned_to_ten_globally_before_profile_filtering() {
    let (_dir, store) = store().await;
    let now = Utc::now();
    for index in 0..12 {
        let profile_id = if index % 2 == 0 { "work" } else { "personal" };
        store
            .record_closed_browser_tab(BrowserClosedTab {
                id: format!("closed-{index}"),
                profile_id: profile_id.to_string(),
                workspace_id: "workspace".to_string(),
                url: format!("https://example.com/{index}"),
                title: index.to_string(),
                payload: json!({}),
                closed_at: now + Duration::seconds(index),
            })
            .await
            .unwrap();
    }

    let all_tabs = store.list_closed_browser_tabs(None, 100).await.unwrap();
    assert_eq!(all_tabs.len(), 10);
    assert_eq!(all_tabs[0].id, "closed-11");
    assert_eq!(all_tabs[9].id, "closed-2");

    let work_tabs = store
        .list_closed_browser_tabs(Some("work"), 100)
        .await
        .unwrap();
    let personal_tabs = store
        .list_closed_browser_tabs(Some("personal"), 100)
        .await
        .unwrap();
    assert_eq!(work_tabs.len(), 5);
    assert_eq!(personal_tabs.len(), 5);
    assert!(work_tabs.iter().all(|tab| tab.profile_id == "work"));
    assert!(personal_tabs.iter().all(|tab| tab.profile_id == "personal"));

    let still_all_tabs = store.list_closed_browser_tabs(None, 100).await.unwrap();
    assert_eq!(still_all_tabs, all_tabs);
}

#[tokio::test]
async fn permissions_are_metadata_and_upsert_by_origin_and_kind() {
    let (_dir, store) = store().await;
    let now = Utc::now();
    let stored = store
        .upsert_browser_permission(BrowserPermission {
            profile_id: " work ".to_string(),
            origin: " HTTPS://Example.COM:443/ ".to_string(),
            permission: " camera ".to_string(),
            decision: BrowserPermissionDecision::Allow,
            updated_at: now,
        })
        .await
        .unwrap();

    assert_eq!(stored.profile_id, "work");
    assert_eq!(stored.origin, "https://example.com");
    assert_eq!(stored.permission, "camera");
    let permissions = store
        .list_browser_permissions(Some("work"), Some("https://EXAMPLE.com:443/"))
        .await
        .unwrap();
    assert_eq!(permissions.len(), 1);
    assert_eq!(permissions[0].decision, BrowserPermissionDecision::Allow);
    let port_scoped = store
        .upsert_browser_permission(BrowserPermission {
            profile_id: "work".to_string(),
            origin: "HTTP://LOCALHOST:8080/".to_string(),
            permission: "microphone".to_string(),
            decision: BrowserPermissionDecision::Deny,
            updated_at: now,
        })
        .await
        .unwrap();
    assert_eq!(port_scoped.origin, "http://localhost:8080");
    assert!(store
        .remove_browser_permission("work", " HTTPS://example.com:443 ", "camera")
        .await
        .unwrap());
}

#[tokio::test]
async fn permission_origins_reject_urls_that_are_not_exact_http_origins() {
    let (_dir, store) = store().await;
    let invalid_origins = [
        "",
        "about:blank",
        "ftp://example.com",
        "https://user@example.com",
        "https://example.com/path",
        "https://example.com?token=secret",
        "https://example.com#fragment",
        "https://example.com:",
        "https://example.com\\@evil.test",
    ];
    for origin in invalid_origins {
        let error = store
            .upsert_browser_permission(BrowserPermission {
                profile_id: "work".to_string(),
                origin: origin.to_string(),
                permission: "camera".to_string(),
                decision: BrowserPermissionDecision::Allow,
                updated_at: Utc::now(),
            })
            .await
            .unwrap_err();
        assert!(
            error.to_string().contains("HTTP(S) scheme"),
            "{origin:?} should be rejected: {error}"
        );
    }

    assert!(store
        .list_browser_permissions(Some("work"), Some("https://example.com/private"))
        .await
        .is_err());
    assert!(store
        .remove_browser_permission("work", "https://example.com?token=secret", "camera")
        .await
        .is_err());
}

#[tokio::test]
async fn removing_a_profile_cascades_browser_catalog_state() {
    let (_dir, store) = store().await;
    store
        .upsert_browser_profile(profile("work", "Work"))
        .await
        .unwrap();
    store
        .record_browser_history(BrowserHistoryEntry {
            id: "history".to_string(),
            profile_id: "work".to_string(),
            workspace_id: None,
            tab_id: None,
            url: "https://example.com".to_string(),
            title: String::new(),
            visit_count: 1,
            visited_at: Utc::now(),
        })
        .await
        .unwrap();
    store
        .upsert_browser_permission(BrowserPermission {
            profile_id: "work".to_string(),
            origin: "https://example.com".to_string(),
            permission: "notifications".to_string(),
            decision: BrowserPermissionDecision::Deny,
            updated_at: Utc::now(),
        })
        .await
        .unwrap();

    assert!(store.remove_browser_profile("work").await.unwrap());
    assert!(store
        .list_browser_history(Some("work"), 50)
        .await
        .unwrap()
        .is_empty());
    assert!(store
        .list_browser_permissions(Some("work"), None)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn profile_import_source_round_trips_without_arbitrary_templates() {
    let (_dir, store) = store().await;
    let mut imported = profile("imported", "Imported");
    imported.source = Some(BrowserProfileSource {
        family: BrowserProfileSourceFamily::Chrome,
        profile_name: Some("  Profile 1  ".to_string()),
        imported_at: Utc::now(),
    });

    let stored = store.upsert_browser_profile(imported).await.unwrap();
    let source = stored.source.unwrap();
    assert_eq!(source.family, BrowserProfileSourceFamily::Chrome);
    assert_eq!(source.profile_name.as_deref(), Some("Profile 1"));
}
