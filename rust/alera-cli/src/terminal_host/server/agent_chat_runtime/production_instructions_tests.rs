use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use alera_provider_protocol::{
    EventKind, InterruptInput, NativeForkInput, NativeForkResult, Provider, ProviderCapabilities,
    ProviderError, ProviderEvent, ProviderKind, ProviderSession, RuntimeResponse,
    SessionStartInput, SessionStatus, SubagentCapabilities, TurnInput, TurnStartResult,
    MAX_TURN_INPUT_CHARS,
};
use async_trait::async_trait;
use serde_json::json;

use super::instructed;

#[derive(Default)]
struct Log {
    starts: Vec<SessionStartInput>,
    forks: Vec<NativeForkInput>,
    turns: Vec<String>,
    calls: Vec<String>,
    fail_next_turn: bool,
    events: VecDeque<ProviderEvent>,
}

struct Recording(Arc<Mutex<Log>>);

fn session() -> ProviderSession {
    ProviderSession {
        provider: ProviderKind::Codex,
        provider_instance_id: "test".into(),
        thread_id: "chat".into(),
        native_thread_id: "native".into(),
        status: SessionStatus::Ready,
        model: None,
        cwd: None,
        active_turn_id: None,
    }
}

#[async_trait]
impl Provider for Recording {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Codex
    }
    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities::default()
    }
    fn subagent_capabilities(&self) -> SubagentCapabilities {
        self.0
            .lock()
            .unwrap()
            .calls
            .push("subagentCapabilities".into());
        SubagentCapabilities::default()
    }
    fn session(&self) -> Option<&ProviderSession> {
        None
    }
    async fn initialize(&mut self) -> Result<(), ProviderError> {
        Ok(())
    }
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        self.0.lock().unwrap().starts.push(input);
        Ok(session())
    }
    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        let mut log = self.0.lock().unwrap();
        if std::mem::take(&mut log.fail_next_turn) {
            return Err(ProviderError::Protocol("busy".into()));
        }
        log.turns.push(input.input);
        Ok(TurnStartResult {
            thread_id: "chat".into(),
            turn_id: "turn".into(),
            native_turn_id: None,
        })
    }
    async fn steer_turn(&mut self, input: TurnInput, _: &str) -> Result<(), ProviderError> {
        self.0
            .lock()
            .unwrap()
            .calls
            .push(format!("steer:{}", input.input));
        Ok(())
    }
    async fn fork_session(
        &mut self,
        input: NativeForkInput,
    ) -> Result<NativeForkResult, ProviderError> {
        self.0.lock().unwrap().forks.push(input);
        Err(ProviderError::Unsupported("fork result".into()))
    }
    async fn await_background_tasks(
        &mut self,
        task_ids: &[String],
        _: bool,
    ) -> Result<Vec<String>, ProviderError> {
        self.0.lock().unwrap().calls.push("await".into());
        Ok(task_ids.to_vec())
    }
    async fn stop_subagent(&mut self, task_id: &str) -> Result<(), ProviderError> {
        self.0.lock().unwrap().calls.push(format!("stop:{task_id}"));
        Ok(())
    }
    async fn interrupt(&mut self, _: InterruptInput) -> Result<(), ProviderError> {
        self.0.lock().unwrap().calls.push("interrupt".into());
        Ok(())
    }
    async fn respond(&mut self, _: RuntimeResponse) -> Result<(), ProviderError> {
        Ok(())
    }
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        Ok(self.0.lock().unwrap().events.pop_front())
    }
    async fn close(&mut self) -> Result<(), ProviderError> {
        self.0.lock().unwrap().calls.push("close".into());
        Ok(())
    }
}

fn provider(name: &str) -> (Box<dyn Provider>, Arc<Mutex<Log>>) {
    let log = Arc::new(Mutex::new(Log::default()));
    let wrapped = instructed(
        Box::new(Recording(log.clone())),
        name,
        &[
            "Use chat_delegate.".to_owned(),
            "Second section.".to_owned(),
        ],
    );
    (wrapped, log)
}

async fn send(
    provider: &mut Box<dyn Provider>,
    text: &str,
) -> Result<TurnStartResult, ProviderError> {
    provider.send_turn(TurnInput::text("chat", text)).await
}

#[tokio::test]
async fn codex_gets_developer_instructions_on_start_resume_and_fork() {
    let (mut codex, log) = provider("codex");
    codex
        .start_session(SessionStartInput::new("chat"))
        .await
        .unwrap();
    let mut resume = SessionStartInput::new("chat");
    resume.resume_thread_id = Some("native".into());
    codex.start_session(resume).await.unwrap();
    let _ = codex
        .fork_session(NativeForkInput {
            source_native_thread_id: "native".into(),
            session: SessionStartInput::new("fork"),
            boundary: None,
        })
        .await;
    send(&mut codex, "Plain prompt").await.unwrap();
    let log = log.lock().unwrap();
    for start in &log.starts {
        assert_eq!(
            start.options["developerInstructions"],
            json!("Use chat_delegate.\n\nSecond section.")
        );
    }
    assert_eq!(
        log.forks[0].session.options["developerInstructions"],
        json!("Use chat_delegate.\n\nSecond section.")
    );
    assert_eq!(log.turns, ["Plain prompt"]);
}

#[tokio::test]
async fn claude_and_launches_without_instructions_pass_through() {
    let (mut claude, log) = provider("claudeAgent");
    claude
        .start_session(SessionStartInput::new("chat"))
        .await
        .unwrap();
    send(&mut claude, "Hello").await.unwrap();
    assert!(log.lock().unwrap().starts[0].options.is_empty());
    assert_eq!(log.lock().unwrap().turns, ["Hello"]);
    let plain_log = Arc::new(Mutex::new(Log::default()));
    let mut plain = instructed(Box::new(Recording(plain_log.clone())), "cursor", &[]);
    plain
        .start_session(SessionStartInput::new("chat"))
        .await
        .unwrap();
    send(&mut plain, "Hello").await.unwrap();
    assert_eq!(plain_log.lock().unwrap().turns, ["Hello"]);
}

#[tokio::test]
async fn the_first_eligible_prompt_is_wrapped_once_per_session() {
    let (mut cursor, log) = provider("cursor");
    cursor
        .start_session(SessionStartInput::new("chat"))
        .await
        .unwrap();
    send(&mut cursor, "/compact").await.unwrap();
    send(&mut cursor, "$review the diff").await.unwrap();
    send(&mut cursor, &"x".repeat(MAX_TURN_INPUT_CHARS))
        .await
        .unwrap();
    log.lock().unwrap().fail_next_turn = true;
    assert!(send(&mut cursor, "Failed once").await.is_err());
    send(&mut cursor, "Fix the parser").await.unwrap();
    send(&mut cursor, "Then the tests").await.unwrap();
    let turns = log.lock().unwrap().turns.clone();
    assert_eq!(turns[0], "/compact");
    assert_eq!(turns[1], "$review the diff");
    assert_eq!(turns[2].len(), MAX_TURN_INPUT_CHARS);
    assert_eq!(
        turns[3],
        "<alera_orchestration_instructions>\nUse chat_delegate.\n\nSecond section.\n</alera_orchestration_instructions>\n\n<user_request>\nFix the parser\n</user_request>"
    );
    assert_eq!(turns[4], "Then the tests");
}

#[tokio::test]
async fn a_restart_or_a_compaction_wraps_the_next_prompt_again() {
    let (mut grok, log) = provider("grok");
    grok.start_session(SessionStartInput::new("chat"))
        .await
        .unwrap();
    send(&mut grok, "First").await.unwrap();
    grok.start_session(SessionStartInput::new("chat"))
        .await
        .unwrap();
    send(&mut grok, "After restart").await.unwrap();
    let mut compaction = ProviderEvent::new(
        ProviderKind::Codex,
        "grok",
        "chat",
        EventKind::ItemStarted,
        json!({"itemType": "context_compaction"}),
        None,
    );
    compaction.turn_id = Some("turn".into());
    log.lock().unwrap().events.push_back(compaction);
    assert!(grok.next_event().await.unwrap().is_some());
    send(&mut grok, "After compaction").await.unwrap();
    send(&mut grok, "Plain").await.unwrap();
    let turns = log.lock().unwrap().turns.clone();
    assert!(turns[0].contains("<user_request>\nFirst\n"));
    assert!(turns[1].contains("<user_request>\nAfter restart\n"));
    assert!(turns[2].contains("<user_request>\nAfter compaction\n"));
    assert_eq!(turns[3], "Plain");
    // A slash command with a path is a prompt, not a command.
    assert!(!super::passes_through("grok", "/tmp/notes.md says hi"));
    assert!(super::passes_through("cursor", "$skill do it"));
    assert!(!super::passes_through("grok", "$skill do it"));
}

#[tokio::test]
async fn every_other_call_is_forwarded() {
    let (mut pi, log) = provider("pi");
    let _ = pi.subagent_capabilities();
    pi.steer_turn(TurnInput::text("chat", "steer"), "turn")
        .await
        .unwrap();
    pi.await_background_tasks(&["bg".into()], true)
        .await
        .unwrap();
    pi.stop_subagent("helper").await.unwrap();
    pi.interrupt(InterruptInput {
        thread_id: "chat".into(),
        turn_id: None,
    })
    .await
    .unwrap();
    pi.close().await.unwrap();
    assert_eq!(
        log.lock().unwrap().calls,
        [
            "subagentCapabilities",
            "steer:steer",
            "await",
            "stop:helper",
            "interrupt",
            "close"
        ]
    );
}
