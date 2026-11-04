mod support;

use alera_provider_codex::{probe_skills, CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderEvent, ProviderSkill, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

const CWD: &str = "/workspace/app";

fn initialize_response(id: i64) -> Value {
    json!({ "id": id, "result": { "codexHome": "/tmp/codex", "userAgent": "test" } })
}

fn thread_response(id: i64) -> Value {
    json!({ "id": id, "result": { "thread": { "id": "native-thread" } } })
}

fn skills_response(id: i64, data: Value) -> Value {
    json!({ "id": id, "result": { "data": data } })
}

fn review_entry(cwd: &str) -> Value {
    json!({
        "cwd": cwd,
        "errors": [],
        "skills": [{
            "name": "review",
            "description": "Review the pending change",
            "path": "/home/me/.codex/skills/review/SKILL.md",
            "scope": "user",
            "enabled": true,
            "interface": {
                "displayName": "Code Review",
                "shortDescription": "Review changes",
                "brandColor": "#000000",
            },
        }],
    })
}

fn review_skill() -> ProviderSkill {
    ProviderSkill::from_native("review", "/home/me/.codex/skills/review/SKILL.md", true)
        .unwrap()
        .with_description(Some("Review the pending change"))
        .with_scope(Some("user"))
        .with_display_name(Some("Code Review"))
        .with_short_description(Some("Review changes"))
}

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-skills".into(),
        ..CodexProviderConfig::default()
    }
}

fn session_input() -> SessionStartInput {
    let mut input = SessionStartInput::new("app-thread");
    input.cwd = Some(PathBuf::from(CWD));
    input
}

fn skills_of(event: &ProviderEvent) -> Vec<ProviderSkill> {
    assert_eq!(event.kind, EventKind::SessionSkillsUpdated);
    assert_eq!(event.thread_id, "app-thread");
    serde_json::from_value(event.payload["skills"].clone()).unwrap()
}

#[tokio::test]
async fn session_start_lists_skills_for_the_session_cwd() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2),
        skills_response(3, json!([review_entry(CWD)])),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    let session = provider.start_session(session_input()).await.unwrap();
    assert_eq!(session.native_thread_id, "native-thread");

    assert_eq!(
        provider.transport().writes()[3],
        json!({ "id": 3, "method": "skills/list", "params": { "cwds": [CWD] } })
    );
    let event = support::next_event(&mut provider).await.unwrap().unwrap();
    assert_eq!(skills_of(&event), vec![review_skill()]);
    assert_eq!(
        event.raw.as_ref().unwrap().method.as_deref(),
        Some("skills/list")
    );
    assert!(support::next_event(&mut provider).await.unwrap().is_none());
}

#[tokio::test]
async fn a_failing_skills_list_does_not_break_session_start() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2),
        json!({ "id": 3, "error": { "code": -32601, "message": "unknown method" } }),
        json!({ "id": 4, "result": { "turn": { "id": "native-turn" } } }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider.start_session(session_input()).await.unwrap();
    // Only the commands update is queued.
    assert_eq!(provider.queued_event_count(), 1);

    let turn = provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    assert_eq!(turn.turn_id, "native-turn");
    assert!(support::next_event(&mut provider).await.unwrap().is_none());
}

#[tokio::test]
async fn a_session_without_a_cwd_does_not_list_skills() {
    let transport = MockTransport::new([initialize_response(1), thread_response(2)]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(provider.transport().writes().len(), 3);
    assert!(support::next_event(&mut provider).await.unwrap().is_none());
}

#[tokio::test]
async fn skills_changed_lists_the_skills_again() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2),
        skills_response(3, json!([])),
        json!({ "method": "skills/changed", "params": {} }),
        skills_response(4, json!([review_entry(CWD)])),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider.start_session(session_input()).await.unwrap();

    let first = support::next_event(&mut provider).await.unwrap().unwrap();
    assert!(skills_of(&first).is_empty());
    let refreshed = support::next_event(&mut provider).await.unwrap().unwrap();
    assert_eq!(skills_of(&refreshed), vec![review_skill()]);
    assert_eq!(
        provider.transport().writes()[4],
        json!({ "id": 4, "method": "skills/list", "params": { "cwds": [CWD] } })
    );
    assert!(support::next_event(&mut provider).await.unwrap().is_none());
}

#[tokio::test]
async fn skills_changed_during_a_request_lists_on_the_next_event() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2),
        skills_response(3, json!([])),
        json!({ "method": "skills/changed", "params": {} }),
        json!({ "id": 4, "result": { "turn": { "id": "native-turn" } } }),
        skills_response(5, json!([review_entry(CWD)])),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider.start_session(session_input()).await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();

    let first = support::next_event(&mut provider).await.unwrap().unwrap();
    assert!(skills_of(&first).is_empty());
    let refreshed = support::next_event(&mut provider).await.unwrap().unwrap();
    assert_eq!(skills_of(&refreshed), vec![review_skill()]);
    assert_eq!(provider.transport().writes()[5]["method"], "skills/list");
}

async fn list(data: Value) -> Result<Vec<ProviderSkill>, ProviderError> {
    let transport = MockTransport::new([initialize_response(1), skills_response(2, data)]);
    let mut provider = CodexProvider::new(transport, config());
    let listed = provider.list_skills(Path::new(CWD)).await;
    assert_eq!(
        provider.transport().writes()[2],
        json!({ "id": 2, "method": "skills/list", "params": { "cwds": [CWD] } })
    );
    listed
}

fn plain_skill(name: &str, cwd: &str) -> Value {
    json!({
        "name": name,
        "description": "",
        "path": format!("{cwd}/.codex/skills/{name}/SKILL.md"),
        "scope": "repo",
        "enabled": true,
    })
}

#[tokio::test]
async fn list_skills_prefers_the_entry_for_the_requested_cwd() {
    let skills = list(json!([
        { "cwd": "/elsewhere", "errors": [], "skills": [plain_skill("other", "/elsewhere")] },
        { "cwd": CWD, "errors": [], "skills": [plain_skill("deploy", CWD)] },
    ]))
    .await
    .unwrap();
    let names: Vec<_> = skills.iter().map(|skill| skill.name.as_str()).collect();
    assert_eq!(names, ["deploy"]);
    assert_eq!(skills[0].description, None);
    assert_eq!(skills[0].scope.as_deref(), Some("repo"));
}

#[tokio::test]
async fn list_skills_flattens_every_entry_without_a_matching_cwd() {
    let skills = list(json!([
        { "cwd": "/one", "errors": [], "skills": [plain_skill("first", "/one")] },
        { "cwd": "/two", "errors": [], "skills": [plain_skill("second", "/two")] },
    ]))
    .await
    .unwrap();
    let names: Vec<_> = skills.iter().map(|skill| skill.name.as_str()).collect();
    assert_eq!(names, ["first", "second"]);
}

#[tokio::test]
async fn list_skills_reads_interface_texts_and_enabled_flags() {
    let skills = list(json!([{
        "cwd": CWD,
        "errors": [{ "message": "bad frontmatter", "path": "/broken/SKILL.md" }],
        "skills": [
            {
                "name": "top", "description": "Top", "path": "/s/top/SKILL.md",
                "scope": "system", "enabled": false,
                "shortDescription": "Top level",
                "interface": { "shortDescription": "Interface", "displayName": null },
            },
            {
                "name": "fallback", "description": "Fallback", "path": "/s/fallback/SKILL.md",
                "scope": "admin", "enabled": true, "shortDescription": null,
                "interface": { "shortDescription": "From interface" },
            },
            { "name": "", "description": "", "path": "/s/empty/SKILL.md", "scope": "user", "enabled": true },
            { "name": "no-path", "description": "", "scope": "user", "enabled": true },
        ],
    }]))
    .await
    .unwrap();
    assert_eq!(skills.len(), 2);
    assert_eq!(skills[0].short_description.as_deref(), Some("Top level"));
    assert_eq!(skills[0].display_name, None);
    assert!(!skills[0].enabled);
    assert_eq!(
        skills[1].short_description.as_deref(),
        Some("From interface")
    );
    assert_eq!(skills[1].scope.as_deref(), Some("admin"));
}

#[tokio::test]
async fn list_skills_rejects_a_response_without_data() {
    let transport = MockTransport::new([initialize_response(1), json!({ "id": 2, "result": {} })]);
    let mut provider = CodexProvider::new(transport, config());
    let error = provider.list_skills(Path::new(CWD)).await.unwrap_err();
    assert!(matches!(error, ProviderError::Protocol(_)));
}

#[tokio::test]
async fn probe_lists_skills_from_a_short_lived_app_server() {
    let mut config = config();
    config.executable = PathBuf::from(env!("CARGO_BIN_EXE_codex-app-server-fixture"));
    config.args.clear();
    config.cwd = Some(std::env::temp_dir());
    let skills = probe_skills(config).await.unwrap();
    let names: Vec<_> = skills.iter().map(|skill| skill.name.as_str()).collect();
    assert_eq!(names, ["review"]);
    assert_eq!(skills[0].scope.as_deref(), Some("user"));
}

#[tokio::test]
async fn probe_requires_a_working_directory() {
    let error = probe_skills(config()).await.unwrap_err();
    assert!(matches!(error, ProviderError::Validation(_)));
}
