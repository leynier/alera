mod skill_fixtures;

use alera_provider_claude::{discover_skills, plan_claude_skill_dispatch, user_invocable_skills};
use serde_json::{json, Value};
use skill_fixtures::*;

fn discovered(config: &alera_provider_claude::ClaudeProviderConfig) -> Value {
    serde_json::to_value(discover_skills(config)).unwrap()
}

fn names(config: &alera_provider_claude::ClaudeProviderConfig) -> Vec<String> {
    discover_skills(config)
        .into_iter()
        .map(|skill| skill.name)
        .collect()
}

#[test]
fn discovers_user_and_project_skills_with_frontmatter_metadata() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let workspace = temp.join("workspace");
    write_skill(
        &config_dir.join("skills"),
        "codex-review",
        "---\nname: codex-review\ndescription: Ask Codex for a review.\n---\n\n# Body",
    );
    write_skill(
        &workspace.join(".claude/skills"),
        "deploy",
        "---\nname: deploy\ndescription: Deploy the app.\n---\n\n# Deploy",
    );
    assert_eq!(
        discovered(&config(&config_dir, Some(&workspace))),
        json!([
            {
                "name": "codex-review",
                "path": skill_path(&config_dir.join("skills"), "codex-review"),
                "enabled": true,
                "scope": "user",
                "description": "Ask Codex for a review."
            },
            {
                "name": "deploy",
                "path": skill_path(&workspace.join(".claude/skills"), "deploy"),
                "enabled": true,
                "scope": "project",
                "description": "Deploy the app."
            }
        ])
    );
}

#[test]
fn discovers_skills_from_add_dirs_and_the_add_dir_extra_argument() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let workspace = temp.join("workspace");
    let extra_dir = workspace.join("extra skills");
    mkdir(&workspace);
    write_skill(
        &extra_dir.join(".claude/skills"),
        "demo",
        "---\ndescription: From an additional directory.\n---",
    );
    assert!(discover_skills(&config(&config_dir, Some(&workspace))).is_empty());
    let expected = json!([{
        "name": "demo",
        "path": skill_path(&extra_dir.join(".claude/skills"), "demo"),
        "enabled": true,
        "scope": "project",
        "description": "From an additional directory."
    }]);
    let mut absolute = config(&config_dir, Some(&workspace));
    absolute.options.add_dirs = vec![extra_dir.clone()];
    assert_eq!(discovered(&absolute), expected);
    let mut relative = config(&config_dir, Some(&workspace));
    relative.options.add_dirs = vec!["missing".into(), "extra skills".into()];
    assert_eq!(discovered(&relative), expected);
    for value in [
        extra_dir.to_string_lossy().into_owned(),
        "extra skills".into(),
    ] {
        let mut extra = config(&config_dir, Some(&workspace));
        extra
            .options
            .extra_args
            .insert("add-dir".into(), Some(value));
        assert_eq!(discovered(&extra), expected);
    }

    let skills = user_invocable_skills(discover_skills(&absolute));
    let dispatch = plan_claude_skill_dispatch("$demo", &skills).unwrap();
    assert_eq!(dispatch.leading_text, None);
    assert_eq!(dispatch.command_text, "/demo");
    assert_eq!(dispatch.skill_name, "demo");

    write_skill(
        &workspace.join(".claude/skills"),
        "demo",
        "---\ndescription: Project copy.\n---",
    );
    assert_eq!(
        discover_skills(&absolute)[0].description.as_deref(),
        Some("Project copy.")
    );
    // A relative or empty directory without a cwd names nothing.
    let mut relative_without_cwd = config(&config_dir, None);
    relative_without_cwd.options.add_dirs = vec!["extra skills".into()];
    assert!(discover_skills(&relative_without_cwd).is_empty());
    for value in [None, Some(String::new())] {
        let mut empty = config(&config_dir, None);
        empty.options.extra_args.insert("add-dir".into(), value);
        assert!(discover_skills(&empty).is_empty());
    }
}

#[test]
fn prefers_user_skills_on_name_collisions_even_with_a_stray_agents_copy() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let workspace = temp.join("workspace");
    write_skill(
        &config_dir.join("skills"),
        "deploy",
        "---\nname: deploy\ndescription: User deploy.\n---",
    );
    write_skill(
        &workspace.join(".agents/skills"),
        "deploy",
        "---\nname: deploy\ndescription: Agents deploy.\n---",
    );
    write_skill(
        &workspace.join(".claude/skills"),
        "deploy",
        "---\nname: deploy\ndescription: Claude deploy.\n---",
    );
    assert_eq!(
        discovered(&config(&config_dir, Some(&workspace))),
        json!([{
            "name": "deploy",
            "path": skill_path(&config_dir.join("skills"), "deploy"),
            "enabled": true,
            "scope": "user",
            "description": "User deploy."
        }])
    );
}

#[test]
fn recovers_colon_bearing_descriptions_with_invocation_metadata_intact() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    for (description, comment) in [
        (
            "Browser automation + AI test authoring via kane-cli: run browser objectives, ...",
            "",
        ),
        (
            "Read C:\\skills\\guide#tag: continue with \"quoted\".",
            " # trailing: comment",
        ),
    ] {
        write_skill(
            &config_dir.join("skills"),
            "kane-cli",
            &format!(
                "---\nname: frontmatter-alias\ndescription: {description}{comment}\nallowed-tools: [Read, Write]\ndisable-model-invocation: yes\nuser-invocable: no\n---"
            ),
        );
        assert_eq!(
            discovered(&config(&config_dir, None)),
            json!([{
                "name": "kane-cli",
                "path": skill_path(&config_dir.join("skills"), "kane-cli"),
                "enabled": true,
                "scope": "user",
                "description": description,
                "userInvocationOnly": true,
                "userInvocable": false
            }])
        );
    }
}

#[test]
fn falls_back_to_the_directory_name_and_skips_malformed_frontmatter() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let skills_dir = config_dir.join("skills");
    write_skill(&skills_dir, "no-frontmatter", "# Just a heading\n");
    for (directory_name, field) in [
        ("broken-yaml", "name: [unclosed"),
        ("broken-tools", "allowed-tools: [Read, Write"),
        ("broken-quoted", "name: \"unclosed: text"),
    ] {
        write_skill(
            &skills_dir,
            directory_name,
            &format!("---\ndescription: Run: browser objectives.\n{field}\n---"),
        );
    }
    write(&skills_dir.join("README.md"), "not a skill");
    let skills = discover_skills(&config(&config_dir, None));
    assert_eq!(
        skills
            .iter()
            .map(|skill| skill.name.as_str())
            .collect::<Vec<_>>(),
        ["no-frontmatter"]
    );
    assert_eq!(skills[0].description, None);
}

#[test]
fn honors_claude_config_dir_from_the_options_environment() {
    let temp = TempDir::new();
    let config_dir = temp.join("env-config");
    write_skill(
        &config_dir.join("skills"),
        "env-skill",
        "---\nname: env-skill\ndescription: From env config dir.\n---",
    );
    assert_eq!(names(&config(&config_dir, None)), ["env-skill"]);

    // Without CLAUDE_CONFIG_DIR the home directory's `.claude` is used.
    let home = temp.join("home");
    write_skill(&home.join(".claude/skills"), "home-skill", "# Home");
    let mut from_home = config(&config_dir, None);
    from_home
        .options
        .env
        .insert("CLAUDE_CONFIG_DIR".into(), " ".into());
    from_home
        .options
        .env
        .insert("HOME".into(), home.to_string_lossy().into_owned());
    assert_eq!(names(&from_home), ["home-skill"]);
}

#[test]
fn resolves_a_relative_claude_config_dir_against_the_workspace_cwd() {
    let temp = TempDir::new();
    let workspace = temp.join("workspace");
    write_skill(
        &workspace.join("relative-config/skills"),
        "relative-skill",
        "---\nname: relative-skill\n---",
    );
    let mut relative = config(&temp.join("unused"), Some(&workspace));
    relative
        .options
        .env
        .insert("CLAUDE_CONFIG_DIR".into(), "relative-config".into());
    let skills = discover_skills(&relative);
    assert_eq!(
        skills
            .iter()
            .map(|skill| skill.name.as_str())
            .collect::<Vec<_>>(),
        ["relative-skill"]
    );
    assert_eq!(skills[0].scope.as_deref(), Some("user"));
}

#[test]
fn accepts_the_yaml_1_1_boolean_spellings_claude_code_allows() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let skills_dir = config_dir.join("skills");
    for (name, field) in [
        ("user-only-yes", "disable-model-invocation: yes"),
        ("user-only-y", "disable-model-invocation: Y"),
        ("agent-only-no", "user-invocable: no"),
        ("agent-only-n", "user-invocable: n"),
        ("agent-only-false", "user-invocable: false"),
        ("agent-only-zero", "user-invocable: 0"),
        ("plain-off", "disable-model-invocation: off"),
        ("plain-unknown", "disable-model-invocation: maybe"),
    ] {
        write_skill(&skills_dir, name, &format!("---\n{field}\n---\n\n# Body"));
    }
    let skills = discover_skills(&config(&config_dir, None));
    assert_eq!(
        skills
            .iter()
            .map(|skill| (
                skill.name.as_str(),
                skill.user_invocation_only == Some(true),
                skill.user_invocable == Some(false),
                skill.is_user_invocable(),
            ))
            .collect::<Vec<_>>(),
        [
            ("agent-only-false", false, true, false),
            ("agent-only-n", false, true, false),
            ("agent-only-no", false, true, false),
            ("agent-only-zero", false, true, false),
            ("plain-off", false, false, true),
            ("plain-unknown", false, false, true),
            ("user-only-y", true, false, true),
            ("user-only-yes", true, false, true),
        ]
    );
    assert_eq!(
        user_invocable_skills(skills)
            .into_keys()
            .collect::<std::collections::BTreeSet<_>>(),
        ["plain-off", "plain-unknown", "user-only-y", "user-only-yes"]
            .map(String::from)
            .into()
    );
}

#[test]
fn identifies_a_skill_by_its_directory_and_sorts_by_locale() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let skills_dir = config_dir.join("skills");
    write_skill(
        &skills_dir,
        "probe-alias",
        "---\nname: probe-alias-frontmatter\n---\n\n# Body",
    );
    for name in ["Zeta", "alpha", "a_b", "a-b", "2spec"] {
        write_skill(&skills_dir, name, "# Body");
    }
    assert_eq!(
        names(&config(&config_dir, None)),
        ["2spec", "a_b", "a-b", "alpha", "probe-alias", "Zeta"]
    );
}
