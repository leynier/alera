use super::super::test_support::{outcome_for, session, write, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;

fn seed_session(config: &std::path::Path, id: &str) {
    write(&config.join(format!("projects/-work-app/{id}.jsonl")), "{}");
    write(
        &config.join(format!("projects/-work-app/{id}/subagents/a.jsonl")),
        "{}",
    );
    write(&config.join(format!("file-history/{id}/f@v1")), "x");
    write(&config.join(format!("session-env/{id}/env")), "x");
    write(&config.join(format!("tasks/{id}/1.json")), "x");
    write(&config.join(format!("debug/{id}.txt")), "x");
    write(&config.join(format!("todos/{id}-agent-{id}.json")), "[]");
}

#[tokio::test]
async fn per_session_removal_covers_every_session_artifact_and_nothing_else() {
    let fixture = Fixture::new();
    let config = fixture.home().join(".claude");
    seed_session(&config, "s1");
    seed_session(&config, "s2");

    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("claude", "s1")],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "claude", "s1").result, Ok(()));
    for gone in [
        "projects/-work-app/s1.jsonl",
        "projects/-work-app/s1",
        "file-history/s1",
        "session-env/s1",
        "tasks/s1",
        "debug/s1.txt",
        "todos/s1-agent-s1.json",
    ] {
        assert!(!config.join(gone).exists(), "{gone}");
    }
    assert!(config.join("projects/-work-app/s2.jsonl").exists());
    assert!(config.join("todos/s2-agent-s2.json").exists());
    assert!(fixture.commands().is_empty());
}

#[tokio::test]
async fn claude_config_dir_variable_relocates_the_store() {
    let mut fixture = Fixture::new();
    let config = fixture.temp.path().join("custom-claude");
    fixture
        .variables
        .insert("CLAUDE_CONFIG_DIR".into(), config.to_string_lossy().into());
    seed_session(&config, "s1");

    fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("claude", "s1")],
        )
        .await;

    assert!(!config.join("projects/-work-app/s1.jsonl").exists());
}

#[cfg(unix)]
#[tokio::test]
async fn ccs_profiles_reach_the_shared_store_through_symlinks() {
    let fixture = Fixture::new();
    let shared = fixture.home().join(".ccs/shared/context-groups/default");
    let instance = fixture.home().join(".ccs/instances/work");
    std::fs::create_dir_all(&instance).unwrap();
    seed_session(&shared, "s1");
    write(&shared.join("projects/-work-app/keep.jsonl"), "{}");
    for link in ["projects", "file-history", "todos"] {
        std::os::unix::fs::symlink(shared.join(link), instance.join(link)).unwrap();
    }
    let mut work_session = session("claude", "s1");
    work_session.ccs_profile = Some("work".into());

    let outcomes = fixture
        .run(RegisteredSessions, "/work/app", vec![work_session])
        .await;

    assert_eq!(outcome_for(&outcomes, "claude", "s1").result, Ok(()));
    assert!(!shared.join("projects/-work-app/s1.jsonl").exists());
    assert!(!shared.join("file-history/s1").exists());
    assert!(!shared.join("todos/s1-agent-s1.json").exists());
    assert!(shared.join("projects/-work-app/keep.jsonl").exists());
    assert!(instance.join("projects").is_symlink());
}

#[cfg(unix)]
#[tokio::test]
async fn a_project_symlink_escaping_the_store_is_refused() {
    let fixture = Fixture::new();
    let config = fixture.home().join(".claude");
    let outside = fixture.temp.path().join("outside");
    write(&outside.join("s1.jsonl"), "{}");
    std::fs::create_dir_all(config.join("projects")).unwrap();
    std::os::unix::fs::symlink(&outside, config.join("projects/-escape")).unwrap();

    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("claude", "s1")],
        )
        .await;

    assert!(outcome_for(&outcomes, "claude", "s1").result.is_err());
    assert!(outside.join("s1.jsonl").exists());
}

#[tokio::test]
async fn missing_ccs_profile_is_reported() {
    let fixture = Fixture::new();
    let mut profile_session = session("claude", "s1");
    profile_session.ccs_profile = Some("gone".into());
    let outcomes = fixture
        .run(RegisteredSessions, "/work/app", vec![profile_session])
        .await;
    assert!(outcome_for(&outcomes, "claude", "s1").result.is_err());
}

#[tokio::test]
async fn path_scope_purges_the_default_and_every_ccs_instance() {
    let fixture = Fixture::new();
    std::fs::create_dir_all(fixture.home().join(".claude")).unwrap();
    for name in ["alpha", "beta"] {
        std::fs::create_dir_all(fixture.home().join(".ccs/instances").join(name)).unwrap();
    }
    write(&fixture.home().join(".ccs/instances/beta.lock"), "");

    let outcomes = fixture.run(WorkspacePath, "/work/app", Vec::new()).await;

    assert_eq!(outcome_for(&outcomes, "claude", PATH_TARGET).result, Ok(()));
    let commands = fixture
        .commands()
        .into_iter()
        .filter(|command| command.program == "claude")
        .collect::<Vec<_>>();
    assert_eq!(commands.len(), 3);
    for command in &commands {
        assert_eq!(command.args, vec!["purge", "/work/app", "--yes"]);
    }
    assert!(commands[0].env.is_empty());
    let instance_dir = |name: &str| {
        fixture
            .home()
            .join(".ccs/instances")
            .join(name)
            .to_string_lossy()
            .into_owned()
    };
    assert_eq!(commands[1].env["CLAUDE_CONFIG_DIR"], instance_dir("alpha"));
    assert_eq!(commands[2].env["CLAUDE_CONFIG_DIR"], instance_dir("beta"));
}

#[tokio::test]
async fn path_scope_without_any_claude_store_runs_nothing() {
    let fixture = Fixture::new();
    let outcomes = fixture.run(WorkspacePath, "/work/app", Vec::new()).await;
    assert!(!outcomes
        .iter()
        .any(|outcome| outcome.agent_type == "claude"));
    assert!(!fixture.argv().iter().any(|argv| argv.starts_with("claude")));
}
