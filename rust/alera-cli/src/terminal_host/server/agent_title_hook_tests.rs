use super::*;
use crate::agent_status::AgentHookEvent;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;

fn event(agent: &str, name: &str, id: &str, prompt: &str) -> AgentHookEvent {
    AgentHookEvent {
        terminal_session_id: "session".into(),
        workspace_id: "workspace".into(),
        tab_id: "tab".into(),
        agent_type: agent.into(),
        event_name: Some(name.into()),
        payload: json!({"session_id": id, "prompt": prompt}),
    }
}

#[tokio::test]
async fn compatible_hooks_do_not_cancel_or_retire_the_native_conversation() {
    for (agent, prompt_event) in [
        ("grok", "UserPromptSubmit"),
        ("cursor", "beforeSubmitPrompt"),
    ] {
        let dir = tempfile::tempdir().unwrap();
        let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
        let mut tab = tab();
        initialize(&mut tab, "");
        actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
        actor
            .observe_hook_title(&event(agent, prompt_event, "native", "First task"))
            .await;
        let job = actor.agent_title_jobs["tab"].id.clone();
        actor
            .agent_presence
            .update("session", agent.into(), AgentPresenceState::Working);
        for name in ["PreToolUse", "PostToolUse", "Stop", "SessionEnd"] {
            actor
                .observe_hook_title(&event("claude", name, "compatible", "Wrong prompt"))
                .await;
        }
        actor
            .observe_hook_title(&event(agent, prompt_event, "native", "Next turn"))
            .await;
        assert_eq!(actor.agent_title_jobs["tab"].id, job);
        let saved = actor
            .runtime_store
            .find_workspace_tab("tab")
            .await
            .unwrap()
            .unwrap();
        let state = AgentTitleState::read(&saved).unwrap();
        assert_eq!(state.agent.as_deref(), Some(agent));
        assert_eq!(state.native_id.as_deref(), Some("native"));
        assert_eq!(state.initial_prompt, "First task");
        assert!(state.retired.is_empty());
        actor
            .finish_agent_title("tab".into(), job, Ok("Native Conversation Title".into()))
            .await;
        assert_eq!(
            actor
                .runtime_store
                .find_workspace_tab("tab")
                .await
                .unwrap()
                .unwrap()
                .title,
            "Native Conversation Title"
        );
    }
}

#[tokio::test]
async fn confirmed_resume_cancels_previous_job_and_restores_first_prompt_without_retry() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let mut tab = tab();
    initialize(&mut tab, "");
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    actor
        .observe_hook_title(&event("grok", "UserPromptSubmit", "a", "Original A prompt"))
        .await;
    let first = actor.agent_title_jobs["tab"].id.clone();
    actor
        .finish_agent_title("tab".into(), first, Ok("Conversation A Title".into()))
        .await;
    actor
        .observe_hook_title(&event("grok", "UserPromptSubmit", "b", "Original B prompt"))
        .await;
    let second = actor.agent_title_jobs["tab"].id.clone();
    actor
        .observe_hook_title(&event("grok", "UserPromptSubmit", "a", "Delayed A prompt"))
        .await;
    assert_eq!(actor.agent_title_jobs["tab"].id, second);
    actor
        .observe_hook_title(&event("grok", "session_start", "a", ""))
        .await;
    assert!(actor.agent_title_jobs.is_empty());
    actor
        .finish_agent_title("tab".into(), second, Ok("Stale B Result".into()))
        .await;
    drop(actor);
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor
        .observe_hook_title(&event("grok", "session_start", "a", ""))
        .await;
    actor
        .observe_hook_title(&event("grok", "UserPromptSubmit", "a", "Continuation of A"))
        .await;
    actor
        .observe_hook_title(&event("grok", "SessionEnd", "b", ""))
        .await;
    assert!(actor.agent_title_jobs.is_empty());
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    let state = AgentTitleState::read(&saved).unwrap();
    assert_eq!(saved.title, "Conversation A Title");
    assert_eq!(state.native_id.as_deref(), Some("a"));
    assert_eq!(state.initial_prompt, "Original A prompt");
    assert!(!state.closed);
    assert!(!state.eligible);
    actor.request_agent_title(1, 1, &json!({"tabId": "tab", "expectedConversationId": saved.payload["agentTitleConversationId"], "expectedRevision": saved.payload["agentTitleRevision"]})).await.unwrap();
    assert_eq!(actor.agent_title_jobs.len(), 1);
}

#[test]
fn closed_session_resume_uses_new_cursor_and_preserves_initial_prompt() {
    let mut state = AgentTitleState::new(true);
    state.observe("pi", Some("a"), "Initial prompt", 0);
    state.attempted = true;
    state.closed = true;
    let previous = state.conversation_id.clone();
    state.resume("pi", Some("a"), 100);
    assert!(state.observe("pi", Some("a"), "Continuation", 101));
    assert_ne!(state.conversation_id, previous);
    assert_eq!(state.cursor, Some(100));
    assert_eq!(state.initial_prompt, "Initial prompt");
    assert!(state.attempted);
    assert!(!state.eligible);
}

#[test]
fn resume_history_is_bounded_and_old_resumes_do_not_inherit_other_prompts() {
    let mut state = AgentTitleState::new(true);
    for id in 0..20 {
        state.observe("grok", Some(&id.to_string()), &format!("Prompt {id}"), id);
    }
    assert_eq!(state.retired_prompts.len(), 16);
    state.resume("grok", Some("0"), 100);
    assert_eq!(state.native_id.as_deref(), Some("0"));
    assert!(state.initial_prompt.is_empty());
    assert!(!state.eligible);
    assert!(!state.observe("grok", Some("19"), "Late prompt", 101));
}

#[tokio::test]
async fn child_or_unverified_opencode_hooks_cannot_retire_the_parent() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let mut tab = tab();
    initialize(&mut tab, "");
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    let mut parent = event("opencode", "MessagePart", "parent", "Parent task");
    parent.payload["role"] = json!("user");
    parent.payload["text"] = json!("Parent task");
    actor.observe_hook_title(&parent).await;
    let generation = actor.agent_title_jobs["tab"].id.clone();
    for metadata in [
        json!({"parent_session_id": "parent"}),
        json!({"agentTitleIgnore": true}),
    ] {
        let mut child = event("opencode", "MessagePart", "child", "Child task");
        child
            .payload
            .as_object_mut()
            .unwrap()
            .extend(metadata.as_object().unwrap().clone());
        actor.observe_hook_title(&child).await;
    }
    actor.observe_hook_title(&parent).await;
    assert_eq!(actor.agent_title_jobs["tab"].id, generation);
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    let state = AgentTitleState::read(&saved).unwrap();
    assert_eq!(state.native_id.as_deref(), Some("parent"));
    assert_eq!(state.initial_prompt, "Parent task");
    assert!(state.retired.is_empty());
}
