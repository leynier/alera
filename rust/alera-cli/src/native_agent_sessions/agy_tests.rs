use std::path::Path;

use super::super::test_support::{outcome_for, session, sqlite_fixture, write, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;
use super::workspace_paths;

fn seed_conversation(storage: &Path, id: &str) {
    write(&storage.join(format!("conversations/{id}.db")), "db");
    write(&storage.join(format!("conversations/{id}.db-wal")), "wal");
    write(&storage.join(format!("conversations/{id}.db-shm")), "shm");
    write(&storage.join(format!("brain/{id}/plan.md")), "x");
    write(&storage.join(format!("annotations/{id}.pbtxt")), "x");
}

fn conversation_exists(storage: &Path, id: &str) -> bool {
    storage.join(format!("conversations/{id}.db")).exists()
        || storage.join(format!("brain/{id}")).exists()
        || storage.join(format!("annotations/{id}.pbtxt")).exists()
}

async fn seed_summaries(storage: &Path, rows: &[(&str, &str, i64)]) {
    let mut statements = vec![
        "CREATE TABLE conversation_summaries (conversation_id text, workspace_uris text NOT NULL, \
         not_fully_idle numeric NOT NULL DEFAULT false, PRIMARY KEY (conversation_id))"
            .to_string(),
    ];
    for (id, uris, busy) in rows {
        statements.push(format!(
            "INSERT INTO conversation_summaries VALUES ('{id}', '{uris}', {busy})"
        ));
    }
    let statements = statements.iter().map(String::as_str).collect::<Vec<_>>();
    sqlite_fixture(&storage.join("conversation_summaries.db"), &statements).await;
}

#[test]
fn workspace_uris_decode_to_exact_paths() {
    assert_eq!(
        workspace_paths("[\"file:///work/my%20app/\"]"),
        vec!["/work/my app".to_string()]
    );
    assert!(workspace_paths("").is_empty());
    assert!(workspace_paths("[\"https://example.com\"]").is_empty());
}

#[tokio::test]
async fn path_scope_removes_idle_conversations_of_the_exact_workspace() {
    let fixture = Fixture::new();
    let storage = fixture.home().join(".gemini/antigravity-cli");
    for id in ["mine", "busy", "sibling", "multi", "registered", "kept"] {
        seed_conversation(&storage, id);
    }
    seed_summaries(
        &storage,
        &[
            ("mine", "[\"file:///work/app\"]", 0),
            ("busy", "[\"file:///work/app\"]", 1),
            ("sibling", "[\"file:///work/app-sibling\"]", 0),
            ("multi", "[\"file:///work/app\",\"file:///work/other\"]", 0),
            ("kept", "[\"file:///work/app\"]", 0),
        ],
    )
    .await;

    let outcomes = fixture
        .run_preserving(
            WorkspacePath,
            "/work/app",
            vec![session("agy", "registered")],
            vec![session("agy", "kept")],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "agy", PATH_TARGET).result, Ok(()));
    assert_eq!(outcome_for(&outcomes, "agy", "registered").result, Ok(()));
    assert!(outcome_for(&outcomes, "agy", "busy").result.is_err());
    assert!(!conversation_exists(&storage, "mine"));
    assert!(!conversation_exists(&storage, "registered"));
    assert!(!storage.join("conversations/mine.db-wal").exists());
    for kept in ["busy", "sibling", "multi", "kept"] {
        assert!(conversation_exists(&storage, kept), "{kept}");
    }
    assert!(storage.join("conversation_summaries.db").exists());
}

#[tokio::test]
async fn an_unreadable_index_still_removes_registered_conversations() {
    let fixture = Fixture::new();
    let storage = fixture.home().join(".gemini/antigravity-cli");
    seed_conversation(&storage, "registered");
    sqlite_fixture(
        &storage.join("conversation_summaries.db"),
        &["CREATE TABLE something_else (id text)"],
    )
    .await;

    let outcomes = fixture
        .run(
            WorkspacePath,
            "/work/app",
            vec![session("agy", "registered")],
        )
        .await;

    assert!(outcome_for(&outcomes, "agy", PATH_TARGET).result.is_err());
    assert_eq!(outcome_for(&outcomes, "agy", "registered").result, Ok(()));
    assert!(!conversation_exists(&storage, "registered"));
}
