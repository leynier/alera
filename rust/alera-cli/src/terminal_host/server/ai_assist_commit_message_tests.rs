use std::fs;

use super::super::mobile_source_control_snapshot::tests::{init_repo, run_git};
use super::*;

#[test]
fn context_lists_staged_files_and_their_patch_only() {
    let repo = tempfile::tempdir().unwrap();
    init_repo(repo.path());
    fs::write(repo.path().join("tracked.txt"), "two\n").unwrap();
    fs::write(repo.path().join("staged.txt"), "new\n").unwrap();
    fs::write(repo.path().join("ignored-by-prompt.txt"), "not staged\n").unwrap();
    run_git(repo.path(), &["add", "tracked.txt", "staged.txt"]);

    let context = commit_context(&repo.path().to_string_lossy()).unwrap();

    assert_eq!(context.branch.as_deref(), Some("main"));
    assert_eq!(
        context.staged_summary,
        "- staged.txt (+1 -0)\n- tracked.txt (+1 -1)"
    );
    assert!(context
        .staged_patch
        .contains("diff --git a/tracked.txt b/tracked.txt"));
    assert!(context.staged_patch.contains("+two"));
    assert!(!context.staged_patch.contains("ignored-by-prompt"));
}

#[test]
fn context_without_staged_changes_is_refused() {
    let repo = tempfile::tempdir().unwrap();
    init_repo(repo.path());
    fs::write(repo.path().join("tracked.txt"), "two\n").unwrap();

    let error = commit_context(&repo.path().to_string_lossy())
        .err()
        .unwrap();

    assert_eq!(error.wire_message(), "No staged changes to summarize.");
}

#[test]
fn prompt_matches_the_desktop_shape() {
    let context = CommitContext {
        branch: None,
        staged_summary: "- a.txt (+1)".to_string(),
        staged_patch: "diff --git a/a.txt b/a.txt\n+hello".to_string(),
    };

    let prompt = commit_message_prompt(&context, "  Use conventional commits.  ");

    assert!(prompt.starts_with("You are generating a single git commit message.\n"));
    assert!(prompt.contains("\nBranch: (detached)\n"));
    assert!(prompt.contains("\nStaged files:\n- a.txt (+1)\n"));
    assert!(prompt.contains("```diff\ndiff --git a/a.txt b/a.txt\n+hello\n```"));
    assert!(prompt.ends_with("\n\nAdditional user instructions:\nUse conventional commits."));
    assert!(!commit_message_prompt(&context, " ").contains("Additional user instructions"));
}

#[test]
fn prompt_sections_are_truncated_by_characters() {
    assert_eq!(limit_prompt_section("abcdef", 6), "abcdef");
    assert_eq!(
        limit_prompt_section("ñandú", 3),
        "ñan\n\n[truncated: 2 characters omitted]"
    );
    let patch = "x".repeat(STAGED_PATCH_BUDGET + 5);
    assert!(
        truncate_diff_for_prompt(&patch).ends_with("\n...(diff truncated, 5 characters omitted)")
    );
}

#[test]
fn generated_messages_are_cleaned_like_desktop() {
    let cases = [
        ("Add login flow.", "Add login flow"),
        ("  \r\n", "Update project files"),
        ("Thinking...\nFix crash on start", "Fix crash on start"),
        ("…\nFix crash on start", "Fix crash on start"),
        (
            "```text\nRefactor parser\n\n- split lexer\n```",
            "Refactor parser\n\n- split lexer",
        ),
        (
            "Generating the message\nShip it\n\nBecause users asked.",
            "Ship it\n\nBecause users asked.",
        ),
        ("Thinkpad support", "Thinkpad support"),
    ];
    for (raw, expected) in cases {
        assert_eq!(clean_generated_commit_message(raw), expected, "{raw:?}");
    }
    let long = "a".repeat(80);
    assert_eq!(clean_generated_commit_message(&long), "a".repeat(72));
}
