use super::*;
use std::sync::atomic::{AtomicU64, Ordering};

fn temp_dir() -> PathBuf {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let dir = std::env::temp_dir().join(format!(
        "alera-claude-settings-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn file(dir: &std::path::Path, name: &str, text: &str) -> PathBuf {
    let path = dir.join(name);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, text).unwrap();
    path
}

fn of(text: &str) -> BypassAvailability {
    let dir = temp_dir();
    availability_of(&[file(&dir, "settings.json", text)])
}

const BYPASS_OFF: BypassAvailability = BypassAvailability {
    bypass_disabled: true,
    auto_disabled: false,
};

#[test]
fn settings_switch_off_bypass_and_auto() {
    let dir = temp_dir();
    assert_eq!(
        availability_of(&[dir.join("missing.json")]),
        BypassAvailability::default()
    );
    assert_eq!(
        of(r#"{"permissions": {"disableBypassPermissionsMode": "disable"}}"#),
        BYPASS_OFF
    );
    for text in [
        r#"{"disableAutoMode": "disable"}"#,
        r#"{"permissions": {"disableAutoMode": "disable"}}"#,
    ] {
        assert_eq!(
            of(text),
            BypassAvailability {
                bypass_disabled: false,
                auto_disabled: true,
            }
        );
    }
    // Comments and trailing commas are read as the CLI reads them.
    assert_eq!(
        of("{\n // no bypass\n \"permissions\": {\"disableBypassPermissionsMode\": \"disable\",},\n}"),
        BYPASS_OFF
    );
    assert_eq!(
        of(r#"{"permissions": {"disableBypassPermissionsMode": false}}"#),
        BypassAvailability::default()
    );
}

#[test]
fn unreadable_or_unexpected_settings_fail_closed() {
    for text in [
        "{not json",
        "[]",
        r#"{"permissions": []}"#,
        r#"{"permissions": {"disableBypassPermissionsMode": true}}"#,
        r#"{"disableAutoMode": "yes"}"#,
    ] {
        assert_eq!(of(text), BYPASS_OFF, "{text}");
    }
    let dir = temp_dir();
    std::fs::create_dir_all(dir.join("settings.json")).unwrap();
    assert_eq!(availability_of(&[dir.join("settings.json")]), BYPASS_OFF);
}

#[test]
fn every_file_the_cli_reads_counts_unless_its_source_is_off() {
    let config = temp_dir();
    let cwd = temp_dir();
    let options = ClaudeAgentOptions {
        env: BTreeMap::from([(
            "CLAUDE_CONFIG_DIR".to_owned(),
            config.to_string_lossy().into_owned(),
        )]),
        ..Default::default()
    };
    let environment = SkillEnvironment::new(&options, Some(&cwd));
    let disable = r#"{"permissions": {"disableBypassPermissionsMode": "disable"}}"#;
    assert!(!bypass_availability(&environment, None).bypass_disabled);
    file(&config, "remote-settings.json", disable);
    assert!(bypass_availability(&environment, None).bypass_disabled);
    std::fs::remove_file(config.join("remote-settings.json")).unwrap();

    file(&cwd, ".claude/settings.local.json", disable);
    assert!(bypass_availability(&environment, None).bypass_disabled);
    let project_only = ["project".to_owned()];
    assert!(!bypass_availability(&environment, Some(&project_only)).bypass_disabled);
    std::fs::remove_file(cwd.join(".claude/settings.local.json")).unwrap();

    file(&config, "settings.json", disable);
    assert!(bypass_availability(&environment, None).bypass_disabled);
    assert!(!bypass_availability(&environment, Some(&project_only)).bypass_disabled);
}
