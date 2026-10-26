use alera_provider_antigravity::{discover_skills, discover_skills_at, AntigravityProviderConfig};
use alera_provider_protocol::ProviderSkill;
use serde_json::json;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};

fn workspace(name: &str) -> (PathBuf, PathBuf) {
    let root = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join("antigravity-skills")
        .join(name);
    let _ = fs::remove_dir_all(&root);
    (root.join("workspace"), root.join("home"))
}

fn write_skill(directory: &Path, contents: &str) -> PathBuf {
    fs::create_dir_all(directory).unwrap();
    let path = directory.join("SKILL.md");
    fs::write(&path, contents).unwrap();
    path
}

fn skill(name: &str, path: &Path, scope: &str, description: Option<&str>) -> ProviderSkill {
    ProviderSkill::from_native(name, &path.to_string_lossy(), true)
        .unwrap()
        .with_scope(Some(scope))
        .with_description(description)
}

#[test]
fn reads_names_descriptions_and_paths_from_the_native_roots() {
    let (cwd, home) = workspace("roots");
    let roots = [
        (home.join(".gemini/config/skills"), "user"),
        (cwd.join(".gemini/skills"), "project"),
        (home.join(".gemini/antigravity-cli/skills"), "user"),
        (cwd.join(".agents/skills"), "project"),
        (cwd.join(".agent/skills"), "project"),
    ];
    let mut expected = Vec::new();
    for (index, (root, scope)) in roots.iter().enumerate() {
        let name = format!("review-{index}");
        let description = format!("Review changes in root {index}.");
        let path = write_skill(
            &root.join(&name),
            &format!("---\nname: {name}\ndescription: {description}\n---\n# Review\n"),
        );
        expected.push(skill(&name, &path, scope, Some(&description)));
    }
    write_skill(
        &home.join(".agents/skills/ignored"),
        "---\nname: ignored\n---\n",
    );
    write_skill(&cwd.join(".claude/skills/other"), "---\nname: other\n---\n");
    assert_eq!(discover_skills_at(&cwd, &home).unwrap(), expected);
}

#[test]
fn uses_native_root_order_for_duplicate_names() {
    let (cwd, home) = workspace("duplicates");
    let roots = [
        home.join(".gemini/config/skills"),
        cwd.join(".gemini/skills"),
        home.join(".gemini/antigravity-cli/skills"),
        cwd.join(".agents/skills"),
        cwd.join(".agent/skills"),
    ];
    for (index, root) in roots.iter().enumerate() {
        write_skill(
            &root.join(format!("copy-{index}")),
            &format!("---\nname: review\ndescription: Copy {index}.\n---\n"),
        );
    }
    for (index, root) in roots.iter().enumerate() {
        let skills = discover_skills_at(&cwd, &home).unwrap();
        assert_eq!(skills.len(), 1);
        assert_eq!(
            skills[0].path,
            root.join(format!("copy-{index}/SKILL.md"))
                .to_string_lossy()
        );
        fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn loads_a_root_skill_without_scanning_its_children() {
    let (cwd, home) = workspace("root-skill");
    let root = cwd.join(".agents/skills");
    let path = write_skill(&root, "---\nname: root-skill\n---\n");
    write_skill(&root.join("child"), "---\nname: child-skill\n---\n");
    assert_eq!(
        discover_skills_at(&cwd, &home).unwrap(),
        vec![skill("root-skill", &path, "project", None)]
    );
    fs::write(&path, "---\nname: [invalid\n---\n").unwrap();
    assert_eq!(discover_skills_at(&cwd, &home).unwrap(), Vec::new());
}

#[test]
fn uses_the_file_name_when_the_frontmatter_has_no_name() {
    let (cwd, home) = workspace("file-name");
    let directory = cwd.join(".agents/skills/not-the-name");
    let path = write_skill(&directory, "---\n---\n# Skill body\n");
    assert_eq!(
        discover_skills_at(&cwd, &home).unwrap(),
        vec![skill("SKILL", &path, "project", None)]
    );
    let lower = directory.join("skill.md");
    fs::rename(&path, &lower).unwrap();
    assert_eq!(
        discover_skills_at(&cwd, &home).unwrap(),
        vec![skill("skill", &lower, "project", None)]
    );
    fs::rename(&lower, directory.join("SKILL.MD")).unwrap();
    assert_eq!(discover_skills_at(&cwd, &home).unwrap(), Vec::new());
}

#[test]
fn accepts_delimiters_after_leading_text_and_rejects_invalid_files() {
    let (cwd, home) = workspace("frontmatter");
    let root = cwd.join(".agents/skills");
    let review = write_skill(
        &root.join("review"),
        "Leading text.---\nname: review\ndescription: null\n---Skill body.",
    );
    for (name, contents) in [
        ("plain", "# Missing frontmatter\n"),
        ("broken", "---\nname: [unclosed\n---\n"),
        ("scalar", "---\n42\n---\n"),
        ("wrong-type", "---\nname: invalid\ndescription: {}\n---\n"),
        ("blank-name", "---\nname: \" \"\n---\n"),
        ("padded-name", "---\nname: \" padded\"\n---\n"),
    ] {
        write_skill(&root.join(name), contents);
    }
    write_skill(&root.join("nested/deep"), "---\nname: too-deep\n---\n");
    fs::create_dir_all(root.join(".not-a-skill")).unwrap();
    fs::write(root.join("README.md"), "Not a skill.").unwrap();
    let hidden = write_skill(
        &root.join(".native-hidden-skill"),
        "---\nname: native-name\ndescription: >\n  Review the code\n  and run tests.\n---\n",
    );
    assert_eq!(
        discover_skills_at(&cwd, &home).unwrap(),
        vec![
            skill(
                "native-name",
                &hidden,
                "project",
                Some("Review the code and run tests.")
            ),
            skill("review", &review, "project", None),
        ]
    );
}

#[test]
fn uses_native_uri_order_within_a_root() {
    let (cwd, home) = workspace("uri-order");
    write_skill(
        &home.join(".gemini/config/skills/review"),
        "---\nname: [invalid\n---\n",
    );
    let root = cwd.join(".agents/skills");
    let native_order = [" space-copy", "!-copy", "\u{f8}-copy", "a-copy"];
    for name in native_order {
        write_skill(&root.join(name), "---\nname: review\n---\n");
    }
    for name in native_order {
        let skills = discover_skills_at(&cwd, &home).unwrap();
        assert_eq!(
            skills,
            vec![skill(
                "review",
                &root.join(name).join("SKILL.md"),
                "project",
                None
            )]
        );
        fs::remove_dir_all(root.join(name)).unwrap();
    }
}

#[test]
fn fails_instead_of_listing_part_of_an_oversized_scan() {
    let (cwd, home) = workspace("budget");
    let root = cwd.join(".agents/skills");
    let large = write_skill(&root.join("large"), "");
    fs::write(&large, vec![b'a'; 1_000_001]).unwrap();
    assert_eq!(
        discover_skills_at(&cwd, &home).unwrap_err(),
        format!(
            "Antigravity skill discovery exceeded its scan limit at '{}'.",
            large.display()
        )
    );
    fs::remove_dir_all(root.join("large")).unwrap();
    let crowded = root.join("crowded");
    fs::create_dir_all(&crowded).unwrap();
    for index in 0..10_001 {
        fs::write(crowded.join(format!("f{index:05}")), "").unwrap();
    }
    assert_eq!(
        discover_skills_at(&cwd, &home).unwrap_err(),
        format!(
            "Antigravity skill discovery exceeded its scan limit at '{}'.",
            crowded.display()
        )
    );
}

#[test]
fn resolves_the_user_home_from_the_config_environment_and_ignores_gemini_home() {
    let (cwd, home) = workspace("config-home");
    let path = write_skill(
        &home.join(".gemini/config/skills/review"),
        "---\nname: review\n---\n",
    );
    let profile = cwd.join("profile");
    write_skill(
        &profile.join("config/skills/private"),
        "---\nname: private\n---\n",
    );
    let config = AntigravityProviderConfig {
        cwd: Some(cwd.clone()),
        env: [
            (OsString::from("HOME"), home.clone().into_os_string()),
            (OsString::from("USERPROFILE"), home.clone().into_os_string()),
            (
                OsString::from("GEMINI_HOME"),
                profile.clone().into_os_string(),
            ),
        ]
        .into(),
        profile_dir: Some(profile),
        ..AntigravityProviderConfig::default()
    };
    let skills = discover_skills(&config).unwrap();
    assert_eq!(
        serde_json::to_value(&skills).unwrap(),
        json!([{"name": "review", "path": path.to_string_lossy(), "scope": "user", "enabled": true}])
    );
}
