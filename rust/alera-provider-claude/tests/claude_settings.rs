//! The managed settings file sits at a fixed system path that a test cannot
//! redirect, so these assume the machine sets no `ANTHROPIC_BASE_URL` there.

mod skill_fixtures;

use alera_provider_claude::claude_settings_base_url;
use skill_fixtures::{write, TempDir};
use std::collections::BTreeMap;
use std::path::Path;

fn env(config_dir: &Path) -> BTreeMap<String, String> {
    BTreeMap::from([(
        "CLAUDE_CONFIG_DIR".to_owned(),
        config_dir.to_string_lossy().into_owned(),
    )])
}

#[test]
fn the_user_settings_base_url_is_returned() {
    let temp = TempDir::new();
    write(
        &temp.join("settings.json"),
        r#"{"env": {"ANTHROPIC_BASE_URL": "https://hub.example.ts.net:8317"}}"#,
    );

    assert_eq!(
        claude_settings_base_url(&env(temp.path())).as_deref(),
        Some("https://hub.example.ts.net:8317")
    );
}

#[test]
fn comments_and_trailing_commas_are_tolerated() {
    let temp = TempDir::new();
    write(
        &temp.join("settings.json"),
        "{\n  // proxy\n  \"env\": {\n    \"ANTHROPIC_BASE_URL\": \"http://localhost:8080\", /* local */\n  },\n}\n",
    );

    assert_eq!(
        claude_settings_base_url(&env(temp.path())).as_deref(),
        Some("http://localhost:8080")
    );
}

#[test]
fn a_value_that_is_not_a_string_reads_as_unset() {
    let temp = TempDir::new();
    write(
        &temp.join("settings.json"),
        r#"{"env": {"ANTHROPIC_BASE_URL": 8080}}"#,
    );

    assert_eq!(claude_settings_base_url(&env(temp.path())), None);
}

#[test]
fn a_missing_or_malformed_file_is_skipped() {
    let temp = TempDir::new();
    assert_eq!(claude_settings_base_url(&env(temp.path())), None);

    write(
        &temp.join("settings.json"),
        r#"{"env": {"ANTHROPIC_BASE_URL": "https://proxy.example""#,
    );
    assert_eq!(claude_settings_base_url(&env(temp.path())), None);

    write(&temp.join("settings.json"), r#"["https://proxy.example"]"#);
    assert_eq!(claude_settings_base_url(&env(temp.path())), None);
}

#[test]
fn the_config_dir_comes_from_the_launch_env_before_its_home() {
    let temp = TempDir::new();
    let home = temp.join("home");
    write(
        &home.join(".claude").join("settings.json"),
        r#"{"env": {"ANTHROPIC_BASE_URL": "https://home.example"}}"#,
    );
    write(
        &temp.join("config").join("settings.json"),
        r#"{"env": {"ANTHROPIC_BASE_URL": "https://config.example"}}"#,
    );
    let mut env = env(&temp.join("config"));
    env.insert("HOME".into(), home.to_string_lossy().into_owned());
    env.insert("USERPROFILE".into(), home.to_string_lossy().into_owned());

    assert_eq!(
        claude_settings_base_url(&env).as_deref(),
        Some("https://config.example")
    );

    env.insert("CLAUDE_CONFIG_DIR".into(), String::new());
    assert_eq!(
        claude_settings_base_url(&env).as_deref(),
        Some("https://home.example")
    );
}
