use super::*;

fn task(id: &str, subject: &str, status: TaskStatus) -> ClaudeTask {
    ClaudeTask {
        id: id.into(),
        subject: subject.into(),
        status,
        active_form: None,
        blocked_by: Vec::new(),
    }
}

#[test]
fn created_text_reads_its_id_and_subject() {
    assert_eq!(
        created_from_text(&json!("Task #12 created successfully: Fix it\nand test")),
        Some(("12".into(), "Fix it\nand test".into()))
    );
    for text in [
        json!("Task #12 created successfully:   "),
        json!("Task # created successfully: X"),
        json!("Created task #1"),
        json!({"task": "x"}),
    ] {
        assert_eq!(created_from_text(&text), None, "{text}");
    }
}

#[test]
fn list_ids_are_sanitized_as_the_cli_does() {
    assert_eq!(sanitize("list/ID"), "list-ID");
    assert_eq!(sanitize("é"), "-");
    assert_eq!(sanitize("🙂"), "--");
    assert_eq!(sanitize("a_b-9"), "a_b-9");
}

#[test]
fn stored_tasks_read_in_numeric_order() {
    let dir = std::env::temp_dir().join(format!("alera-claude-tasks-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    for (name, id) in [("10.json", "10"), ("2.json", "2")] {
        let task = json!({"id": id, "subject": format!("Task {id}"), "status": "pending"});
        std::fs::write(dir.join(name), task.to_string()).unwrap();
    }
    std::fs::write(dir.join("notes.json"), "{}").unwrap();
    let tasks = read_stored(&dir).unwrap();
    assert_eq!(
        tasks
            .iter()
            .map(|task| task.id.as_str())
            .collect::<Vec<_>>(),
        ["2", "10"]
    );
    std::fs::remove_dir_all(&dir).unwrap();
    assert_eq!(read_stored(&dir), None);
}

#[test]
fn a_replaced_task_keeps_its_place() {
    let tasks = vec![
        task("1", "One", TaskStatus::Pending),
        task("2", "Two", TaskStatus::Pending),
    ];
    let next = apply(
        &tasks,
        "TaskCreate",
        &json!({}),
        &json!({"task": {"id": "1", "subject": "Again"}}),
    )
    .unwrap();
    assert_eq!(next[0].subject, "Again");
    assert_eq!(next[1].id, "2");
    let unchanged = apply(
        &next,
        "TaskUpdate",
        &json!({"taskId": "2", "status": "pending"}),
        &json!({"success": true}),
    );
    assert_eq!(unchanged, None);
}
