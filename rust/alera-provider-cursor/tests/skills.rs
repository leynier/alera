use alera_provider_cursor::{discover_skills, discover_skills_lenient};
use alera_provider_protocol::ProviderSkill;
use std::fs;
use std::path::{Path, PathBuf};

fn fixture(name: &str) -> (PathBuf, PathBuf) {
    let root = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join("cursor-skills")
        .join(name);
    let _ = fs::remove_dir_all(&root);
    let cwd = root.join("workspace");
    let home = root.join("home");
    fs::create_dir_all(&cwd).unwrap();
    fs::create_dir_all(&home).unwrap();
    (cwd, home)
}

fn write_skill(directory: &Path, contents: &str) -> PathBuf {
    fs::create_dir_all(directory).unwrap();
    let path = directory.join("SKILL.md");
    fs::write(&path, contents).unwrap();
    path
}

fn names(skills: &[ProviderSkill]) -> Vec<(&str, Option<&str>)> {
    skills
        .iter()
        .map(|skill| (skill.name.as_str(), skill.scope.as_deref()))
        .collect()
}

#[test]
fn reads_every_root_with_project_skills_winning_and_sorted() {
    let (cwd, home) = fixture("roots");
    let review = write_skill(
        &cwd.join(".cursor/skills/review"),
        "---\nname: Code Review\ndescription: Review changes.\n---\n# Review\n",
    );
    write_skill(
        &home.join(".cursor/skills/review"),
        "---\nname: review\n---\n",
    );
    write_skill(&cwd.join(".agents/skills/Zeta"), "# no frontmatter\n");
    write_skill(
        &cwd.join(".codex/skills/nested/deep/alpha"),
        "---\nname: alpha\n---\n",
    );
    write_skill(
        &home.join(".claude/skills/beta"),
        "---\ndescription: \"  \"\n---\n",
    );
    write_skill(
        &home.join(".cursor/skills-cursor/create-rule"),
        "---\nname: create-rule\n---\n",
    );
    write_skill(
        &home.join(".cursor/skills-cursor/beta"),
        "---\nname: beta\n---\n",
    );

    let skills = discover_skills(Some(&cwd), &home).unwrap();
    assert_eq!(
        names(&skills),
        vec![
            ("alpha", Some("project")),
            ("beta", Some("user")),
            ("create-rule", Some("system")),
            ("review", Some("project")),
            ("Zeta", Some("project")),
        ]
    );
    let first = &skills[3];
    assert_eq!(first.path, review.to_string_lossy());
    assert_eq!(first.display_name.as_deref(), Some("Code Review"));
    assert_eq!(first.description.as_deref(), Some("Review changes."));
    assert!(first.enabled);
    assert_eq!(skills[0].display_name, None);
    assert_eq!(skills[1].description, None);

    let user_only = discover_skills(None, &home).unwrap();
    assert_eq!(
        names(&user_only),
        vec![
            ("beta", Some("user")),
            ("create-rule", Some("system")),
            ("review", Some("user")),
        ]
    );
}

#[test]
fn honors_cli_surfaces_invocation_flags_and_invalid_frontmatter() {
    let (cwd, home) = fixture("frontmatter");
    let root = cwd.join(".cursor/skills");
    write_skill(
        &root.join("cli-list"),
        "---\nmetadata:\n  surfaces: [ide, CLI]\n---\n",
    );
    write_skill(
        &root.join("cli-text"),
        "---\nmetadata:\n  surfaces: \"ide, cli \"\n---\n",
    );
    write_skill(
        &root.join("ide-only"),
        "---\nmetadata:\n  surfaces: [ide]\n---\n",
    );
    write_skill(
        &root.join("empty-surface"),
        "---\nmetadata:\n  surfaces: \"\"\n---\n",
    );
    write_skill(&root.join("broken"), "---\nname: [unclosed\n---\n");
    write_skill(&root.join("scalar"), "---\n42\n---\n");
    write_skill(
        &root.join("manual"),
        "---\ndisable-model-invocation: yes\nuser-invocable: \"off\"\n---\n",
    );
    write_skill(
        &root.join("flags"),
        "---\ndisable-model-invocation: y\nuser-invocable: 1\n---\n",
    );

    let skills = discover_skills(Some(&cwd), &home).unwrap();
    assert_eq!(
        skills
            .iter()
            .map(|skill| skill.name.as_str())
            .collect::<Vec<_>>(),
        vec!["cli-list", "cli-text", "flags", "manual"]
    );
    let flags = &skills[2];
    assert_eq!(flags.user_invocation_only, None);
    assert_eq!(flags.user_invocable, None);
    let manual = &skills[3];
    assert_eq!(manual.user_invocation_only, Some(true));
    assert_eq!(manual.user_invocable, Some(false));
    assert!(!manual.is_user_invocable());
}

#[test]
fn skips_node_modules_and_directories_deeper_than_ten() {
    let (cwd, home) = fixture("depth");
    let root = cwd.join(".cursor/skills");
    write_skill(
        &root.join("node_modules/pkg/hidden"),
        "---\nname: hidden\n---\n",
    );
    let mut deep = root.clone();
    for level in 1..=10 {
        deep = deep.join(format!("d{level}"));
    }
    write_skill(&deep, "---\nname: deepest\n---\n");
    write_skill(&deep.join("too-deep"), "---\nname: too-deep\n---\n");

    let skills = discover_skills(Some(&cwd), &home).unwrap();
    assert_eq!(
        skills
            .iter()
            .map(|skill| skill.name.as_str())
            .collect::<Vec<_>>(),
        vec!["d10"]
    );
}

#[test]
fn reports_an_exhausted_scan_budget_but_keeps_partial_results_leniently() {
    let (cwd, home) = fixture("budget");
    let root = cwd.join(".cursor/skills");
    write_skill(&root.join("aaa-first"), "---\nname: aaa-first\n---\n");
    let filler = root.join("filler");
    fs::create_dir_all(&filler).unwrap();
    for index in 0..10_001 {
        fs::write(filler.join(format!("f{index:05}")), "").unwrap();
    }

    let error = discover_skills(Some(&cwd), &home).unwrap_err();
    assert_eq!(
        error,
        format!(
            "Cursor skill discovery for '{}' was incomplete (scan-budget-exhausted).",
            cwd.display()
        )
    );
    let partial = discover_skills_lenient(Some(&cwd), Some(&home));
    assert_eq!(partial.len(), 1);
    assert_eq!(partial[0].name, "aaa-first");
}

#[cfg(unix)]
#[test]
fn outside_root_symlinks_expose_only_their_own_skill() {
    let (cwd, home) = fixture("symlinks");
    let outside = cwd.join("outside");
    write_skill(&outside, "---\nname: outside\n---\n");
    write_skill(&outside.join("inner"), "---\nname: inner\n---\n");
    let root = cwd.join(".cursor/skills");
    fs::create_dir_all(&root).unwrap();
    std::os::unix::fs::symlink(&outside, root.join("linked")).unwrap();
    fs::create_dir_all(cwd.join(".agents")).unwrap();
    std::os::unix::fs::symlink(&root, cwd.join(".agents/skills")).unwrap();

    let skills = discover_skills(Some(&cwd), &home).unwrap();
    assert_eq!(
        skills
            .iter()
            .map(|skill| skill.name.as_str())
            .collect::<Vec<_>>(),
        vec!["linked"]
    );
}
