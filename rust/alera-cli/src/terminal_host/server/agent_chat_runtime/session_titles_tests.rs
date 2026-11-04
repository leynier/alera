//! AI chat titles: one automatic attempt, regeneration state, user titles
//! that only a person's request replaces, and forks.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use serde_json::Value;
use tokio::sync::{oneshot, Notify};

use super::super::super::agent_chat_title_jobs::ChatTitleGenerator;
use super::super::super::agent_chat_title_prompt::ChatTitleRequest;
use super::super::AgentChatRuntime;
use super::*;

#[derive(Default)]
struct ScriptedTitles {
    requests: Mutex<Vec<ChatTitleRequest>>,
    answers: Mutex<VecDeque<Result<String, String>>>,
    automatic_off: AtomicBool,
    hold: AtomicBool,
    release: Notify,
}

impl ScriptedTitles {
    fn answer(&self, answer: Result<&str, &str>) {
        self.answers
            .lock()
            .unwrap()
            .push_back(answer.map(str::to_owned).map_err(str::to_owned));
    }

    fn requests(&self) -> Vec<ChatTitleRequest> {
        self.requests.lock().unwrap().clone()
    }

    /// Waits until `count` jobs reached the generator.
    async fn reached(&self, count: usize) {
        wait_until(|| self.requests.lock().unwrap().len() >= count).await;
    }

    /// Waits until every scripted answer was taken, then lets the job post it.
    async fn drained(&self) {
        wait_until(|| self.answers.lock().unwrap().is_empty()).await;
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

#[async_trait]
impl ChatTitleGenerator for ScriptedTitles {
    async fn automatic_enabled(&self) -> bool {
        !self.automatic_off.load(Ordering::SeqCst)
    }

    async fn generate(
        &self,
        request: ChatTitleRequest,
        _cancel: oneshot::Receiver<()>,
    ) -> Result<String, String> {
        let held = self.hold.load(Ordering::SeqCst);
        self.requests.lock().unwrap().push(request);
        if held {
            self.release.notified().await;
        }
        self.answers
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or_else(|| Err("no scripted title".into()))
    }
}

async fn titled_fixture() -> (
    crate::terminal_host::server::chat_orchestration::test_support::TestHarness,
    AgentChatRuntime,
    Arc<RecordingFactory>,
    Arc<ScriptedTitles>,
) {
    let (harness, runtime, factory) = fixture().await;
    let titles = Arc::new(ScriptedTitles::default());
    let runtime = runtime.with_title_generator(titles.clone());
    (harness, runtime, factory, titles)
}

async fn snapshot(runtime: &AgentChatRuntime, chat: &str) -> Value {
    runtime.snapshot(chat).await.unwrap()
}

async fn wait_for_state(runtime: &AgentChatRuntime, chat: &str, status: &str) -> Value {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = snapshot(runtime, chat).await;
            if snapshot["titleGeneration"]["status"] == status {
                return snapshot;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap()
}

async fn command(runtime: &AgentChatRuntime, chat: &str, op: ChatOp) -> Result<Value, String> {
    runtime
        .command(chat, op, CallerCtx::runtime(), None)
        .await
        .map_err(|error| error.wire_message())
}

/// A chat whose first turn ended and got the title `title`.
async fn titled_chat(
    runtime: &AgentChatRuntime,
    factory: &RecordingFactory,
    titles: &ScriptedTitles,
    title: &str,
) -> String {
    titles.answer(Ok(title));
    let chat = create(runtime, None).await;
    send(runtime, &chat, "first", "Fix the login crash on Android").await;
    finish_turn(runtime, factory, &chat, 1).await;
    let titled = wait_for_state(runtime, &chat, "idle").await;
    assert_eq!(titled["title"], title);
    assert_eq!(titled["titleSource"], "generated");
    chat
}

#[tokio::test]
async fn the_first_turn_generates_one_title_and_later_turns_do_not() {
    let (harness, runtime, factory, titles) = titled_fixture().await;
    let chat = titled_chat(&runtime, &factory, &titles, "Android Login Crash").await;
    let requests = titles.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].previous_title, None);
    assert_eq!(requests[0].conversation, "Fix the login crash on Android");
    assert!(requests[0].fork.is_none());
    assert_eq!(
        snapshot(&runtime, &chat).await["titleGeneration"]["autoAttempted"],
        true
    );

    titles.answer(Ok("Never Used"));
    send(&runtime, &chat, "second", "Also add a test").await;
    finish_turn(&runtime, &factory, &chat, 2).await;
    let after = snapshot(&runtime, &chat).await;
    assert_eq!(after["title"], "Android Login Crash");
    assert_eq!(titles.requests().len(), 1, "a second automatic attempt ran");
    harness.finish().await;
}

#[tokio::test]
async fn automatic_titles_respect_the_setting_and_still_count_the_attempt() {
    let (harness, runtime, factory, titles) = titled_fixture().await;
    titles.automatic_off.store(true, Ordering::SeqCst);
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Fix the login crash").await;
    finish_turn(&runtime, &factory, &chat, 1).await;
    let after = snapshot(&runtime, &chat).await;
    assert_eq!(after["titleSource"], "derived");
    assert_eq!(after["titleGeneration"]["autoAttempted"], true);
    assert!(titles.requests().is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn a_generated_title_never_replaces_a_title_a_person_set() {
    let (harness, runtime, factory, titles) = titled_fixture().await;
    titles.hold.store(true, Ordering::SeqCst);
    titles.answer(Ok("Generated Too Late"));
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Fix the login crash").await;
    finish_turn(&runtime, &factory, &chat, 1).await;
    assert_eq!(
        snapshot(&runtime, &chat).await["titleGeneration"]["status"],
        "generating"
    );
    titles.reached(1).await;
    command(
        &runtime,
        &chat,
        ChatOp::Rename {
            title: "Mine".into(),
        },
    )
    .await
    .unwrap();
    titles.release.notify_one();
    // The job's answer is discarded: the rename dropped it.
    titles.drained().await;
    let after = snapshot(&runtime, &chat).await;
    assert_eq!(after["title"], "Mine");
    assert_eq!(after["titleSource"], "user");
    assert_eq!(after["titleGeneration"]["status"], "idle");

    let refused = command(
        &runtime,
        &chat,
        ChatOp::RegenerateTitle {
            replace_user_title: false,
        },
    )
    .await
    .unwrap_err();
    assert!(refused.contains("Only a person"), "{refused}");
    assert_eq!(titles.requests().len(), 1);
    harness.finish().await;
}

#[tokio::test]
async fn regeneration_reports_its_state_and_replaces_a_user_title_on_request() {
    let (harness, runtime, factory, titles) = titled_fixture().await;
    let chat = titled_chat(&runtime, &factory, &titles, "Android Login Crash").await;
    command(
        &runtime,
        &chat,
        ChatOp::Rename {
            title: "Mine".into(),
        },
    )
    .await
    .unwrap();
    titles.hold.store(true, Ordering::SeqCst);
    titles.answer(Ok("Login Crash Regression Tests"));
    let started = command(
        &runtime,
        &chat,
        ChatOp::RegenerateTitle {
            replace_user_title: true,
        },
    )
    .await
    .unwrap();
    assert_eq!(started["titleGeneration"]["status"], "generating");
    let pending = snapshot(&runtime, &chat).await;
    assert_eq!(pending["titleGeneration"]["mode"], "regenerate");
    assert_eq!(pending["title"], "Mine");
    titles.release.notify_one();
    let done = wait_for_state(&runtime, &chat, "idle").await;
    assert_eq!(done["title"], "Login Crash Regression Tests");
    assert_eq!(done["titleSource"], "generated");
    let requests = titles.requests();
    assert_eq!(requests[1].previous_title.as_deref(), Some("Mine"));
    assert!(requests[1]
        .conversation
        .contains("USER:\nFix the login crash"));
    harness.finish().await;
}

#[tokio::test]
async fn a_failed_regeneration_keeps_the_title_and_reports_why() {
    let (harness, runtime, factory, titles) = titled_fixture().await;
    let chat = titled_chat(&runtime, &factory, &titles, "Android Login Crash").await;
    titles.answer(Err("AI Assist is disabled."));
    command(
        &runtime,
        &chat,
        ChatOp::RegenerateTitle {
            replace_user_title: false,
        },
    )
    .await
    .unwrap();
    let failed = wait_for_state(&runtime, &chat, "failed").await;
    assert_eq!(failed["title"], "Android Login Crash");
    assert_eq!(
        failed["titleGeneration"]["errorMessage"],
        "AI Assist is disabled."
    );
    harness.finish().await;
}

#[tokio::test]
async fn a_fork_titles_itself_from_inherited_history_without_the_pending_job() {
    let (harness, runtime, factory, titles) = titled_fixture().await;
    let source = titled_chat(&runtime, &factory, &titles, "Android Login Crash").await;
    titles.hold.store(true, Ordering::SeqCst);
    command(
        &runtime,
        &source,
        ChatOp::RegenerateTitle {
            replace_user_title: false,
        },
    )
    .await
    .unwrap();
    titles.reached(2).await;
    titles.hold.store(false, Ordering::SeqCst);
    let turn = snapshot(&runtime, &source).await["turns"][0]["turnId"]
        .as_str()
        .unwrap()
        .to_owned();
    let forked = runtime
        .fork(&source, &turn, None, CallerCtx::runtime(), None)
        .await
        .unwrap();
    let fork = forked["chatId"].as_str().unwrap().to_owned();
    let initial = snapshot(&runtime, &fork).await;
    assert_eq!(initial["title"], "Android Login Crash Fork");
    assert_eq!(initial["titleSource"], "derived");
    assert_eq!(initial["titleGeneration"]["status"], "idle");
    assert!(initial["titleGeneration"].get("jobId").is_none());

    // The source's pending job never lands on the fork.
    titles.answer(Ok("Source Title"));
    titles.release.notify_one();
    let source_done = wait_for_state(&runtime, &source, "idle").await;
    assert_eq!(source_done["title"], "Source Title");
    assert_eq!(
        snapshot(&runtime, &fork).await["title"],
        "Android Login Crash Fork"
    );

    titles.answer(Ok("Android Login Crash Tests"));
    send(&runtime, &fork, "fork-first", "Now write regression tests").await;
    finish_turn(&runtime, &factory, &fork, 1).await;
    let done = wait_for_state(&runtime, &fork, "idle").await;
    assert_eq!(done["title"], "Android Login Crash Tests");
    let request = titles.requests().pop().unwrap();
    assert_eq!(request.conversation, "Now write regression tests");
    let fork_source = request.fork.expect("fork variant");
    assert_eq!(fork_source.title, "Android Login Crash");
    assert!(fork_source
        .history
        .contains("Fix the login crash on Android"));
    harness.finish().await;
}
