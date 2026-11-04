use alera_core::runtime::ChatOrchestrationTaskStatus as Status;

use super::wake_text::{fair_shares, wake_text, WakeTask, WAKE_TEXT_MAX_BYTES};

fn task(id: &str, status: Status, result: Option<&str>) -> WakeTask {
    WakeTask {
        task_id: id.into(),
        title: Some(format!("Title {id}")),
        status: Some(status),
        child_chat_id: Some(format!("chat-{id}")),
        result: result.map(ToOwned::to_owned),
        error: None,
    }
}

#[test]
fn fair_shares_give_small_sizes_all_they_ask_and_split_the_rest() {
    assert_eq!(fair_shares(&[10, 500, 20], 300), vec![10, 270, 20]);
    assert_eq!(fair_shares(&[100, 100, 100], 200), vec![66, 67, 67]);
    assert_eq!(fair_shares(&[5, 5], 100), vec![5, 5]);
    assert_eq!(fair_shares(&[], 100), Vec::<usize>::new());
    assert_eq!(fair_shares(&[50], 0), vec![0]);
}

#[test]
fn a_small_result_is_inlined_under_its_header() {
    let text = wake_text(&[task("t1", Status::Completed, Some("All tests pass."))]);
    assert_eq!(
        text,
        "Delegated task t1 (Title t1) [completed]:\nAll tests pass."
    );
}

#[test]
fn large_results_share_the_budget_fairly_and_point_to_the_child_chat() {
    let big = "a".repeat(20_000);
    let text = wake_text(&[
        task("t1", Status::Completed, Some("Short result.")),
        task("t2", Status::Completed, Some(&big)),
        task("t3", Status::Completed, Some(&big)),
    ]);
    assert!(text.len() <= WAKE_TEXT_MAX_BYTES, "{}", text.len());
    assert!(text.contains("[completed]:\nShort result."));
    assert_eq!(text.matches("[Truncated to fit this message.").count(), 2);
    assert!(text.contains("Read the full result with chat_read and chatId chat-t2."));
    assert!(text.contains("Read the full result with chat_read and chatId chat-t3."));
    let t2 = text.find("task t2").unwrap();
    let t3 = text.find("task t3").unwrap();
    let share = |from: usize, to: usize| text[from..to].matches('a').count();
    assert!(share(t2, t3).abs_diff(share(t3, text.len())) < 64);
}

#[test]
fn a_cut_lands_on_a_char_boundary() {
    let wide = "é".repeat(12_000);
    let text = wake_text(&[task("t1", Status::Completed, Some(&wide))]);
    assert!(text.len() <= WAKE_TEXT_MAX_BYTES);
    assert!(text.contains("[Truncated to fit this message."));
}

#[test]
fn a_cut_closes_an_open_code_fence() {
    let fenced = format!("Result:\n```rust\n{}", "let x = 1;\n".repeat(3_000));
    let text = wake_text(&[task("t1", Status::Completed, Some(&fenced))]);
    let body = text.split("\n[Truncated").next().unwrap();
    assert!(body.ends_with("\n```"), "{}", &body[body.len() - 20..]);
    assert_eq!(body.matches("```").count(), 2);
}

#[test]
fn a_hundred_large_results_keep_every_task_id_and_leave_out_what_does_not_fit() {
    let big = "b".repeat(5_000);
    let tasks: Vec<WakeTask> = (0..100)
        .map(|index| task(&format!("t{index:03}"), Status::Completed, Some(&big)))
        .collect();
    let text = wake_text(&tasks);
    for index in 0..100 {
        assert!(text.contains(&format!("Delegated task t{index:03} ")));
    }
    assert!(text.contains("the result did not fit in this message. Read it with chat_read"));
    assert!(text.len() <= WAKE_TEXT_MAX_BYTES + 2_000, "{}", text.len());
}

#[test]
fn a_missing_task_points_to_chat_task_status() {
    let missing = WakeTask {
        task_id: "gone".into(),
        title: None,
        status: None,
        child_chat_id: None,
        result: None,
        error: None,
    };
    assert_eq!(
        wake_text(&[missing]),
        "Delegated task gone is no longer recorded. Check it with chat_task_status and taskId gone."
    );
}

#[test]
fn titles_stay_on_one_line_and_failures_lead_with_their_error() {
    let mut failed = task("t1", Status::Failed, Some("Partial notes."));
    failed.title = Some("Fix\nthe   parser".into());
    failed.error = Some((Some("turnFailed".into()), "The model refused.".into()));
    assert_eq!(
        wake_text(&[failed]),
        "Delegated task t1 (Fix the parser) [failed]:\nError (turnFailed): The model refused.\nPartial notes."
    );
}

#[test]
fn a_task_without_a_result_says_where_to_read_it() {
    let text = wake_text(&[task("t1", Status::NeedsInput, None)]);
    assert_eq!(
        text,
        "Delegated task t1 (Title t1) [needs_input]. Read it with chat_task_status and taskId t1."
    );
}
