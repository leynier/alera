use super::*;

#[test]
fn context_compaction_lifecycle_reuses_one_timeline_cell() {
    let mut record = WorkspaceTabRecord {
        id: "tab".into(),
        workspace_id: "workspace".into(),
        kind: CODEX_TAB_KIND.into(),
        title: "Codex".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        payload: json!({}),
    };
    append_message(
        &mut record,
        json!({
            "method": "item/started",
            "params": {
                "turnId": "turn",
                "item": {
                    "id": "compact",
                    "type": "contextCompaction",
                    "title": "Context automatically compacting"
                }
            }
        }),
    );
    let active_snapshot = snapshot(&record);
    let active = active_snapshot["timelineCells"].as_array().unwrap();
    assert_eq!(active.len(), 1);
    assert_eq!(active[0]["title"], "Compacting");
    assert_eq!(active[0]["status"], "inProgress");
    assert_eq!(active[0]["isStreaming"], true);

    append_message(
        &mut record,
        json!({
            "method": "item/completed",
            "params": {
                "turnId": "turn",
                "item": {"id": "compact", "type": "contextCompaction"}
            }
        }),
    );
    append_message(
        &mut record,
        json!({"method": "thread/compacted", "params": {"turnId": "turn"}}),
    );
    let completed_snapshot = snapshot(&record);
    let completed = completed_snapshot["timelineCells"].as_array().unwrap();
    assert_eq!(completed.len(), 1);
    assert_eq!(completed[0]["id"], "item-compact");
    assert_eq!(completed[0]["title"], "Compacted");
    assert_eq!(completed[0]["status"], "completed");
    assert_eq!(completed[0]["isStreaming"], false);
}
