use super::*;
use serde_json::json;

fn line(value: Value) -> String {
    format!("{value}\n")
}

fn assistant(id: &str, content: Value) -> String {
    line(
        json!({"type": "assistant", "message": {"role": "assistant", "id": id, "content": content}}),
    )
}

fn text(id: &str, body: &str) -> String {
    assistant(id, json!([{"type": "text", "text": body}]))
}

#[test]
fn one_answer_per_assistant_turn() {
    assert_eq!(
        parse_agent_answers(&(text("a", "first") + &text("b", "second"))),
        ["first", "second"]
    );
}

#[test]
fn a_split_assistant_message_is_one_turn() {
    let contents = assistant(
        "a",
        json!([{"type": "thinking", "thinking": "weighing it up"}]),
    ) + &text("a", "the answer")
        + &text("a", "and more");
    assert_eq!(parse_agent_answers(&contents), ["the answer\n\nand more"]);
}

#[test]
fn bookkeeping_prompts_blank_text_and_cut_lines_are_skipped() {
    let contents = line(json!({"type": "attachment", "attachment": {"type": "skill_listing"}}))
        + &line(json!({"type": "user", "message": {"role": "user", "content": "the prompt"}}))
        + &line(json!({
            "type": "assistant", "isMeta": true,
            "message": {"id": "m", "content": [{"type": "text", "text": "injected"}]},
        }))
        + &assistant(
            "t",
            json!([{"type": "tool_use", "id": "t", "name": "Bash", "input": {}}]),
        )
        + &text("b", "   ")
        + &text("c", "    indented code")
        + "{\"type\":\"assistant\",\"mess";
    assert_eq!(parse_agent_answers(&contents), ["    indented code"]);
}

#[test]
fn member_ids_that_look_like_paths_are_refused() {
    assert!(valid_agent_id("a1_b-2"));
    for id in ["", "../x", "a/b", "a.b", &"x".repeat(129)] {
        assert!(!valid_agent_id(id), "{id}");
    }
    let root = tempfile::tempdir().unwrap();
    assert_eq!(
        read_agent_answers(root.path(), "/anywhere", "../escape").err(),
        Some(WorkflowFileError::InvalidPath)
    );
}

struct Root {
    _dir: tempfile::TempDir,
    projects: PathBuf,
}

fn root() -> Root {
    let dir = tempfile::tempdir().unwrap();
    let projects = dir.path().join("projects");
    fs::create_dir_all(projects.join("p/run")).unwrap();
    Root {
        projects,
        _dir: dir,
    }
}

fn path(root: &Root, relative: &str) -> String {
    root.projects.join(relative).to_string_lossy().into_owned()
}

#[test]
fn a_script_under_the_root_is_served_and_capped() {
    let root = root();
    fs::write(
        root.projects.join("p/run/x.js"),
        "export const meta = {};\n",
    )
    .unwrap();
    let file = read_contained(
        &root.projects,
        &path(&root, "p/run/x.js"),
        "js",
        1024,
        false,
    )
    .unwrap();
    assert!(file.contents.contains("export const meta"));
    assert!(!file.truncated);
    fs::write(root.projects.join("p/run/big.js"), "x".repeat(2048)).unwrap();
    let capped = read_contained(
        &root.projects,
        &path(&root, "p/run/big.js"),
        "js",
        1024,
        false,
    )
    .unwrap();
    assert_eq!(capped.contents.len(), 1024);
    assert!(capped.truncated);
}

#[test]
fn relative_wrong_extension_missing_and_outside_paths_are_refused() {
    let root = root();
    fs::write(root.projects.join("p/run/x.ts"), "nope").unwrap();
    let read = |path: &str| {
        read_contained(&root.projects, path, "js", 1024, false)
            .err()
            .unwrap()
    };
    assert_eq!(read("run.js"), WorkflowFileError::InvalidPath);
    assert_eq!(
        read(&path(&root, "p/run/x.ts")),
        WorkflowFileError::InvalidPath
    );
    assert_eq!(
        read(&path(&root, "p/run/gone.js")),
        WorkflowFileError::NotFound
    );
    let outside = tempfile::tempdir().unwrap();
    fs::write(outside.path().join("evil.js"), "evil").unwrap();
    assert_eq!(
        read(&outside.path().join("evil.js").to_string_lossy()),
        WorkflowFileError::OutsideRoot
    );
    let missing_root = root.projects.join("absent");
    assert_eq!(
        read_contained(&missing_root, &path(&root, "p/run/x.js"), "js", 1, false)
            .err()
            .unwrap(),
        WorkflowFileError::RootUnavailable
    );
}

#[cfg(unix)]
#[test]
fn symlink_escapes_are_refused_on_realpath() {
    let root = root();
    let outside = tempfile::tempdir().unwrap();
    fs::write(outside.path().join("evil.js"), "evil").unwrap();
    let link = root.projects.join("p/run/sneaky.js");
    std::os::unix::fs::symlink(outside.path().join("evil.js"), &link).unwrap();
    assert!(fs::symlink_metadata(&link).unwrap().is_symlink());
    assert_eq!(
        read_contained(&root.projects, &link.to_string_lossy(), "js", 1024, false)
            .err()
            .unwrap(),
        WorkflowFileError::OutsideRoot
    );
    // A link named .js onto a file of another kind inside the root.
    fs::write(root.projects.join("p/run/data.txt"), "data").unwrap();
    let renamed = root.projects.join("p/run/renamed.js");
    std::os::unix::fs::symlink(root.projects.join("p/run/data.txt"), &renamed).unwrap();
    assert_eq!(
        read_contained(
            &root.projects,
            &renamed.to_string_lossy(),
            "js",
            1024,
            false
        )
        .err()
        .unwrap(),
        WorkflowFileError::WrongExtension
    );
}

#[cfg(unix)]
#[test]
fn a_fifo_is_refused_without_waiting_for_a_writer() {
    let root = root();
    let fifo = root.projects.join("p/run/pipe.js");
    let name = std::ffi::CString::new(fifo.to_string_lossy().as_bytes()).unwrap();
    assert_eq!(unsafe { libc::mkfifo(name.as_ptr(), 0o600) }, 0);
    assert_eq!(
        read_contained(&root.projects, &fifo.to_string_lossy(), "js", 1024, false)
            .err()
            .unwrap(),
        WorkflowFileError::NotRegularFile
    );
}

#[test]
fn answers_come_from_small_and_capped_transcripts() {
    let root = root();
    let dir = path(&root, "p/run");
    let write = |id: &str, contents: &str| {
        fs::write(
            root.projects.join(format!("p/run/agent-{id}.jsonl")),
            contents,
        )
        .unwrap();
    };
    let turn = text("a", "the answer");
    let filler = line(json!({"type": "user", "message": {"content": "x".repeat(4096)}}));
    write("small", &turn);
    let empty_edge = text("edge", "").len();
    let edge_answer = "x".repeat(TRANSCRIPT_BYTE_CAP + 1 - empty_edge);
    write("edge", &text("edge", &edge_answer));
    write(
        "boundary",
        &(filler.repeat(160) + &turn + &" ".repeat(TRANSCRIPT_BYTE_CAP - turn.len())),
    );
    write(
        "huge",
        &(turn.clone() + &filler.repeat(160) + &text("final", "final answer")),
    );
    let read = |id: &str| read_agent_answers(&root.projects, &dir, id).unwrap();
    assert_eq!(read("small"), ["the answer"]);
    assert_eq!(read("edge"), [edge_answer]);
    assert_eq!(read("huge"), ["final answer"]);
    assert_eq!(read("boundary"), ["the answer"]);
}
