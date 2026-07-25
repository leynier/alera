use chrono::Utc;

use super::{AgentProfile, RuntimeStore};

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
    raw.description = "  Backend work  ".to_string();
    raw.quota_group = Some("   ".to_string());

    let stored = store.upsert_agent_profile(raw).await.unwrap();
    assert_eq!(stored.name, "Codex Sol");
    assert_eq!(stored.command, "codex");
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
