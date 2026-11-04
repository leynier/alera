use alera_provider_grok::decode_inspect_skills;
use serde_json::json;

fn inspect_payload(skills: serde_json::Value) -> String {
    json!({ "skills": skills }).to_string()
}

#[test]
fn maps_inspect_entries_onto_provider_skills_sorted_by_name() {
    let skills = decode_inspect_skills(&inspect_payload(json!([
        {
            "name": "writing-docs",
            "description": "Write user docs.",
            "source": {"type": "user", "path": "/home/dev/.grok/skills/writing-docs/SKILL.md"},
            "userInvocable": true
        },
        {
            "name": "deploy",
            "description": "Deploy the app.",
            "source": {"type": "plugin", "path": "/home/dev/.grok/installed-plugins/pkg/plug/skills/deploy/SKILL.md"},
            "userInvocable": true
        }
    ])))
    .unwrap();
    assert_eq!(
        serde_json::to_value(&skills).unwrap(),
        json!([
            {
                "name": "deploy",
                "description": "Deploy the app.",
                "path": "/home/dev/.grok/installed-plugins/pkg/plug/skills/deploy/SKILL.md",
                "scope": "plugin",
                "enabled": true
            },
            {
                "name": "writing-docs",
                "description": "Write user docs.",
                "path": "/home/dev/.grok/skills/writing-docs/SKILL.md",
                "scope": "user",
                "enabled": true
            }
        ])
    );
}

#[test]
fn disables_skills_the_cli_marks_as_not_user_invocable() {
    let skills = decode_inspect_skills(&inspect_payload(json!([
        {
            "name": "internal-helper",
            "source": {"type": "bundled", "path": "/opt/grok/bundled/skills/internal-helper/SKILL.md"},
            "userInvocable": false
        },
        {"name": "implicit", "source": {"path": "/repo/.grok/skills/implicit/SKILL.md"}}
    ])))
    .unwrap();
    assert_eq!(
        serde_json::to_value(&skills).unwrap(),
        json!([
            {"name": "implicit", "path": "/repo/.grok/skills/implicit/SKILL.md", "enabled": true},
            {
                "name": "internal-helper",
                "path": "/opt/grok/bundled/skills/internal-helper/SKILL.md",
                "scope": "bundled",
                "enabled": false
            }
        ])
    );
}

#[test]
fn skips_entries_without_a_name_or_a_path_and_lets_the_last_duplicate_win() {
    let skills = decode_inspect_skills(&inspect_payload(json!([
        {"name": "  ", "source": {"type": "user", "path": "/tmp/skills/a/SKILL.md"}},
        {"name": "no-path", "source": {"type": "user"}},
        {"name": "no-source"},
        {"name": "string-source", "source": "/tmp/skills/b/SKILL.md"},
        "not-an-object",
        {"name": "kept", "source": {"type": "user", "path": "/home/kept/SKILL.md"}},
        {"name": "kept", "source": {"type": "project", "path": " /repo/.grok/skills/kept/SKILL.md "}}
    ])))
    .unwrap();
    assert_eq!(skills.len(), 1);
    assert_eq!(skills[0].name, "kept");
    assert_eq!(skills[0].path, "/repo/.grok/skills/kept/SKILL.md");
    assert_eq!(skills[0].scope.as_deref(), Some("project"));
}

#[test]
fn rejects_malformed_or_unexpected_output() {
    for stdout in ["not json", "null", "[]", r#"{"skills":"nope"}"#, "{}"] {
        assert_eq!(decode_inspect_skills(stdout), None, "{stdout}");
    }
    assert_eq!(
        decode_inspect_skills(" {\"skills\":[]}\n"),
        Some(Vec::new())
    );
}

#[cfg(unix)]
mod spawned {
    use alera_provider_grok::{discover_skills, GrokProviderConfig};
    use std::ffi::OsString;
    use std::fs;
    use std::path::{Path, PathBuf};

    /// Runs `sh inspect --json` in a directory whose `inspect` file is the
    /// stub, so the test never executes a file it has just written (which
    /// races into ETXTBSY when another test thread forks).
    fn stub(name: &str, script: &str) -> (GrokProviderConfig, PathBuf) {
        let directory = Path::new(env!("CARGO_TARGET_TMPDIR"))
            .join("grok-inspect")
            .join(name);
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join("inspect"), script).unwrap();
        let config = GrokProviderConfig {
            executable: PathBuf::from("/bin/sh"),
            cwd: Some(directory.clone()),
            env: [(
                OsString::from("GROK_DISABLE_AUTOUPDATER"),
                OsString::from("0"),
            )]
            .into(),
            ..GrokProviderConfig::default()
        };
        (config, directory)
    }

    #[tokio::test]
    async fn runs_inspect_in_the_cwd_with_the_probe_environment() {
        let (config, directory) = stub(
            "success",
            r#"[ "$1" = "--json" ] || exit 9
printf '%s|%s' "$(pwd)" "$GROK_DISABLE_AUTOUPDATER" > probe.txt
printf '{"skills":[{"name":"review","source":{"type":"project","path":"%s/SKILL.md"}}]}' "$(pwd)"
"#,
        );
        let skills = discover_skills(&config).await.unwrap();
        let canonical = fs::canonicalize(&directory).unwrap();
        assert_eq!(skills.len(), 1);
        assert_eq!(skills[0].name, "review");
        assert_eq!(
            fs::read_to_string(directory.join("probe.txt")).unwrap(),
            format!("{}|1", canonical.display())
        );
    }

    #[tokio::test]
    async fn reports_the_failing_stage() {
        let (config, directory) = stub("exit", "exit 3\n");
        assert_eq!(
            discover_skills(&config).await.unwrap_err(),
            format!(
                "`grok inspect --json` failed during exit for '{}' with exit code 3.",
                directory.display()
            )
        );

        let (config, _) = stub("decode", "echo not-json\n");
        assert!(discover_skills(&config)
            .await
            .unwrap_err()
            .contains("failed during decode"));

        let missing = GrokProviderConfig {
            executable: PathBuf::from("/nonexistent/grok"),
            ..GrokProviderConfig::default()
        };
        assert_eq!(
            discover_skills(&missing).await.unwrap_err(),
            "`grok inspect --json` failed during spawn."
        );
    }

    #[tokio::test]
    async fn kills_a_probe_that_outlives_the_timeout() {
        let (config, _) = stub("timeout", "exec sleep 30\n");
        let started = std::time::Instant::now();
        let error = discover_skills(&config).await.unwrap_err();
        assert!(error.contains("failed during timeout"), "{error}");
        assert!(started.elapsed() < std::time::Duration::from_secs(10));
    }
}
