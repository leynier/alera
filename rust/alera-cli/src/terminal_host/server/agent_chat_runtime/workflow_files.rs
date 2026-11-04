//! Contained reads of the files Claude Code keeps for a workflow run: its
//! script and its members' transcripts. The paths come from the provider's
//! run handles, never from a client, and are still only trusted this far,
//! as T3 Code's `readContainedWorkflowFile` trusts them:
//!
//! - the file's own realpath must live under the provider's files root, so a
//!   symlink, a symlinked leaf included, cannot escape it;
//! - only the expected extension is served;
//! - only a regular file is read, opened without blocking on a FIFO, and the
//!   opened file must still be the one the path names;
//! - reads are capped rather than refused, with a truncation marker.

use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use serde_json::Value;

/// Why a workflow file could not be served. `code` is the wire reason.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum WorkflowFileError {
    InvalidPath,
    RootUnavailable,
    NotFound,
    OutsideRoot,
    WrongExtension,
    NotRegularFile,
    ChangedDuringRead,
    ReadFailed,
}

impl WorkflowFileError {
    pub(crate) fn code(self) -> &'static str {
        match self {
            Self::InvalidPath => "invalidPath",
            Self::RootUnavailable => "rootUnavailable",
            Self::NotFound => "notFound",
            Self::OutsideRoot => "outsideRoot",
            Self::WrongExtension => "wrongExtension",
            Self::NotRegularFile => "notRegularFile",
            Self::ChangedDuringRead => "changedDuringRead",
            Self::ReadFailed => "readFailed",
        }
    }

    pub(crate) fn message(self) -> &'static str {
        match self {
            Self::InvalidPath => "The workflow file path is not one Alera reads.",
            Self::RootUnavailable => "The agent's run files directory is unavailable.",
            Self::NotFound => "The workflow file no longer exists.",
            Self::OutsideRoot => "The workflow file is outside the agent's run files.",
            Self::WrongExtension => "The workflow file is not the expected kind.",
            Self::NotRegularFile => "The workflow file is not a regular file.",
            Self::ChangedDuringRead => "The workflow file changed while it was read.",
            Self::ReadFailed => "The workflow file could not be read.",
        }
    }
}

pub(crate) struct ContainedFile {
    pub path: PathBuf,
    pub contents: String,
    pub truncated: bool,
}

fn has_extension(path: &Path, extension: &str) -> bool {
    path.extension().and_then(|value| value.to_str()) == Some(extension)
}

#[cfg(unix)]
fn open_without_blocking(path: &Path) -> std::io::Result<File> {
    use std::os::unix::fs::OpenOptionsExt;
    OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(path)
}

#[cfg(not(unix))]
fn open_without_blocking(path: &Path) -> std::io::Result<File> {
    OpenOptions::new().read(true).open(path)
}

#[cfg(unix)]
fn same_file(opened: &fs::Metadata, named: &fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;
    opened.ino() == named.ino() && opened.dev() == named.dev()
}

#[cfg(not(unix))]
fn same_file(_: &fs::Metadata, named: &fs::Metadata) -> bool {
    named.is_file()
}

/// Reads `path` under `root`. `extension` has no dot. With `tail`, the last
/// `byte_cap` bytes and one more are read, so a window that starts on a line
/// boundary still sees the newline before it.
pub(crate) fn read_contained(
    root: &Path,
    path: &str,
    extension: &str,
    byte_cap: usize,
    tail: bool,
) -> Result<ContainedFile, WorkflowFileError> {
    let requested = Path::new(path);
    if !requested.is_absolute() || !has_extension(requested, extension) {
        return Err(WorkflowFileError::InvalidPath);
    }
    let root = fs::canonicalize(root).map_err(|_| WorkflowFileError::RootUnavailable)?;
    let resolved = fs::canonicalize(requested).map_err(|_| WorkflowFileError::NotFound)?;
    if resolved == root || !resolved.starts_with(&root) {
        return Err(WorkflowFileError::OutsideRoot);
    }
    if !has_extension(&resolved, extension) {
        return Err(WorkflowFileError::WrongExtension);
    }
    let mut file = open_without_blocking(&resolved).map_err(|_| WorkflowFileError::ReadFailed)?;
    let opened = file.metadata().map_err(|_| WorkflowFileError::ReadFailed)?;
    if !opened.is_file() {
        return Err(WorkflowFileError::NotRegularFile);
    }
    let named = fs::symlink_metadata(&resolved).map_err(|_| WorkflowFileError::ReadFailed)?;
    if !same_file(&opened, &named) {
        return Err(WorkflowFileError::ChangedDuringRead);
    }
    let size = opened.len();
    let window = (byte_cap as u64 + u64::from(tail)).min(size);
    if tail {
        file.seek(SeekFrom::Start(size - window))
            .map_err(|_| WorkflowFileError::ReadFailed)?;
    }
    let mut bytes = Vec::with_capacity(window as usize);
    file.take(window)
        .read_to_end(&mut bytes)
        .map_err(|_| WorkflowFileError::ReadFailed)?;
    Ok(ContainedFile {
        path: resolved,
        contents: String::from_utf8_lossy(&bytes).into_owned(),
        truncated: size > window,
    })
}

/// A workflow script, capped at 256 KiB.
pub(crate) const SCRIPT_BYTE_CAP: usize = 256 * 1024;
/// The end of a member's transcript, where its final answers are.
pub(crate) const TRANSCRIPT_BYTE_CAP: usize = 512 * 1024;

/// A member id names a file, so anything path-shaped is refused outright.
pub(crate) fn valid_agent_id(agent_id: &str) -> bool {
    (1..=128).contains(&agent_id.len())
        && agent_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
}

/// The assistant text of each turn in a member's JSONL transcript. Harness
/// bookkeeping (`attachment` lines, `isMeta` entries) is not conversation,
/// and one assistant message split across lines sharing a `message.id` is
/// one turn. A line the byte cap cut in half is skipped.
pub(crate) fn parse_agent_answers(contents: &str) -> Vec<String> {
    let mut turns: Vec<String> = Vec::new();
    let mut by_message: std::collections::HashMap<String, usize> = Default::default();
    for line in contents.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let Ok(entry) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if entry.get("type").and_then(Value::as_str) != Some("assistant")
            || entry.get("isMeta") == Some(&Value::Bool(true))
        {
            continue;
        }
        let message = entry.get("message");
        let Some(content) = message
            .and_then(|message| message.get("content"))
            .and_then(Value::as_array)
        else {
            continue;
        };
        let body = content
            .iter()
            .filter(|block| block.get("type").and_then(Value::as_str) == Some("text"))
            .filter_map(|block| block.get("text").and_then(Value::as_str))
            .filter(|text| !text.trim().is_empty())
            .collect::<Vec<_>>()
            .join("\n\n");
        if body.is_empty() {
            continue;
        }
        let id = message
            .and_then(|message| message.get("id"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|id| !id.is_empty());
        if let Some(existing) = id.and_then(|id| by_message.get(id)) {
            turns[*existing] = format!("{}\n\n{body}", turns[*existing]);
            continue;
        }
        if let Some(id) = id {
            by_message.insert(id.to_owned(), turns.len());
        }
        turns.push(body);
    }
    turns
}

/// A member's answers from its transcript. A capped read drops the first
/// line, which the cap may have cut.
pub(crate) fn read_agent_answers(
    root: &Path,
    transcript_dir: &str,
    agent_id: &str,
) -> Result<Vec<String>, WorkflowFileError> {
    if !valid_agent_id(agent_id) {
        return Err(WorkflowFileError::InvalidPath);
    }
    let path = Path::new(transcript_dir).join(format!("agent-{agent_id}.jsonl"));
    let file = read_contained(
        root,
        &path.to_string_lossy(),
        "jsonl",
        TRANSCRIPT_BYTE_CAP,
        true,
    )?;
    let contents = if file.truncated {
        file.contents.split_once('\n').map_or("", |(_, rest)| rest)
    } else {
        file.contents.as_str()
    };
    Ok(parse_agent_answers(contents))
}

#[cfg(test)]
#[path = "workflow_files_tests.rs"]
mod tests;
