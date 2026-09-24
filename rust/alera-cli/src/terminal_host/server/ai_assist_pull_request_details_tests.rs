use alera_core::source_control::{GitRangeCommit, GitRangeFile};

use super::*;

fn range(head_branch: Option<&str>) -> GitRangeContext {
    GitRangeContext {
        base_ref: "main".into(),
        head_oid: "abcdef1234567".into(),
        head_branch: head_branch.map(ToOwned::to_owned),
        merge_base: Some("0123456".into()),
        commits: vec![GitRangeCommit {
            oid: "abcdef1234567".into(),
            subject: "Add pull request actions".into(),
            message: "Add pull request actions".into(),
        }],
        files: vec![GitRangeFile {
            path: "lib/a.dart".into(),
            status: GitChangeStatus::Modified,
            added: Some(3),
            removed: Some(1),
        }],
        patch: "diff --git a/lib/a.dart b/lib/a.dart\n+x".into(),
    }
}

#[test]
fn builds_the_desktop_prompt_from_the_range() {
    let prompt =
        pull_request_details_prompt("main", &range(Some("feat/x")), " Mention tests ").unwrap();
    assert!(
        prompt.starts_with("You are generating a GitHub-style pull request title and description.")
    );
    assert!(prompt.contains("Base branch: main\nHead branch: feat/x"));
    assert!(prompt.contains("- abcdef1 Add pull request actions"));
    assert!(prompt.contains("- M lib/a.dart (+3 -1)"));
    assert!(prompt.contains("```diff\ndiff --git a/lib/a.dart b/lib/a.dart\n+x\n```"));
    assert!(prompt.ends_with("Additional user instructions:\nMention tests"));
}

#[test]
fn refuses_an_empty_range_or_the_base_itself() {
    let mut empty = range(Some("feat/x"));
    empty.commits.clear();
    empty.files.clear();
    empty.patch.clear();
    assert!(pull_request_details_prompt("main", &empty, "").is_err());
    assert!(pull_request_details_prompt("main", &range(Some("main")), "").is_err());
}

#[test]
fn parses_the_title_and_body_like_desktop() {
    let details = parse_pull_request_details("Add mobile actions.\n\n- Merge\n- Comment\n");
    assert_eq!(details.title, "Add mobile actions");
    assert_eq!(details.body.as_deref(), Some("- Merge\n- Comment"));

    let only_title = parse_pull_request_details("```\nFix crash\n```");
    assert_eq!(only_title.title, "Fix crash");
    assert_eq!(only_title.body, None);

    assert_eq!(parse_pull_request_details("   ").title, "Update Project");
    assert_eq!(parse_pull_request_details(&"x".repeat(90)).title.len(), 72);
}
