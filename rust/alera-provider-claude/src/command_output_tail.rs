//! Tails the output file Claude Code writes for a foreground Bash task,
//! `<CLAUDE_CODE_TMPDIR or /tmp>/claude-<uid>/<project>/<session>/tasks/<task>.output`,
//! as T3 Code a5d97921f6. This layout is a CLI internal: any failure means
//! no live output, and the tool result still carries the final output.

use std::collections::{BTreeMap, HashMap};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

pub(super) const POLL_INTERVAL: Duration = Duration::from_millis(250);
pub(super) const MAX_LOCATE_ATTEMPTS: u32 = 40;
pub(super) const MAX_READ_BYTES: u64 = 256 * 1024;

/// Where the CLI keeps task output for [env], on Unix only.
pub(crate) fn task_output_root(env: &BTreeMap<String, String>) -> Option<PathBuf> {
    #[cfg(unix)]
    {
        let base = env
            .get("CLAUDE_CODE_TMPDIR")
            .cloned()
            .or_else(|| std::env::var("CLAUDE_CODE_TMPDIR").ok())
            .map(|dir| dir.trim().to_owned())
            .filter(|dir| !dir.is_empty())
            .unwrap_or_else(|| "/tmp".into());
        // SAFETY: getuid has no preconditions and cannot fail.
        let uid = unsafe { libc::getuid() };
        Some(Path::new(&base).join(format!("claude-{uid}")))
    }
    #[cfg(not(unix))]
    {
        let _ = env;
        None
    }
}

#[derive(Debug)]
struct Tail {
    session_id: String,
    task_id: String,
    file: Option<PathBuf>,
    locate_attempts: u32,
    offset: u64,
    /// An incomplete UTF-8 sequence the next read completes.
    pending: Vec<u8>,
}

#[derive(Debug)]
pub(crate) struct CommandOutputTails {
    root: Option<PathBuf>,
    /// By tool use id.
    tails: HashMap<String, Tail>,
    next_poll: Instant,
}

impl Default for CommandOutputTails {
    fn default() -> Self {
        Self::new(None)
    }
}

impl CommandOutputTails {
    pub(crate) fn new(root: Option<PathBuf>) -> Self {
        Self {
            root,
            tails: HashMap::new(),
            next_poll: Instant::now(),
        }
    }

    pub(crate) fn start(&mut self, tool_use_id: &str, session_id: &str, task_id: &str) {
        if self.root.is_none() || self.tails.contains_key(tool_use_id) {
            return;
        }
        if self.tails.is_empty() {
            self.next_poll = Instant::now();
        }
        self.tails.insert(
            tool_use_id.to_owned(),
            Tail {
                session_id: session_id.to_owned(),
                task_id: task_id.to_owned(),
                file: None,
                locate_attempts: 0,
                offset: 0,
                pending: Vec::new(),
            },
        );
    }

    pub(crate) fn is_active(&self) -> bool {
        !self.tails.is_empty()
    }

    pub(crate) fn next_poll(&self) -> Instant {
        self.next_poll
    }

    /// New output of every running tail, by tool use id.
    pub(crate) fn poll(&mut self) -> Vec<(String, String)> {
        self.next_poll = Instant::now() + POLL_INTERVAL;
        let root = self.root.clone();
        let mut chunks = Vec::new();
        let mut lost = Vec::new();
        for (id, tail) in &mut self.tails {
            if tail.file.is_none() {
                tail.file = root.as_deref().and_then(|root| locate(root, tail));
                if tail.file.is_none() {
                    tail.locate_attempts += 1;
                    if tail.locate_attempts >= MAX_LOCATE_ATTEMPTS {
                        lost.push(id.clone());
                    }
                    continue;
                }
            }
            let chunk = read(tail, false);
            if !chunk.is_empty() {
                chunks.push((id.clone(), chunk));
            }
        }
        for id in lost {
            self.tails.remove(&id);
        }
        chunks.sort();
        chunks
    }

    /// The last output of [tool_use_id]'s tail, which then stops.
    pub(crate) fn stop(&mut self, tool_use_id: &str) -> Option<String> {
        let mut tail = self.tails.remove(tool_use_id)?;
        if tail.file.is_none() {
            tail.file = self.root.as_deref().and_then(|root| locate(root, &tail));
        }
        tail.file.as_ref()?;
        Some(read(&mut tail, true)).filter(|chunk| !chunk.is_empty())
    }

    /// The tool use id tailing [task_id], if any.
    pub(crate) fn tool_use_of(&self, task_id: &str) -> Option<String> {
        self.tails
            .iter()
            .find(|(_, tail)| tail.task_id == task_id)
            .map(|(id, _)| id.clone())
    }

    pub(crate) fn running(&self) -> Vec<String> {
        let mut ids = self.tails.keys().cloned().collect::<Vec<_>>();
        ids.sort();
        ids
    }

    pub(crate) fn clear(&mut self) {
        self.tails.clear();
    }
}

fn locate(root: &Path, tail: &Tail) -> Option<PathBuf> {
    std::fs::read_dir(root).ok()?.flatten().find_map(|project| {
        let path = project
            .path()
            .join(&tail.session_id)
            .join("tasks")
            .join(format!("{}.output", tail.task_id));
        path.is_file().then_some(path)
    })
}

fn read(tail: &mut Tail, last: bool) -> String {
    let Some(path) = &tail.file else {
        return String::new();
    };
    let Ok(mut file) = std::fs::File::open(path) else {
        return String::new();
    };
    let Ok(size) = file.metadata().map(|metadata| metadata.len()) else {
        return String::new();
    };
    if size < tail.offset {
        tail.offset = 0;
        tail.pending.clear();
    }
    let mut prefix = "";
    let mut bytes = Vec::new();
    if size > tail.offset {
        let start = tail.offset.max(size.saturating_sub(MAX_READ_BYTES));
        if start > tail.offset {
            // A writer faster than the polls skips ahead.
            tail.pending.clear();
            prefix = "\n";
        }
        if file.seek(SeekFrom::Start(start)).is_err()
            || file.take(size - start).read_to_end(&mut bytes).is_err()
        {
            return String::new();
        }
        tail.offset = start + bytes.len() as u64;
    }
    let mut buffer = std::mem::take(&mut tail.pending);
    buffer.extend(bytes);
    let mut text = prefix.to_owned();
    text.push_str(&decode(&mut buffer, last));
    tail.pending = buffer;
    text
}

/// Decodes [buffer], leaving an incomplete trailing sequence in it unless
/// [last]. Invalid bytes become U+FFFD.
pub(super) fn decode(buffer: &mut Vec<u8>, last: bool) -> String {
    let mut text = String::new();
    let mut rest = buffer.as_slice();
    loop {
        match std::str::from_utf8(rest) {
            Ok(valid) => {
                text.push_str(valid);
                rest = &[];
                break;
            }
            Err(error) => {
                let (valid, after) = rest.split_at(error.valid_up_to());
                text.push_str(std::str::from_utf8(valid).unwrap_or_default());
                match error.error_len() {
                    Some(length) => {
                        text.push('\u{FFFD}');
                        rest = &after[length..];
                    }
                    None if last => {
                        text.push('\u{FFFD}');
                        rest = &[];
                        break;
                    }
                    None => {
                        rest = after;
                        break;
                    }
                }
            }
        }
    }
    *buffer = rest.to_vec();
    text
}
