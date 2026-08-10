use super::*;

#[test]
fn thread_history_cache_reuses_and_bounds_projected_histories() {
    let mut cache = ThreadHistoryCache::default();
    let mut newest_cursor = None;
    for index in 0..=MAX_CACHED_THREAD_HISTORIES {
        newest_cursor = cache
            .insert(
                &format!("thread-{index}"),
                &history_response(index, 2, 8),
                1,
                None,
                None,
                None,
            )
            .and_then(|page| page.next_cursor);
    }

    assert_eq!(cache.entries.len(), MAX_CACHED_THREAD_HISTORIES);
    assert!(!cache.entries.contains_key("thread-0"));
    assert_eq!(
        cache
            .get(
                &format!("thread-{MAX_CACHED_THREAD_HISTORIES}"),
                newest_cursor.as_deref().unwrap(),
                1,
            )
            .unwrap()
            .turns[0]["id"],
        format!("turn-{MAX_CACHED_THREAD_HISTORIES}-0")
    );
}

#[test]
fn oversized_thread_history_retains_bounded_pages_without_a_reread_gap() {
    let mut cache = ThreadHistoryCache::default();
    let response = history_response(1, 80, 128 * 1024);
    cache.insert(
        "thread-1",
        &response,
        1,
        Some("page-head"),
        Some("page-older"),
        None,
    );

    assert!(cache.total_bytes <= MAX_CACHED_THREAD_HISTORY_BYTES);
    let entry = cache.entries.get("thread-1").unwrap();
    assert!(!entry.pages.is_empty());
    assert!(entry.pages.len() < 79);
    assert!(entry.pages.values().all(|page| page.next_cursor.is_some()));
    let uncached_cursor = entry
        .pages
        .values()
        .filter_map(|page| page.next_cursor.as_deref())
        .find(|cursor| !entry.pages.contains_key(*cursor))
        .unwrap();
    let decoded = decode_history_cursor(uncached_cursor).unwrap();
    let local_cursor = decoded.local_cursor.as_deref().unwrap();

    let reconstructed = project_local_history_page(
        &response,
        local_cursor,
        1,
        decoded.page_cursor.as_deref(),
        Some("page-older"),
        None,
    )
    .unwrap()
    .0;
    assert_eq!(reconstructed.turns.len(), 1);
    assert!(reconstructed.next_cursor.is_some());
}

#[test]
fn oversized_legacy_history_does_not_publish_an_uncached_cursor() {
    let mut cache = ThreadHistoryCache::default();
    let response = history_response(1, 80, 128 * 1024);
    let latest = cache
        .insert("thread-1", &response, 1, None, None, None)
        .unwrap();

    assert!(cache.total_bytes <= MAX_CACHED_THREAD_HISTORY_BYTES);
    let entry = cache.entries.get("thread-1").unwrap();
    assert!(!entry.pages.is_empty());
    assert!(entry.pages.len() < 79);
    assert!(latest
        .next_cursor
        .as_deref()
        .is_some_and(|cursor| entry.pages.contains_key(cursor)));
    for page in entry.pages.values() {
        assert!(page
            .next_cursor
            .as_deref()
            .is_none_or(|cursor| entry.pages.contains_key(cursor)));
    }
    assert!(entry.pages.values().any(|page| page.next_cursor.is_none()));
}

#[test]
fn native_turn_pages_are_reversed_and_chain_after_local_pages() {
    let response = json!({
        "data": [
            completed_turn("turn-new"),
            completed_turn("turn-old"),
        ],
        "nextCursor": "native-older",
    });
    let projected = turns_list_history_response(&response, None).unwrap();
    let mut cache = ThreadHistoryCache::default();

    let latest = cache
        .insert(
            "thread-1",
            &projected,
            1,
            Some("native-head"),
            Some("native-older"),
            None,
        )
        .unwrap();
    assert_eq!(latest.turns[0]["id"], "turn-new");
    let local_cursor = latest.next_cursor.unwrap();
    let older = cache.get("thread-1", &local_cursor, 1).unwrap();
    assert_eq!(older.turns[0]["id"], "turn-old");
    let continuation = decode_history_cursor(older.next_cursor.as_deref().unwrap()).unwrap();
    assert_eq!(continuation.page_cursor.as_deref(), Some("native-older"));
    assert!(continuation.local_cursor.is_none());
}

#[test]
fn native_review_overlap_keeps_the_envelope_and_worker_together() {
    let response = json!({
        "thread": {"turns": [
            {
                "id": "review-envelope",
                "status": "completed",
                "items": [
                    {"id": "entry", "type": "enteredReviewMode", "review": "current changes"},
                    {"id": "exit", "type": "exitedReviewMode", "review": "No findings."}
                ]
            },
            {
                "id": "review-worker",
                "status": "completed",
                "items": [
                    {"id": "user-1", "type": "userMessage", "clientId": null,
                     "content": [{"type": "text", "text": "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."}]},
                    {"id": "user-2", "type": "userMessage", "clientId": null,
                     "content": [{"type": "text", "text": "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."}]}
                ]
            }
        ]}
    });

    let page = latest_turn_page(&response, 20).unwrap();
    assert_eq!(page.turns.len(), 1);
    assert_eq!(page.turns[0]["id"], "review-envelope");
    assert_eq!(
        page.turns[0]["items"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|item| item["type"] == "userMessage")
            .count(),
        1
    );
}

#[test]
fn native_review_boundary_requests_the_older_envelope() {
    let worker = json!({
        "id": "review-worker",
        "items": [
            {"type": "userMessage", "clientId": null,
             "content": [{"type": "text", "text": "Review the changes."}]},
            {"type": "userMessage", "clientId": null,
             "content": [{"type": "text", "text": "Review the changes."}]}
        ]
    });
    assert_eq!(
        review_boundary_cursor(&[completed_turn("newer"), worker], Some("older-page")),
        Some("older-page")
    );
    assert_eq!(
        review_boundary_cursor(&[completed_turn("ordinary")], Some("older-page")),
        None
    );
}

#[test]
fn failed_review_boundary_fetch_keeps_the_usable_page_and_cursor() {
    let turns = vec![completed_turn("newer"), completed_turn("review-worker")];

    let (kept, cursor) =
        merge_review_boundary_response(turns.clone(), "native-older".to_string(), None);

    assert_eq!(kept, turns);
    assert_eq!(cursor.as_deref(), Some("native-older"));
}

#[test]
fn resumed_history_prefers_the_requested_initial_turn_page() {
    let response = json!({
        "thread": {"turns": [completed_turn("partial-live")]},
        "turnsBackwardsCursor": "native-before-initial",
        "initialTurnsPage": {
            "data": [completed_turn("turn-new"), completed_turn("turn-old")],
            "nextCursor": "native-older",
        },
    });

    let projected = resume_history_response(&response).unwrap();
    assert_eq!(projected["thread"]["turns"][0]["id"], "turn-old");
    assert_eq!(projected["thread"]["turns"][1]["id"], "turn-new");

    let mut cache = ThreadHistoryCache::default();
    assert_eq!(
        resumed_history_continuation(&response),
        (Some("native-older"), None)
    );
    let latest = cache
        .insert(
            "thread-1",
            &projected,
            1,
            None,
            resumed_history_continuation(&response).0,
            resumed_history_continuation(&response).1,
        )
        .unwrap();
    let local_cursor = decode_history_cursor(latest.next_cursor.as_deref().unwrap()).unwrap();
    assert!(local_cursor.page_cursor.is_none());
    assert!(local_cursor.local_cursor.is_some());
}

#[test]
fn resumed_paginated_history_preserves_the_backwards_cursor() {
    let response = json!({
        "thread": {
            "historyMode": "paginated",
            "turns": [completed_turn("turn-new")],
        },
        "turnsBackwardsCursor": "native-older",
    });
    let projected = resume_history_response(&response).unwrap();
    let mut cache = ThreadHistoryCache::default();

    let latest = cache
        .insert(
            "thread-1",
            &projected,
            20,
            None,
            resumed_history_continuation(&response).0,
            resumed_history_continuation(&response).1,
        )
        .unwrap();

    assert_eq!(latest.turns[0]["id"], "turn-new");
    let continuation = decode_history_cursor(latest.next_cursor.as_deref().unwrap()).unwrap();
    assert_eq!(continuation.page_cursor.as_deref(), Some("native-older"));
    assert_eq!(continuation.inclusive_turn_id.as_deref(), Some("turn-new"));
    assert!(continuation.local_cursor.is_none());
}

#[test]
fn fallback_resume_reverses_turns_for_review_boundary_completion() {
    let response = json!({
        "thread": {
            "turns": [
                {
                    "id": "review-worker",
                    "status": "inProgress",
                    "items": [
                        {"type": "userMessage", "clientId": null,
                         "content": [{"type": "text", "text": "Review the changes."}]},
                        {"type": "userMessage", "clientId": null,
                         "content": [{"type": "text", "text": "Review the changes."}]}
                    ]
                },
                completed_turn("turn-new")
            ],
        },
        "turnsBackwardsCursor": "native-before-worker",
    });

    let turns = resumed_history_boundary_turns(&response).unwrap();

    assert_eq!(turns[0]["id"], "turn-new");
    assert_eq!(turns[1]["id"], "review-worker");
    assert_eq!(
        review_boundary_cursor(&turns, Some("native-before-worker")),
        Some("native-before-worker")
    );
    assert_eq!(
        resumed_history_continuation(&response),
        (Some("native-before-worker"), Some("review-worker"))
    );
    assert_eq!(review_boundary_fetch_limit(Some("review-worker")), 2);
    assert_eq!(review_boundary_fetch_limit(None), 1);
}

#[test]
fn inclusive_resume_cursor_filters_the_already_projected_boundary_turn() {
    let response = json!({
        "data": [
            completed_turn("turn-new"),
            completed_turn("turn-old"),
        ],
        "nextCursor": "native-older",
    });

    let projected = turns_list_history_response(&response, Some("turn-new")).unwrap();

    assert_eq!(projected["thread"]["turns"].as_array().unwrap().len(), 1);
    assert_eq!(projected["thread"]["turns"][0]["id"], "turn-old");
}

#[test]
fn resumed_history_accepts_stable_thread_turns_without_reordering_them() {
    let response = json!({
        "thread": {
            "turns": [completed_turn("turn-old"), completed_turn("turn-new")],
        },
    });

    let projected = resume_history_response(&response).unwrap();

    assert_eq!(projected["thread"]["turns"][0]["id"], "turn-old");
    assert_eq!(projected["thread"]["turns"][1]["id"], "turn-new");
}

#[test]
fn uncached_local_history_cursor_requires_a_fresh_resume() {
    let cursor = encode_history_cursor(AppServerHistoryCursor {
        page_cursor: None,
        local_cursor: Some("turn-before:turn-old".to_string()),
        next_page_cursor: Some("native-older".to_string()),
        inclusive_turn_id: None,
    });

    let decoded = decode_history_cursor(&cursor).unwrap();

    assert_eq!(
        native_page_cursor(&decoded),
        Err("Codex history cursor expired. Reload the conversation and try again.")
    );
}

fn history_response(thread: usize, turns: usize, text_bytes: usize) -> Value {
    json!({
        "thread": {
            "turns": (0..turns)
                .map(|turn| json!({
                    "id": format!("turn-{thread}-{turn}"),
                    "status": "completed",
                    "items": [{
                        "id": format!("item-{thread}-{turn}"),
                        "type": "userMessage",
                        "content": [{"type": "text", "text": "x".repeat(text_bytes)}],
                    }],
                }))
                .collect::<Vec<_>>()
        }
    })
}

fn completed_turn(id: &str) -> Value {
    json!({
        "id": id,
        "status": "completed",
        "items": [{
            "id": format!("item-{id}"),
            "type": "userMessage",
            "content": [{"type": "text", "text": id}],
        }],
    })
}
