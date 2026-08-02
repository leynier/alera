use chrono::Utc;
use serde_json::json;
use sqlx::sqlite::SqliteConnectOptions;

use super::{AgentProfile, AgentProfileLaunchMode, RuntimeStore, RUNTIME_DATABASE_FILE_NAME};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn profile(id: &str, name: &str) -> AgentProfile {
    let now = Utc::now();
    AgentProfile {
        id: id.to_string(),
        name: name.to_string(),
        agent_type: "codex".to_string(),
        command: "codex".to_string(),
        launch_mode: AgentProfileLaunchMode::Command,
        managed_config: None,
        custom_prompt: String::new(),
        description: String::new(),
        quota_group: None,
        created_at: now,
        updated_at: now,
    }
}

#[tokio::test]
async fn upserts_and_lists_profiles_by_name() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_b", "Zed Runner"))
        .await
        .unwrap();
    store
        .upsert_agent_profile(profile("prof_a", "Alpha Runner"))
        .await
        .unwrap();

    let profiles = store.list_agent_profiles().await.unwrap();
    let names: Vec<_> = profiles.iter().map(|item| item.name.as_str()).collect();
    assert_eq!(names, ["Alpha Runner", "Zed Runner"]);
}

#[tokio::test]
async fn resolves_a_profile_by_name_case_insensitively() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_a", "Codex Sol"))
        .await
        .unwrap();

    let found = store.agent_profile_by_name("codex sol").await.unwrap();
    assert_eq!(found.unwrap().id, "prof_a");
    assert!(store
        .agent_profile_by_name("missing")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn rejects_a_duplicate_name_from_another_profile() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_a", "Codex Sol"))
        .await
        .unwrap();

    let error = store
        .upsert_agent_profile(profile("prof_b", "codex sol"))
        .await
        .unwrap_err();
    assert!(
        error.to_string().contains("already exists"),
        "unexpected error: {error}"
    );
}

#[tokio::test]
async fn updating_the_same_profile_keeps_its_own_name() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_a", "Codex Sol"))
        .await
        .unwrap();

    let mut updated = profile("prof_a", "Codex Sol");
    updated.command = "codex --model gpt-5.6-sol".to_string();
    let stored = store.upsert_agent_profile(updated).await.unwrap();
    assert_eq!(stored.command, "codex --model gpt-5.6-sol");
    assert_eq!(store.list_agent_profiles().await.unwrap().len(), 1);
}

#[tokio::test]
async fn trims_fields_and_drops_a_blank_quota_group() {
    let (_dir, store) = store().await;
    let mut raw = profile("prof_a", "  Codex Sol  ");
    raw.command = "  codex  ".to_string();
    raw.custom_prompt = "  Always Explain The Tradeoffs  ".to_string();
    raw.description = "  Backend work  ".to_string();
    raw.quota_group = Some("   ".to_string());

    let stored = store.upsert_agent_profile(raw).await.unwrap();
    assert_eq!(stored.name, "Codex Sol");
    assert_eq!(stored.command, "codex");
    assert_eq!(stored.custom_prompt, "Always Explain The Tradeoffs");
    assert_eq!(stored.description, "Backend work");
    assert_eq!(stored.quota_group, None);
}

#[tokio::test]
async fn rejects_empty_required_fields() {
    let (_dir, store) = store().await;
    let mut blank_name = profile("prof_a", "   ");
    blank_name.command = "codex".to_string();
    assert!(store.upsert_agent_profile(blank_name).await.is_err());

    let mut blank_command = profile("prof_b", "Codex Sol");
    blank_command.command = "   ".to_string();
    assert!(store.upsert_agent_profile(blank_command).await.is_err());
}

#[tokio::test]
async fn round_trips_managed_configuration() {
    let (_dir, store) = store().await;
    let mut managed = profile("prof_managed", "Managed Codex");
    managed.command = "codex --model gpt-5.6-sol --search".to_string();
    managed.launch_mode = AgentProfileLaunchMode::Managed;
    managed.managed_config = Some(json!({
        "model": "gpt-5.6-sol",
        "webSearch": true
    }));

    let stored = store.upsert_agent_profile(managed).await.unwrap();
    assert_eq!(stored.launch_mode, AgentProfileLaunchMode::Managed);
    assert_eq!(
        stored.managed_config,
        Some(json!({"model": "gpt-5.6-sol", "webSearch": true}))
    );
}

#[tokio::test]
async fn command_profiles_discard_managed_configuration() {
    let (_dir, store) = store().await;
    let mut command = profile("prof_command", "Command Codex");
    command.managed_config = Some(json!({"model": "ignored"}));

    let stored = store.upsert_agent_profile(command).await.unwrap();
    assert_eq!(stored.launch_mode, AgentProfileLaunchMode::Command);
    assert_eq!(stored.managed_config, None);
}

#[tokio::test]
async fn migrates_existing_profiles_to_command_mode() {
    let dir = tempfile::tempdir().unwrap();
    let options = SqliteConnectOptions::new()
        .filename(dir.path().join(RUNTIME_DATABASE_FILE_NAME))
        .create_if_missing(true);
    let pool = sqlx::SqlitePool::connect_with(options).await.unwrap();
    sqlx::query(
        "CREATE TABLE agentProfiles (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            agentType TEXT NOT NULL,
            command TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            quotaGroup TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
        )",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO agentProfiles
         (id, name, agentType, command, description, createdAt, updatedAt)
         VALUES ('prof_legacy', 'Legacy Codex', 'codex', 'codex --search', '', ?, ?)",
    )
    .bind("2026-07-01T00:00:00.000Z")
    .bind("2026-07-01T00:00:00.000Z")
    .execute(&pool)
    .await
    .unwrap();
    pool.close().await;

    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let profile = store
        .find_agent_profile("prof_legacy")
        .await
        .unwrap()
        .unwrap();

    assert_eq!(profile.launch_mode, AgentProfileLaunchMode::Command);
    assert_eq!(profile.command, "codex --search");
    assert_eq!(profile.managed_config, None);
    assert_eq!(profile.custom_prompt, "");
}

#[tokio::test]
async fn rejects_managed_configuration_that_is_not_an_object() {
    let (_dir, store) = store().await;
    let mut managed = profile("prof_managed", "Managed Codex");
    managed.launch_mode = AgentProfileLaunchMode::Managed;
    managed.managed_config = Some(json!(["not", "an", "object"]));

    assert!(store.upsert_agent_profile(managed).await.is_err());
}

#[tokio::test]
async fn removes_a_profile_and_reports_whether_it_existed() {
    let (_dir, store) = store().await;
    store
        .upsert_agent_profile(profile("prof_a", "Codex Sol"))
        .await
        .unwrap();

    assert!(store.remove_agent_profile("prof_a").await.unwrap());
    assert!(!store.remove_agent_profile("prof_a").await.unwrap());
    assert!(store.list_agent_profiles().await.unwrap().is_empty());
}
