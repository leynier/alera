use super::{TrackedToolCalls, TRACKED_CALL_LIMIT};
use serde_json::{json, Value};

fn request(id: &str) -> Value {
    json!({"sessionId":"root","toolCall":{"toolCallId":id}})
}

#[test]
fn id_only_requests_take_the_tracked_title_input_and_command_kind() {
    let mut tracked = TrackedToolCalls::default();
    tracked.observe(
        "root",
        Some("t1"),
        &json!({"toolCallId":"c1","kind":"execute","status":"pending","title":"Run ls"}),
    );
    tracked.observe(
        "root",
        Some("t1"),
        &json!({"toolCallId":"c1","status":"in_progress","rawInput":{"command":"ls -la"}}),
    );
    let mut params = request("c1");
    tracked.enrich("root", Some("t1"), &mut params);
    assert_eq!(
        params["toolCall"],
        json!({"toolCallId":"c1","title":"Run ls","kind":"execute","rawInput":{"command":"ls -la"}})
    );
}

#[test]
fn sent_fields_are_kept_and_other_kinds_are_not_filled() {
    let mut tracked = TrackedToolCalls::default();
    tracked.observe(
        "root",
        None,
        &json!({"toolCallId":"c1","kind":"edit","title":"Edit","rawInput":{"path":"a"}}),
    );
    let mut params = json!({"toolCall":{"toolCallId":"c1","title":null}});
    tracked.enrich("root", None, &mut params);
    assert_eq!(
        params["toolCall"],
        json!({"toolCallId":"c1","title":null,"rawInput":{"path":"a"}})
    );
}

#[test]
fn other_sessions_turns_and_settled_calls_are_not_enriched() {
    let mut tracked = TrackedToolCalls::default();
    tracked.observe(
        "root",
        Some("t1"),
        &json!({"toolCallId":"c1","kind":"execute"}),
    );
    for (session, turn) in [("child", Some("t1")), ("root", Some("t2"))] {
        let mut params = request("c1");
        tracked.enrich(session, turn, &mut params);
        assert_eq!(params, request("c1"));
    }
    for status in ["completed", "failed", "cancelled"] {
        tracked.observe(
            "root",
            Some("t1"),
            &json!({"toolCallId":"c1","kind":"execute"}),
        );
        tracked.observe(
            "root",
            Some("t1"),
            &json!({"toolCallId":"c1","status":status}),
        );
        let mut params = request("c1");
        tracked.enrich("root", Some("t1"), &mut params);
        assert_eq!(params, request("c1"), "{status}");
    }
    tracked.observe(
        "root",
        Some("t1"),
        &json!({"toolCallId":"c1","kind":"execute"}),
    );
    tracked.observe(
        "root",
        Some("t2"),
        &json!({"toolCallId":"c2","kind":"execute"}),
    );
    let mut params = request("c1");
    tracked.enrich("root", Some("t2"), &mut params);
    assert_eq!(params, request("c1"));
}

#[test]
fn the_tracker_keeps_the_newest_calls_within_its_bound() {
    let mut tracked = TrackedToolCalls::default();
    for index in 0..=TRACKED_CALL_LIMIT {
        tracked.observe(
            "root",
            None,
            &json!({"toolCallId":format!("c{index}"),"kind":"execute"}),
        );
    }
    assert_eq!(tracked.calls.len(), TRACKED_CALL_LIMIT);
    let mut oldest = request("c0");
    tracked.enrich("root", None, &mut oldest);
    assert_eq!(oldest, request("c0"));
    let mut newest = request(&format!("c{TRACKED_CALL_LIMIT}"));
    tracked.enrich("root", None, &mut newest);
    assert_eq!(newest["toolCall"]["kind"], "execute");
    tracked.reset();
    let mut reset = request(&format!("c{TRACKED_CALL_LIMIT}"));
    tracked.enrich("root", None, &mut reset);
    assert!(reset["toolCall"].get("kind").is_none());
}
