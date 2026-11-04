use super::claude_command_output_text as text;
use super::tail::{decode, CommandOutputTails, MAX_LOCATE_ATTEMPTS, MAX_READ_BYTES};
use serde_json::json;
use std::io::Write;
use std::sync::atomic::{AtomicU64, Ordering};

#[test]
fn command_output_joins_its_streams() {
    let content = json!("fallback");
    let both = |stdout: &str, stderr: &str| {
        text(Some(&json!({"stdout": stdout, "stderr": stderr})), &content)
    };
    assert_eq!(both("out", ""), "out");
    assert_eq!(both("", "err"), "err");
    assert_eq!(both("out", "err"), "out\nerr");
    assert_eq!(both("out\n", "err"), "out\nerr");
    assert_eq!(both(" ", "\n"), "fallback");
    assert_eq!(
        text(
            None,
            &json!([{"type": "text", "text": "a"}, {"type": "text", "text": "b"}])
        ),
        "ab"
    );
}

#[test]
fn split_and_invalid_utf8_decode_as_the_cli_wrote_it() {
    let euro = "€".as_bytes();
    let mut buffer = vec![b'a', euro[0]];
    assert_eq!(decode(&mut buffer, false), "a");
    buffer.extend(&euro[1..]);
    assert_eq!(decode(&mut buffer, false), "€");
    let mut invalid = vec![b'x', 0xff, b'y', euro[0]];
    assert_eq!(decode(&mut invalid, false), "x\u{FFFD}y");
    assert_eq!(decode(&mut invalid, true), "\u{FFFD}");
}

#[cfg(unix)]
fn temp_root() -> std::path::PathBuf {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let root = std::env::temp_dir().join(format!(
        "alera-claude-output-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir_all(root.join("project/session/tasks")).unwrap();
    root
}

#[cfg(unix)]
#[test]
fn a_tail_reads_appended_output_and_restarts_after_truncation() {
    let root = temp_root();
    let path = root.join("project/session/tasks/task.output");
    let mut tails = CommandOutputTails::new(Some(root.clone()));
    tails.start("tool", "session", "task");
    assert!(tails.poll().is_empty());
    std::fs::write(&path, "one\n").unwrap();
    assert_eq!(tails.poll(), [("tool".to_owned(), "one\n".to_owned())]);
    std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(b"two\n")
        .unwrap();
    assert_eq!(tails.poll(), [("tool".to_owned(), "two\n".to_owned())]);
    std::fs::write(&path, "new\n").unwrap();
    assert_eq!(tails.poll(), [("tool".to_owned(), "new\n".to_owned())]);
    std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(b"last")
        .unwrap();
    assert_eq!(tails.stop("tool").as_deref(), Some("last"));
    assert!(!tails.is_active());
}

#[cfg(unix)]
#[test]
fn a_fast_writer_is_read_from_its_tail() {
    let root = temp_root();
    let path = root.join("project/session/tasks/task.output");
    let mut tails = CommandOutputTails::new(Some(root));
    tails.start("tool", "session", "task");
    let big = "x".repeat(MAX_READ_BYTES as usize + 10);
    std::fs::write(&path, &big).unwrap();
    let chunks = tails.poll();
    assert!(chunks[0].1.starts_with('\n'));
    assert_eq!(chunks[0].1.len(), MAX_READ_BYTES as usize + 1);
}

#[cfg(unix)]
#[test]
fn a_file_that_never_appears_drops_its_tail() {
    let mut tails = CommandOutputTails::new(Some(temp_root()));
    tails.start("tool", "session", "missing");
    for _ in 0..MAX_LOCATE_ATTEMPTS {
        assert!(tails.poll().is_empty());
    }
    assert!(!tails.is_active());
}

#[cfg(unix)]
#[test]
fn the_root_honors_claude_code_tmpdir() {
    let env = std::collections::BTreeMap::from([(
        "CLAUDE_CODE_TMPDIR".to_owned(),
        " /var/tmp/custom ".to_owned(),
    )]);
    let root = super::tail::task_output_root(&env).unwrap();
    assert!(root.starts_with("/var/tmp/custom"));
    assert!(root
        .file_name()
        .unwrap()
        .to_string_lossy()
        .starts_with("claude-"));
}
