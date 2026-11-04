mod skill_fixtures;
mod support;

use alera_provider_protocol::{EventKind, Provider, SessionStartInput, TurnInput};
use serde_json::{json, Value};
use skill_fixtures::{config, mkdir, write, TempDir};
use support::*;

fn call(id: &str, name: &str, input: Value, parent: Option<&str>) -> Value {
    json!({
        "type": "assistant",
        "session_id": "native-session",
        "parent_tool_use_id": parent,
        "message": {
            "id": format!("message-{id}"),
            "content": [{"type": "tool_use", "id": id, "name": name, "input": input}]
        }
    })
}

fn result(id: &str, content: Value, structured: Option<Value>) -> Value {
    let mut frame = json!({
        "type": "user",
        "session_id": "native-session",
        "message": {
            "role": "user",
            "content": [{"type": "tool_result", "tool_use_id": id, "content": content}]
        }
    });
    if let Some(structured) = structured {
        frame["tool_use_result"] = structured;
    }
    frame
}

fn create(id: &str, task: &str, subject: &str) -> Vec<Value> {
    vec![
        call(id, "TaskCreate", json!({"subject": subject}), None),
        result(
            id,
            json!(format!("Task #{task} created successfully: {subject}")),
            Some(json!({"task": {"id": task, "subject": subject}})),
        ),
    ]
}

fn update(id: &str, input: Value) -> Vec<Value> {
    vec![
        call(id, "TaskUpdate", input, None),
        result(id, json!("Updated task"), Some(json!({"success": true}))),
    ]
}

/// The `plan` of each plan update in one turn.
async fn turn_plans(
    frames: Vec<Value>,
    provider_config: alera_provider_claude::ClaudeProviderConfig,
    resume: Option<&str>,
) -> Vec<Value> {
    let mut incoming = vec![initialize_response()];
    incoming.extend(frames);
    incoming.push(result_message(false, None));
    let mut session = SessionStartInput::new("app-thread");
    session.resume_thread_id = resume.map(str::to_owned);
    let (mut provider, _handle) =
        started_provider_with_config(incoming, provider_config, session).await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "tasks"))
        .await
        .unwrap();
    let mut plans = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::TurnPlanUpdated {
            plans.push(event.payload["plan"].clone());
        }
        if event.kind == EventKind::TurnCompleted {
            return plans;
        }
    }
}

fn steps(plan: &Value) -> Vec<(String, String, String)> {
    plan.as_array()
        .unwrap()
        .iter()
        .map(|step| {
            (
                step["id"].as_str().unwrap().to_owned(),
                step["content"].as_str().unwrap().to_owned(),
                step["status"].as_str().unwrap().to_owned(),
            )
        })
        .collect()
}

fn step(id: &str, content: &str, status: &str) -> (String, String, String) {
    (id.into(), content.into(), status.into())
}

#[tokio::test]
async fn task_create_and_update_project_the_whole_list() {
    let mut frames = create("t1", "1", "Inspect");
    frames.extend(create("t2", "2", "Implement"));
    frames.extend(update(
        "t3",
        json!({"taskId": "1", "status": "in_progress"}),
    ));
    frames.extend(update(
        "t4",
        json!({"taskId": "1", "subject": "Inspected", "status": "completed"}),
    ));
    frames.extend(update("t5", json!({"taskId": "2", "status": "deleted"})));
    frames.extend(update("t6", json!({"taskId": "2", "status": "pending"})));
    let plans = turn_plans(frames, isolated_config(), None).await;
    assert_eq!(plans.len(), 5);
    assert_eq!(
        steps(&plans[2]),
        [
            step("1", "Inspect", "in_progress"),
            step("2", "Implement", "pending")
        ]
    );
    assert_eq!(
        steps(&plans[3]),
        [
            step("1", "Inspected", "completed"),
            step("2", "Implement", "pending")
        ]
    );
    // A deleted task never comes back.
    assert_eq!(steps(&plans[4]), [step("1", "Inspected", "completed")]);
}

#[tokio::test]
async fn task_list_replaces_the_list_and_failed_updates_change_nothing() {
    let mut frames = create("t1", "1", "Inspect");
    frames.push(call("t2", "TaskList", json!({}), None));
    frames.push(result(
        "t2",
        json!("listed"),
        Some(json!({"tasks": [{"id": "7", "subject": "Listed", "status": "pending"}]})),
    ));
    frames.push(call(
        "t3",
        "TaskUpdate",
        json!({"taskId": "7", "status": "completed"}),
        None,
    ));
    frames.push(result("t3", json!("nope"), Some(json!({"success": false}))));
    let mut errored = result("t4", json!("boom"), None);
    errored["message"]["content"][0]["is_error"] = json!(true);
    frames.push(call(
        "t4",
        "TaskUpdate",
        json!({"taskId": "7", "status": "completed"}),
        None,
    ));
    frames.push(errored);
    frames.push(call("t5", "TaskList", json!({}), None));
    frames.push(result("t5", json!("listed"), Some(json!({"tasks": []}))));
    let plans = turn_plans(frames, isolated_config(), None).await;
    assert_eq!(plans.len(), 3);
    assert_eq!(steps(&plans[1]), [step("7", "Listed", "pending")]);
    assert_eq!(plans[2], json!([]));
}

#[tokio::test]
async fn subagent_task_tools_update_the_shared_list() {
    let mut frames = create("t1", "1", "Main task");
    frames.push(call(
        "s1",
        "TaskCreate",
        json!({"subject": "Child task"}),
        Some("agent"),
    ));
    frames.push(result(
        "s1",
        json!([{"type": "text", "text": "Task #2 created successfully: Child task"}]),
        None,
    ));
    frames.push(call(
        "s2",
        "TaskUpdate",
        json!({"taskId": "1", "status": "completed"}),
        Some("agent"),
    ));
    frames.push(result("s2", json!("Updated task #1 status"), None));
    frames.push(call(
        "s3",
        "TaskUpdate",
        json!({"taskId": "2", "status": "completed"}),
        Some("agent"),
    ));
    frames.push(result(
        "s3",
        json!("Tests must pass before completing."),
        None,
    ));
    let plans = turn_plans(frames, isolated_config(), None).await;
    assert_eq!(plans.len(), 3);
    assert_eq!(
        steps(&plans[2]),
        [
            step("1", "Main task", "completed"),
            step("2", "Child task", "pending")
        ]
    );
}

#[tokio::test]
async fn the_first_task_tool_after_a_restart_reads_claudes_store() {
    let home = TempDir::new();
    let tasks = home.join("tasks").join("native-session");
    mkdir(&tasks);
    let stored = |id: &str, subject: &str, status: &str| {
        json!({"id": id, "subject": subject, "status": status}).to_string()
    };
    write(&tasks.join("1.json"), &stored("1", "Inspect", "completed"));
    write(&tasks.join("2.json"), &stored("2", "Implement", "pending"));
    write(
        &tasks.join("3.json"),
        &json!({"id": "3", "subject": "Hidden", "status": "pending", "metadata": {"_internal": true}})
            .to_string(),
    );
    write(&tasks.join("4.json"), "{");
    mkdir(&tasks.join("5.json"));
    let frames = update("t1", json!({"taskId": "2", "status": "completed"}));
    let plans = turn_plans(frames, config(home.path(), None), Some("native-session")).await;
    assert_eq!(plans.len(), 1);
    assert_eq!(
        steps(&plans[0]),
        [
            step("1", "Inspect", "completed"),
            step("2", "Implement", "completed")
        ]
    );

    let empty = TempDir::new();
    mkdir(&empty.join("tasks").join("native-session"));
    let frames = update("t1", json!({"taskId": "1", "status": "deleted"}));
    let emptied = turn_plans(frames, config(empty.path(), None), Some("native-session")).await;
    assert_eq!(emptied.len(), 1);
    assert_eq!(emptied[0], json!([]));
}
