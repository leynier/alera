use alera_agent_transport::MockTransport;
use alera_provider_pi::{PiProvider, PiProviderConfig};
use alera_provider_protocol::{EventKind, Provider, ProviderEvent, SessionStartInput, TurnInput};
use serde_json::{json, Value};

fn state() -> Value {
    json!({
        "sessionFile": "/tmp/pi/session.jsonl",
        "sessionId": "session-1",
        "model": { "provider": "anthropic", "id": "claude-sonnet" },
        "isStreaming": false
    })
}

fn response(id: &str, command: &str, data: Value) -> Value {
    json!({ "type": "response", "id": id, "command": command, "success": true, "data": data })
}

/// The shape Pi's RPC `get_commands` answers with: extension commands,
/// prompt templates and skills, each with its source.
fn catalog() -> Value {
    json!({ "commands": [
        {
            "name": "skill:global-review",
            "description": "Review changes.",
            "source": "skill",
            "sourceInfo": { "path": "/home/test/.agents/skills/global-review/SKILL.md", "scope": "user" }
        },
        {
            "name": "skill:project-deploy",
            "description": "Deploy this project.",
            "source": "skill",
            "sourceInfo": { "path": "/workspace/.agents/skills/project-deploy/SKILL.md", "scope": "workspace" },
            "interface": { "displayName": "Project Deploy", "shortDescription": "Ship it" }
        },
        { "name": "skill:brave-search", "source": "skill", "location": "global", "path": "/home/test/.pi/agent/skills/brave-search/SKILL.md" },
        { "name": "skill:", "source": "skill" },
        { "name": "hello", "description": "Say hello.", "source": "extension" },
        { "name": "fix-tests", "description": "Fix failing tests", "source": "prompt", "location": "project" },
        { "name": "compact", "description": "An extension shadowing the builtin", "source": "extension" },
        { "name": "  ", "source": "extension" }
    ]})
}

fn provider(responses: Vec<Value>) -> PiProvider<MockTransport> {
    PiProvider::new(
        MockTransport::new(responses),
        PiProviderConfig {
            request_timeout: std::time::Duration::from_millis(100),
            ..PiProviderConfig::default()
        },
    )
}

async fn next(provider: &mut PiProvider<MockTransport>) -> ProviderEvent {
    let event = provider.next_event().await.unwrap().unwrap();
    event.validate().unwrap();
    event
}

async fn start(provider: &mut PiProvider<MockTransport>) {
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    assert_eq!(next(provider).await.kind, EventKind::SessionStarted);
    assert_eq!(next(provider).await.kind, EventKind::ThreadStarted);
}

#[tokio::test]
async fn session_start_publishes_compact_first_then_pi_commands_and_skills() {
    let mut provider = provider(vec![
        response("alera-pi-1", "get_state", state()),
        response("alera-pi-get-commands", "get_commands", catalog()),
    ]);
    start(&mut provider).await;
    assert!(provider
        .transport()
        .writes()
        .iter()
        .any(|record| *record == json!({ "type": "get_commands", "id": "alera-pi-get-commands" })));
    let commands = next(&mut provider).await;
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    assert!(commands.turn_id.is_none());
    assert_eq!(
        commands.payload,
        json!({ "commands": [
            {
                "name": "compact",
                "description": "Summarize the conversation and reduce context usage",
                "input": { "hint": "Optional instructions" }
            },
            { "name": "hello", "description": "Say hello." },
            { "name": "fix-tests", "description": "Fix failing tests" }
        ]})
    );
    let skills = next(&mut provider).await;
    assert_eq!(skills.kind, EventKind::SessionSkillsUpdated);
    assert_eq!(
        skills.payload,
        json!({ "skills": [
            {
                "name": "global-review",
                "description": "Review changes.",
                "path": "/home/test/.agents/skills/global-review/SKILL.md",
                "scope": "user",
                "enabled": true
            },
            {
                "name": "project-deploy",
                "description": "Deploy this project.",
                "path": "/workspace/.agents/skills/project-deploy/SKILL.md",
                "scope": "project",
                "enabled": true,
                "displayName": "Project Deploy",
                "shortDescription": "Ship it"
            },
            {
                "name": "brave-search",
                "path": "/home/test/.pi/agent/skills/brave-search/SKILL.md",
                "scope": "user",
                "enabled": true
            }
        ]})
    );
}

#[tokio::test]
async fn a_failed_catalog_read_publishes_nothing() {
    let mut provider = provider(vec![
        response("alera-pi-1", "get_state", state()),
        json!({
            "type": "response",
            "id": "alera-pi-get-commands",
            "command": "get_commands",
            "success": false,
            "error": "Unknown command: get_commands"
        }),
    ]);
    start(&mut provider).await;
    assert_eq!(next(&mut provider).await.kind, EventKind::SessionExited);
}

#[tokio::test]
async fn a_catalog_answer_during_another_call_is_kept() {
    let mut provider = provider(vec![
        response("alera-pi-1", "get_state", state()),
        response(
            "alera-pi-get-commands",
            "get_commands",
            json!({ "commands": [] }),
        ),
        response("alera-pi-2", "set_model", json!({})),
    ]);
    start(&mut provider).await;
    let mut input = TurnInput::text("thread", "hello");
    input.model = Some("openai/gpt-5".into());
    provider.send_turn(input).await.unwrap();
    let commands = next(&mut provider).await;
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    assert_eq!(commands.payload["commands"][0]["name"], "compact");
    let skills = next(&mut provider).await;
    assert_eq!(skills.payload, json!({ "skills": [] }));
}
