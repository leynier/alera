mod skill_fixtures;

use alera_provider_claude::{discover_skills, ClaudeProviderConfig};
use skill_fixtures::*;

fn enabled(config: &ClaudeProviderConfig) -> Vec<(String, bool)> {
    discover_skills(config)
        .into_iter()
        .map(|skill| (skill.name, skill.enabled))
        .collect()
}

fn pairs(expected: &[(&str, bool)]) -> Vec<(String, bool)> {
    expected
        .iter()
        .map(|(name, enabled)| (name.to_string(), *enabled))
        .collect()
}

fn write_named_skills(config_dir: &std::path::Path, names: &[&str]) {
    for name in names {
        write_skill(
            &config_dir.join("skills"),
            name,
            &format!("---\nname: {name}\n---\n\n# Body"),
        );
    }
}

#[test]
fn disables_skills_switched_off_by_skill_overrides() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let workspace = temp.join("workspace");
    write_named_skills(&config_dir, &["kept", "off-by-user", "off-by-project"]);
    write(
        &config_dir.join("settings.json"),
        r#"{ "skillOverrides": { "off-by-user": "off", "kept": "on" } }"#,
    );
    write(
        &workspace.join(".claude/settings.json"),
        r#"{ "skillOverrides": { "off-by-project": "off" } }"#,
    );
    assert_eq!(
        enabled(&config(&config_dir, Some(&workspace))),
        pairs(&[
            ("kept", true),
            ("off-by-project", false),
            ("off-by-user", false)
        ])
    );
}

#[test]
fn reads_settings_with_comments_and_trailing_commas() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    write_named_skills(&config_dir, &["kept", "off"]);
    write(
        &config_dir.join("settings.json"),
        "{\n  // hand-edited\n  \"skillOverrides\": {\n    \"off\": \"off\", /* why */\n  },\n}\n",
    );
    assert_eq!(
        enabled(&config(&config_dir, None)),
        pairs(&[("kept", true), ("off", false)])
    );
}

#[test]
fn ignores_unreadable_settings_when_resolving_skill_overrides() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    write_named_skills(&config_dir, &["kept"]);
    write(&config_dir.join("settings.json"), "{ not json");
    assert_eq!(
        enabled(&config(&config_dir, None)),
        pairs(&[("kept", true)])
    );
}

#[test]
fn treats_a_user_invocable_only_override_like_disable_model_invocation() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    write_named_skills(&config_dir, &["ask-matt"]);
    write(
        &config_dir.join("settings.json"),
        r#"{ "skillOverrides": { "ask-matt": "user-invocable-only" } }"#,
    );
    let skills = discover_skills(&config(&config_dir, None));
    assert_eq!(skills.len(), 1);
    assert!(skills[0].enabled);
    assert_eq!(skills[0].user_invocation_only, Some(true));
}

#[test]
fn drops_every_override_in_a_file_when_one_value_is_invalid() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let workspace = temp.join("workspace");
    write_named_skills(
        &config_dir,
        &[
            "unknown-mode",
            "boolean-false",
            "sibling-off",
            "project-off",
        ],
    );
    // Claude ignores the entire override map when any value is an unknown string or boolean.
    write(
        &config_dir.join("settings.json"),
        r#"{ "skillOverrides": { "unknown-mode": "some-future-mode", "boolean-false": false, "sibling-off": "off" } }"#,
    );
    // Another file's valid map still applies.
    write(
        &workspace.join(".claude/settings.json"),
        r#"{ "skillOverrides": { "project-off": "off" } }"#,
    );
    assert_eq!(
        enabled(&config(&config_dir, Some(&workspace))),
        pairs(&[
            ("boolean-false", true),
            ("project-off", false),
            ("sibling-off", true),
            ("unknown-mode", true)
        ])
    );
}

#[test]
fn reads_repository_root_settings_from_a_nested_workspace() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let repo = temp.join("repo");
    let workspace = repo.join("packages/app");
    write_named_skills(
        &config_dir,
        &["root-off", "root-off-cwd-on", "cwd-off-root-on"],
    );
    mkdir(&repo.join(".git"));
    // The CLI ignores the root's plain settings.json from a nested cwd.
    write(
        &repo.join(".claude/settings.json"),
        r#"{ "skillOverrides": { "cwd-off-root-on": "off" } }"#,
    );
    // The root local file outranks the workspace local file, as in the CLI.
    write(
        &repo.join(".claude/settings.local.json"),
        r#"{ "skillOverrides": { "root-off": "off", "root-off-cwd-on": "off", "cwd-off-root-on": "on" } }"#,
    );
    write(
        &workspace.join(".claude/settings.local.json"),
        r#"{ "skillOverrides": { "root-off-cwd-on": "on", "cwd-off-root-on": "off" } }"#,
    );
    assert_eq!(
        enabled(&config(&config_dir, Some(&workspace))),
        pairs(&[
            ("cwd-off-root-on", true),
            ("root-off", false),
            ("root-off-cwd-on", false)
        ])
    );
}

#[test]
fn ignores_ancestor_settings_outside_a_repository() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let parent = temp.join("not-a-repo");
    let workspace = parent.join("workspace");
    write_named_skills(&config_dir, &["kept"]);
    mkdir(&workspace);
    write(
        &parent.join(".claude/settings.local.json"),
        r#"{ "skillOverrides": { "kept": "off" } }"#,
    );
    assert_eq!(
        enabled(&config(&config_dir, Some(&workspace))),
        pairs(&[("kept", true)])
    );
}

#[test]
fn switches_a_skill_off_by_its_directory_name_not_its_frontmatter_name() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    write_skill(
        &config_dir.join("skills"),
        "probe-alias",
        "---\nname: probe-alias-frontmatter\n---\n\n# Body",
    );
    write(
        &config_dir.join("settings.json"),
        r#"{ "skillOverrides": { "probe-alias-frontmatter": "off" } }"#,
    );
    assert_eq!(
        enabled(&config(&config_dir, None)),
        pairs(&[("probe-alias", true)])
    );
    write(
        &config_dir.join("settings.json"),
        r#"{ "skillOverrides": { "probe-alias": "off" } }"#,
    );
    assert_eq!(
        enabled(&config(&config_dir, None)),
        pairs(&[("probe-alias", false)])
    );
}
