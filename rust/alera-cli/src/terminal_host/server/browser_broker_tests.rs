use std::collections::BTreeSet;

use serde_json::json;

use super::browser_broker::{
    BrowserBroker, BrowserCall, BrowserDriver, BrowserPage, BrowserPageChange,
    MAX_BROWSER_CALLS_PER_TAB,
};

fn driver(owner_client_id: u64) -> BrowserDriver {
    BrowserDriver {
        owner_client_id,
        app_instance_id: format!("app-{owner_client_id}"),
        driver_instance_id: format!("driver-{owner_client_id}"),
        engine: "webview".to_string(),
        platform: "test".to_string(),
        capabilities: BTreeSet::new(),
    }
}

fn page(owner_client_id: u64, tab_id: &str) -> BrowserPage {
    BrowserPage {
        tab_id: tab_id.to_string(),
        workspace_id: "workspace-1".to_string(),
        profile_id: "default".to_string(),
        generation: 0,
        document_generation: 7,
        url: Some("https://example.com/".to_string()),
        title: Some("Example".to_string()),
        capabilities: BTreeSet::new(),
        owner_client_id,
    }
}

fn call(correlation_id: impl Into<String>, owner_client_id: u64, generation: u64) -> BrowserCall {
    call_for_tab(
        correlation_id,
        owner_client_id,
        generation,
        "tab-1",
        "browser.snapshot",
    )
}

fn call_for_tab(
    correlation_id: impl Into<String>,
    owner_client_id: u64,
    generation: u64,
    tab_id: &str,
    request_type: &str,
) -> BrowserCall {
    BrowserCall {
        correlation_id: correlation_id.into(),
        requester_client_id: 90,
        requester_request_id: 12,
        owner_client_id,
        request_type: request_type.to_string(),
        tab_id: tab_id.to_string(),
        generation,
        params: json!({"pageId": tab_id}),
        deadline_at_ms: 10_000,
    }
}

fn broker_with_page() -> (BrowserBroker, BrowserPage) {
    let mut broker = BrowserBroker::default();
    broker.register_driver(driver(1));
    let (page, drain) = broker.sync_page(1, page(1, "tab-1")).unwrap();
    assert!(drain.removed.is_empty());
    (broker, page)
}

#[test]
fn one_call_per_tab_runs_and_the_rest_are_fifo() {
    let (mut broker, page) = broker_with_page();
    let first = broker.enqueue(call("first", 1, page.generation)).unwrap();
    let second = broker.enqueue(call("second", 1, page.generation)).unwrap();
    let third = broker.enqueue(call("third", 1, page.generation)).unwrap();

    assert!(first.dispatch_now);
    assert!(!second.dispatch_now);
    assert!(!third.dispatch_now);
    let completion = broker
        .complete(1, "first", "tab-1", page.generation)
        .unwrap();
    assert_eq!(
        completion.promoted.unwrap().correlation_id,
        "second",
        "the oldest queued call must run next"
    );
    let completion = broker
        .complete(1, "second", "tab-1", page.generation)
        .unwrap();
    assert_eq!(completion.promoted.unwrap().correlation_id, "third");
}

#[test]
fn per_tab_queue_is_bounded() {
    let (mut broker, page) = broker_with_page();
    for index in 0..MAX_BROWSER_CALLS_PER_TAB {
        broker
            .enqueue(call(format!("call-{index}"), 1, page.generation))
            .unwrap();
    }
    let error = broker
        .enqueue(call("overflow", 1, page.generation))
        .unwrap_err();
    assert_eq!(error.code, "queue_full");
    assert!(error.retryable);
}

#[test]
fn a_page_has_one_connection_owner() {
    let (mut broker, _) = broker_with_page();
    broker.register_driver(driver(2));
    let error = broker.sync_page(2, page(2, "tab-1")).unwrap_err();
    assert_eq!(error.code, "page_owned");
    assert!(!error.retryable);
}

#[test]
fn unchanged_full_sync_preserves_generations_and_active_calls() {
    let (mut broker, first_page) = broker_with_page();
    broker
        .enqueue(call("active", 1, first_page.generation))
        .unwrap();

    let mut refreshed_first = page(1, "tab-1");
    refreshed_first.title = Some("Updated Metadata".to_string());
    let (refreshed_first, drain) = broker.sync_page(1, refreshed_first).unwrap();
    assert_eq!(refreshed_first.generation, first_page.generation);
    assert_eq!(refreshed_first.title.as_deref(), Some("Updated Metadata"));
    assert!(drain.removed.is_empty());

    let (second_page, drain) = broker.sync_page(1, page(1, "tab-2")).unwrap();
    assert!(drain.removed.is_empty());
    assert_ne!(second_page.generation, first_page.generation);
    broker
        .complete(1, "active", "tab-1", first_page.generation)
        .unwrap();
}

#[test]
fn syncing_a_changed_document_does_not_cancel_another_page() {
    let (mut broker, first_page) = broker_with_page();
    let (second_page, _) = broker.sync_page(1, page(1, "tab-2")).unwrap();
    broker
        .enqueue(call("first", 1, first_page.generation))
        .unwrap();
    broker
        .enqueue(call_for_tab(
            "second",
            1,
            second_page.generation,
            "tab-2",
            "browser.snapshot",
        ))
        .unwrap();

    let mut changed_first = page(1, "tab-1");
    changed_first.document_generation = 8;
    let (changed_first, drain) = broker.sync_page(1, changed_first).unwrap();

    assert_ne!(changed_first.generation, first_page.generation);
    assert_eq!(drain.removed.len(), 1);
    assert_eq!(drain.removed[0].call.correlation_id, "first");
    broker
        .complete(1, "second", "tab-2", second_page.generation)
        .unwrap();
}

#[test]
fn metadata_updates_keep_generation_but_document_updates_invalidate_calls() {
    let (mut broker, page) = broker_with_page();
    broker.enqueue(call("active", 1, page.generation)).unwrap();

    let (metadata_page, drain, invalidated, preserved_navigation) = broker
        .change_page(
            1,
            "tab-1",
            BrowserPageChange {
                expected_generation: page.generation,
                profile_id: None,
                document_generation: Some(7),
                document_changed: false,
                navigation_correlation_id: None,
                url_changed: true,
                url: Some("https://example.com/next".to_string()),
                title: Some("Next".to_string()),
            },
        )
        .unwrap();
    assert!(!invalidated);
    assert!(preserved_navigation.is_none());
    assert_eq!(metadata_page.generation, page.generation);
    assert!(drain.removed.is_empty());

    let (document_page, drain, invalidated, preserved_navigation) = broker
        .change_page(
            1,
            "tab-1",
            BrowserPageChange {
                expected_generation: page.generation,
                profile_id: None,
                document_generation: Some(8),
                document_changed: true,
                navigation_correlation_id: Some("active".to_string()),
                url_changed: true,
                url: Some("https://example.com/document".to_string()),
                title: None,
            },
        )
        .unwrap();
    assert!(invalidated);
    assert!(preserved_navigation.is_none());
    assert!(document_page.generation > page.generation);
    assert_eq!(drain.removed.len(), 1);
    assert!(drain.removed[0].was_in_flight);
    assert_eq!(
        broker
            .complete(1, "active", "tab-1", page.generation)
            .unwrap_err()
            .code,
        "stale_response"
    );
}

#[test]
fn document_change_rebases_the_navigation_that_started_it() {
    let (mut broker, page) = broker_with_page();
    broker
        .enqueue(call_for_tab(
            "navigation",
            1,
            page.generation,
            "tab-1",
            "browser.navigate",
        ))
        .unwrap();
    broker
        .enqueue(call("queued-snapshot", 1, page.generation))
        .unwrap();

    let (changed_page, drain, invalidated, preserved_navigation) = broker
        .change_page(
            1,
            "tab-1",
            BrowserPageChange {
                expected_generation: page.generation,
                profile_id: None,
                document_generation: Some(8),
                document_changed: true,
                navigation_correlation_id: Some("navigation".to_string()),
                url_changed: true,
                url: Some("https://example.com/next".to_string()),
                title: None,
            },
        )
        .unwrap();

    assert!(invalidated);
    assert_eq!(preserved_navigation.as_deref(), Some("navigation"));
    assert_ne!(changed_page.generation, page.generation);
    assert_eq!(drain.removed.len(), 1);
    assert_eq!(drain.removed[0].call.correlation_id, "queued-snapshot");
    assert!(!drain.removed[0].was_in_flight);
    assert_eq!(
        broker.call("navigation").unwrap().generation,
        changed_page.generation
    );
    broker
        .complete(1, "navigation", "tab-1", changed_page.generation)
        .unwrap();
}

#[test]
fn navigation_can_complete_before_its_document_change_is_reported() {
    let (mut broker, page) = broker_with_page();
    broker
        .enqueue(call_for_tab(
            "navigation",
            1,
            page.generation,
            "tab-1",
            "browser.reload",
        ))
        .unwrap();
    broker
        .complete(1, "navigation", "tab-1", page.generation)
        .unwrap();

    let (changed_page, drain, invalidated, preserved_navigation) = broker
        .change_page(
            1,
            "tab-1",
            BrowserPageChange {
                expected_generation: page.generation,
                profile_id: None,
                document_generation: Some(8),
                document_changed: true,
                navigation_correlation_id: Some("navigation".to_string()),
                url_changed: false,
                url: None,
                title: None,
            },
        )
        .unwrap();

    assert!(invalidated);
    assert!(preserved_navigation.is_none());
    assert_ne!(changed_page.generation, page.generation);
    assert!(drain.removed.is_empty());
}

#[test]
fn deadlines_and_disconnects_release_active_jobs() {
    let (mut broker, page) = broker_with_page();
    let mut expired = call("expired", 1, page.generation);
    expired.deadline_at_ms = 50;
    broker.enqueue(expired).unwrap();
    assert_eq!(broker.expired_correlations(50), ["expired"]);

    let drain = broker.remove_driver(1);
    assert_eq!(drain.removed.len(), 1);
    assert_eq!(broker.active_jobs(), 0);
    assert!(broker.page("tab-1").is_none());
}
