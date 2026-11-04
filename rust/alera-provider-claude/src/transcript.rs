//! Whether a Claude session ever saved a message, as T3 Code 63e18dffc5. A
//! session the CLI created but never wrote a user or assistant line to
//! cannot be resumed, so the adapter starts a fresh one instead.

use crate::skills::SkillEnvironment;
use claude_agent_sdk::ClaudeAgentOptions;
use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Read};
use std::path::Path;

/// The most of one transcript read before giving up on finding a message.
const MAX_SCANNED_BYTES: u64 = 16 * 1024 * 1024;

/// True only when a transcript of [session_id] exists under the config
/// dir's `projects` and none of its copies holds a user or assistant line.
/// Anything uncertain (no transcript, a read error, a transcript past the
/// scan cap) is false, leaving the resume to the CLI.
pub fn claude_session_has_no_conversation(
    env: &BTreeMap<String, String>,
    cwd: Option<&Path>,
    session_id: &str,
) -> bool {
    if session_id.is_empty() || matches!(session_id, "." | "..") || session_id.contains(['/', '\\'])
    {
        return false;
    }
    let options = ClaudeAgentOptions {
        env: env.clone(),
        ..Default::default()
    };
    let Some(config_dir) = SkillEnvironment::new(&options, cwd).config_dir() else {
        return false;
    };
    let Ok(projects) = std::fs::read_dir(config_dir.join("projects")) else {
        return false;
    };
    let mut found = false;
    for project in projects.flatten() {
        let path = project.path().join(format!("{session_id}.jsonl"));
        if !path.is_file() {
            continue;
        }
        if !has_no_conversation(&path) {
            return false;
        }
        found = true;
    }
    found
}

fn has_no_conversation(path: &Path) -> bool {
    let Ok(file) = std::fs::File::open(path) else {
        return false;
    };
    let mut reader = BufReader::new(file.take(MAX_SCANNED_BYTES));
    let mut scanned = 0_u64;
    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => return scanned < MAX_SCANNED_BYTES,
            Ok(read) => scanned += read as u64,
            Err(_) => return false,
        }
        let kind = serde_json::from_str::<serde_json::Value>(&line)
            .ok()
            .and_then(|value| value.get("type")?.as_str().map(str::to_owned));
        if matches!(kind.as_deref(), Some("user" | "assistant")) {
            return false;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    fn config_dir() -> std::path::PathBuf {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        std::env::temp_dir().join(format!(
            "alera-claude-transcript-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::SeqCst)
        ))
    }

    fn write(dir: &Path, project: &str, id: &str, lines: &[&str]) {
        let project = dir.join("projects").join(project);
        std::fs::create_dir_all(&project).unwrap();
        std::fs::write(project.join(format!("{id}.jsonl")), lines.join("\n")).unwrap();
    }

    fn env(dir: &Path) -> BTreeMap<String, String> {
        BTreeMap::from([(
            "CLAUDE_CONFIG_DIR".to_owned(),
            dir.to_string_lossy().into_owned(),
        )])
    }

    const METADATA: [&str; 3] = [
        r#"{"type":"last-prompt","lastPrompt":"hi"}"#,
        r#"{"type":"atis-latch"}"#,
        r#"{"type":"cost-state","costUSD":0}"#,
    ];

    #[test]
    fn a_metadata_only_transcript_never_saved_a_message() {
        let dir = config_dir();
        write(&dir, "-workspace", "native-thread-empty", &METADATA);
        assert!(claude_session_has_no_conversation(
            &env(&dir),
            None,
            "native-thread-empty"
        ));
        write(
            &dir,
            "-other",
            "native-thread-empty",
            &[r#"{"type":"user"}"#],
        );
        assert!(!claude_session_has_no_conversation(
            &env(&dir),
            None,
            "native-thread-empty"
        ));
    }

    #[test]
    fn uncertain_cases_leave_the_resume_to_the_cli() {
        let dir = config_dir();
        assert!(!claude_session_has_no_conversation(
            &env(&dir),
            None,
            "missing"
        ));
        write(
            &dir,
            "-workspace",
            "saved",
            &[METADATA[0], r#"{"type":"assistant"}"#],
        );
        assert!(!claude_session_has_no_conversation(
            &env(&dir),
            None,
            "saved"
        ));
        assert!(!claude_session_has_no_conversation(
            &env(&dir),
            None,
            "missing"
        ));
        for id in ["", ".", "..", "a/b", "a\\b"] {
            assert!(!claude_session_has_no_conversation(&env(&dir), None, id));
        }
    }

    #[test]
    fn a_relative_config_dir_is_read_against_the_cwd() {
        let cwd = config_dir();
        write(&cwd.join("config"), "-workspace", "empty", &METADATA);
        let env = BTreeMap::from([("CLAUDE_CONFIG_DIR".to_owned(), "config".to_owned())]);
        assert!(claude_session_has_no_conversation(
            &env,
            Some(&cwd),
            "empty"
        ));
    }
}
