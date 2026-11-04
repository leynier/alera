//! Antigravity model lists, thinking levels and probe session files.

use alera_provider_antigravity::{
    models_from_session, remove_session_files, thinking_from_options, AntigravityProviderConfig,
    AntigravityThinking,
};
use serde_json::json;
use std::collections::BTreeMap;
use std::path::PathBuf;

#[test]
fn models_are_unique_the_current_one_is_default_and_shared_names_show_ids() {
    let choices = vec![
        ("a".to_owned(), "Gemini".to_owned()),
        ("b".to_owned(), "Gemini".to_owned()),
        ("a".to_owned(), "Again".to_owned()),
        ("c".to_owned(), "Claude".to_owned()),
    ];
    let thinking = BTreeMap::from([(
        "c".to_owned(),
        AntigravityThinking {
            levels: vec!["low".into()],
            default: None,
        },
    )]);
    let models = models_from_session(&choices, Some("b"), &thinking);
    let summary: Vec<_> = models
        .iter()
        .map(|model| {
            (
                model.id.as_str(),
                model.label.as_str(),
                model.provider_default,
            )
        })
        .collect();
    assert_eq!(
        summary,
        vec![
            ("a", "Gemini (a)", false),
            ("b", "Gemini (b)", true),
            ("c", "Claude", false)
        ]
    );
    assert_eq!(models[2].thinking.levels, vec!["low"]);
}

#[test]
fn thinking_levels_come_from_the_thought_level_option() {
    let options = vec![
        json!({"id":"thought_level","category":"thought_level","type":"select","currentValue":"high","options":[{"value":"low"},{"value":"high"}]}),
    ];
    assert_eq!(
        thinking_from_options(&options),
        AntigravityThinking {
            levels: vec!["low".into(), "high".into()],
            default: Some("high".into())
        }
    );
    assert_eq!(thinking_from_options(&[]), AntigravityThinking::default());
}

const SESSION: &str = "0b5c3f0e-8f6a-4c1e-9d2b-7a1e5c3b9f00";

fn session_files(root: &std::path::Path, cwd: &str) -> Vec<PathBuf> {
    let conversations = root.join("antigravity-acp/conversations");
    let brain = root.join("antigravity-acp/brain").join(SESSION);
    std::fs::create_dir_all(&conversations).unwrap();
    std::fs::create_dir_all(&brain).unwrap();
    let mut files = vec![brain.join("note.md")];
    for suffix in ["db", "db-wal", "meta"] {
        files.push(conversations.join(format!("{SESSION}.{suffix}")));
    }
    for file in &files {
        std::fs::write(file, "x").unwrap();
    }
    std::fs::write(
        conversations.join(format!("{SESSION}.meta")),
        json!({"cwd": cwd}).to_string(),
    )
    .unwrap();
    files
}

#[test]
fn probe_session_files_are_removed_only_when_the_probe_owns_them() {
    let root = tempfile::tempdir().unwrap();
    let files = session_files(root.path(), "/tmp/probe-a");
    remove_session_files(root.path(), SESSION, std::path::Path::new("/tmp/other"));
    assert!(files.iter().all(|file| file.exists()));
    remove_session_files(
        root.path(),
        "not-a-uuid",
        std::path::Path::new("/tmp/probe-a"),
    );
    assert!(files.iter().all(|file| file.exists()));
    remove_session_files(root.path(), SESSION, std::path::Path::new("/tmp/probe-a"));
    assert!(files.iter().all(|file| !file.exists()));
}

#[test]
fn the_profile_root_prefers_the_profile_then_gemini_home() {
    let config = AntigravityProviderConfig {
        profile_dir: Some(PathBuf::from("/profiles/agy")),
        ..Default::default()
    };
    assert_eq!(
        alera_provider_antigravity::profile_root(&config),
        Some(PathBuf::from("/profiles/agy"))
    );
    let mut config = AntigravityProviderConfig::default();
    config
        .env
        .insert("GEMINI_HOME".into(), "/homes/gemini".into());
    assert_eq!(
        alera_provider_antigravity::profile_root(&config),
        Some(PathBuf::from("/homes/gemini"))
    );
}
