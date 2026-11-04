use muse_agent_sdk::SessionState;
use serde_json::json;

#[test]
fn fold_keeps_newer_item_revisions_and_records_view_gaps() {
    let mut state = SessionState::default();
    state.apply(
        "item/updated",
        &json!({
            "sessionId":"session-1",
            "viewCursor":"v:2",
            "item":{"itemId":"item-1","revision":2,"status":"running","kind":"agentMessage","text":"new"}
        }),
    );
    state.apply(
        "item/updated",
        &json!({
            "sessionId":"session-1",
            "viewCursor":"v:1",
            "item":{"itemId":"item-1","revision":1,"status":"running","kind":"agentMessage","text":"old"}
        }),
    );
    state.apply(
        "view/gap",
        &json!({"sessionId":"session-1","after":"v:2","next":"v:9"}),
    );
    assert_eq!(state.items["item-1"].revision, 2);
    assert_eq!(state.items["item-1"].value["text"], "new");
    assert_eq!(state.gap, Some(("v:2".into(), "v:9".into())));
    assert_eq!(state.raw_events.len(), 3);
}
