use super::*;

#[test]
fn resume_reconciles_legacy_turn_based_user_message_ids() {
    let stored = json!({
        "events": [],
        "timelineCells": [{
            "id": "user-turn-1",
            "turnId": "turn-1",
            "kind": "userMessage",
            "createdAt": "2026-08-08T10:00:00Z",
            "markdownText": "Review this file",
            "metadata": {
                "attachments": [{"path": "/tmp/report.csv"}],
                "clientUserMessageId": "client-1"
            }
        }],
        "pendingRequests": [],
    });
    let resumed = json!({
        "events": [],
        "timelineCells": [{
            "id": "user-client-1",
            "turnId": "turn-1",
            "kind": "userMessage",
            "createdAt": "2026-08-08T10:00:01Z",
            "markdownText": "/tmp/report.csv Review this file",
            "metadata": {"itemType": "userMessage"}
        }],
        "pendingRequests": [],
    });

    let merged = merge_resume_snapshot(&stored, resumed);
    let cells = merged["timelineCells"].as_array().unwrap();

    assert_eq!(cells.len(), 1);
    assert_eq!(cells[0]["id"], "user-client-1");
    assert_eq!(cells[0]["markdownText"], "Review this file");
    assert_eq!(cells[0]["metadata"]["clientUserMessageId"], "client-1");
    assert_eq!(
        cells[0]["metadata"]["attachments"][0]["path"],
        "/tmp/report.csv"
    );
}
