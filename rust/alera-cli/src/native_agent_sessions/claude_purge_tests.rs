use super::super::test_support::{outcome_for, session, write, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;
use super::project_dir_name;

#[test]
fn project_directory_names_match_claude() {
    assert_eq!(
        project_dir_name("/home/user/.t3/worktrees/alera/t3-63ebf21a"),
        "-home-user--t3-worktrees-alera-t3-63ebf21a"
    );
    assert_eq!(project_dir_name("C:\\work\\app"), "C--work-app");
    assert_eq!(project_dir_name("/a/\u{1F600}"), "-a---");
}

#[tokio::test]
async fn a_preserved_session_turns_the_purge_into_per_session_removal() {
    let fixture = Fixture::new();
    let config = fixture.home().join(".claude");
    let project = config.join("projects/-work-app");
    write(&project.join("keep.jsonl"), "{}");
    write(&project.join("drop.jsonl"), "{}");
    write(&project.join("drop/subagents/a.jsonl"), "{}");
    write(&config.join("file-history/drop/f"), "x");
    write(&config.join("file-history/keep/f"), "x");
    let sibling = config.join("projects/-work-app-sibling");
    write(&sibling.join("other.jsonl"), "{}");

    let outcomes = fixture
        .run_preserving(
            WorkspacePath,
            "/work/app",
            Vec::new(),
            vec![session("claude", "keep")],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "claude", PATH_TARGET).result, Ok(()));
    assert!(!fixture.argv().iter().any(|argv| argv.starts_with("claude")));
    assert!(project.join("keep.jsonl").exists());
    assert!(config.join("file-history/keep").exists());
    assert!(!project.join("drop.jsonl").exists());
    assert!(!project.join("drop").exists());
    assert!(!config.join("file-history/drop").exists());
    assert!(sibling.join("other.jsonl").exists());
}

#[tokio::test]
async fn a_preserved_session_of_another_project_still_allows_the_purge() {
    let fixture = Fixture::new();
    let config = fixture.home().join(".claude");
    write(&config.join("projects/-work-other/keep.jsonl"), "{}");

    let outcomes = fixture
        .run_preserving(
            WorkspacePath,
            "/work/app",
            Vec::new(),
            vec![session("claude", "keep")],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "claude", PATH_TARGET).result, Ok(()));
    assert!(fixture
        .argv()
        .contains(&"claude purge /work/app --yes".to_string()));
}

#[tokio::test]
async fn a_hashed_project_holding_a_preserved_session_is_left_alone() {
    let fixture = Fixture::new();
    let config = fixture.home().join(".claude");
    let long_path = format!("/work/{}", "a".repeat(240));
    let name = project_dir_name(&long_path);
    let hashed = config
        .join("projects")
        .join(format!("{}-1x2y3z", &name[..200]));
    write(&hashed.join("keep.jsonl"), "{}");
    write(&hashed.join("drop.jsonl"), "{}");

    let outcomes = fixture
        .run_preserving(
            WorkspacePath,
            &long_path,
            Vec::new(),
            vec![session("claude", "keep")],
        )
        .await;

    assert!(outcome_for(&outcomes, "claude", PATH_TARGET)
        .result
        .is_err());
    assert!(!fixture.argv().iter().any(|argv| argv.starts_with("claude")));
    assert!(hashed.join("drop.jsonl").exists());
}
