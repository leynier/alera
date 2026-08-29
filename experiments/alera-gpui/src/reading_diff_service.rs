use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;

use alera_core::reading_diff::{self, CompiledChunk, PreparedDiff, ReadingDiffChunk};
use async_channel::{Receiver, Sender};
use serde::{Deserialize, Serialize};

use crate::reading_diff_agent::{run_reading_diff_agent, ReadingDiffAgentRequest};

#[derive(Clone)]
pub struct ReadingDiffService {
    commands: Sender<Command>,
}

#[allow(clippy::large_enum_variant)]
enum Command {
    Generate {
        request: ReadingDiffRequest,
        cancel: Arc<AtomicBool>,
        progress: Sender<ReadingDiffProgress>,
        reply: Sender<Result<ReadingDiffResult, String>>,
    },
    Close,
}

#[derive(Clone, Debug)]
pub struct ReadingDiffRequest {
    pub key: String,
    pub raw_diff: Vec<u8>,
    pub working_directory: String,
    pub agent: String,
    pub model: String,
    pub effort: Option<String>,
    pub instructions: String,
    pub timeout_seconds: u64,
    pub ignore_cache: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ReadingDiffResult {
    pub diff: Vec<u8>,
    pub summary: String,
    pub changed_lines: u32,
    pub retained_changed_lines: u32,
    pub agent_label: String,
    pub model: String,
    pub effort: Option<String>,
    pub chunk_count: usize,
    pub from_cache: bool,
}

#[derive(Clone, Debug)]
pub struct ReadingDiffProgress {
    pub stage: ReadingDiffStage,
    pub completed_chunks: usize,
    pub total_chunks: usize,
    pub current_chunk: Option<usize>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ReadingDiffStage {
    Preparing,
    Generating,
    Repairing,
    Combining,
    Cached,
}

impl ReadingDiffService {
    pub fn start() -> Self {
        let (commands, receiver) = async_channel::bounded(8);
        let cache_directory = dirs::cache_dir()
            .unwrap_or_else(std::env::temp_dir)
            .join("alera-gpui")
            .join("reading-diffs");
        thread::Builder::new()
            .name("alera-gpui-reading-diff".to_string())
            .spawn(move || run(receiver, cache_directory))
            .expect("failed to start reading diff service");
        Self { commands }
    }

    pub async fn generate(
        &self,
        request: ReadingDiffRequest,
        cancel: Arc<AtomicBool>,
        progress: Sender<ReadingDiffProgress>,
    ) -> Result<ReadingDiffResult, String> {
        let (reply, response) = async_channel::bounded(1);
        self.commands
            .send(Command::Generate {
                request,
                cancel,
                progress,
                reply,
            })
            .await
            .map_err(|_| "Reading Diff Service Is Closed.".to_string())?;
        response
            .recv()
            .await
            .map_err(|_| "Reading Diff Service Closed Before Replying.".to_string())?
    }
}

impl Drop for ReadingDiffService {
    fn drop(&mut self) {
        if self.commands.sender_count() == 1 {
            let _ = self.commands.try_send(Command::Close);
        }
    }
}

fn run(commands: Receiver<Command>, cache_directory: PathBuf) {
    let mut cache = HashMap::<u64, ReadingDiffResult>::new();
    while let Ok(command) = commands.recv_blocking() {
        match command {
            Command::Generate {
                request,
                cancel,
                progress,
                reply,
            } => {
                let result = generate(&request, &cancel, &progress, &mut cache, &cache_directory);
                let _ = reply.send_blocking(result);
            }
            Command::Close => return,
        }
    }
}

fn generate(
    request: &ReadingDiffRequest,
    cancel: &Arc<AtomicBool>,
    progress: &Sender<ReadingDiffProgress>,
    cache: &mut HashMap<u64, ReadingDiffResult>,
    cache_directory: &Path,
) -> Result<ReadingDiffResult, String> {
    let agent = effective_agent(&request.agent);
    let cache_key = request_cache_key(request, agent);
    if !request.ignore_cache {
        if let Some(cached) = cache
            .get(&cache_key)
            .cloned()
            .or_else(|| read_cached_result(cache_directory, cache_key))
        {
            let mut cached = cached;
            cached.from_cache = true;
            let _ = progress.send_blocking(ReadingDiffProgress {
                stage: ReadingDiffStage::Cached,
                completed_chunks: cached.chunk_count,
                total_chunks: cached.chunk_count,
                current_chunk: None,
            });
            return Ok(cached);
        }
    }
    let _ = progress.send_blocking(ReadingDiffProgress {
        stage: ReadingDiffStage::Preparing,
        completed_chunks: 0,
        total_chunks: 0,
        current_chunk: None,
    });
    let max_chunk_bytes = (agent == "copilot").then_some(4096);
    let prepared =
        reading_diff::prepare(&request.raw_diff, max_chunk_bytes).map_err(|error| error.message)?;
    let mut compiled = Vec::new();
    let mut agent_label = agent_label(agent).to_string();
    for chunk in &prepared.chunks {
        check_canceled(cancel)?;
        let _ = progress.send_blocking(ReadingDiffProgress {
            stage: ReadingDiffStage::Generating,
            completed_chunks: compiled.len(),
            total_chunks: prepared.chunks.len(),
            current_chunk: Some(chunk.index as usize + 1),
        });
        let prompt = build_prompt(&prepared, chunk, &request.instructions);
        let (plan, label) = run_reading_diff_agent(ReadingDiffAgentRequest {
            agent,
            model: &request.model,
            effort: request.effort.as_deref(),
            prompt: &prompt,
            working_directory: &request.working_directory,
            timeout_seconds: request.timeout_seconds,
            cancel: cancel.clone(),
        })?;
        agent_label = label;
        let result =
            match reading_diff::compile_with_source(&chunk.raw_diff, &request.raw_diff, &plan) {
                Ok(result) => result,
                Err(error) => {
                    let _ = progress.send_blocking(ReadingDiffProgress {
                        stage: ReadingDiffStage::Repairing,
                        completed_chunks: compiled.len(),
                        total_chunks: prepared.chunks.len(),
                        current_chunk: Some(chunk.index as usize + 1),
                    });
                    let repair = build_repair_prompt(&prompt, &plan, &error.message);
                    let (plan, label) = run_reading_diff_agent(ReadingDiffAgentRequest {
                        agent,
                        model: &request.model,
                        effort: request.effort.as_deref(),
                        prompt: &repair,
                        working_directory: &request.working_directory,
                        timeout_seconds: request.timeout_seconds,
                        cancel: cancel.clone(),
                    })?;
                    agent_label = label;
                    reading_diff::compile_with_source(&chunk.raw_diff, &request.raw_diff, &plan)
                        .map_err(|error| {
                            format!(
                                "The Replacement Reading Diff Plan Was Invalid: {}",
                                error.message
                            )
                        })?
                }
            };
        compiled.push(CompiledChunk {
            index: chunk.index,
            continuation_preamble: chunk.continuation_preamble.clone(),
            result,
        });
    }
    check_canceled(cancel)?;
    let _ = progress.send_blocking(ReadingDiffProgress {
        stage: ReadingDiffStage::Combining,
        completed_chunks: prepared.chunks.len(),
        total_chunks: prepared.chunks.len(),
        current_chunk: None,
    });
    let merged =
        reading_diff::merge_chunks(compiled, &request.raw_diff).map_err(|error| error.message)?;
    let result = ReadingDiffResult {
        diff: merged.reading_diff,
        summary: merged.summary,
        changed_lines: merged.changed_lines,
        retained_changed_lines: merged.retained_changed_lines,
        agent_label,
        model: request.model.clone(),
        effort: request.effort.clone(),
        chunk_count: prepared.chunks.len(),
        from_cache: false,
    };
    cache.insert(cache_key, result.clone());
    write_cached_result(cache_directory, cache_key, &result);
    Ok(result)
}

fn read_cached_result(cache_directory: &Path, key: u64) -> Option<ReadingDiffResult> {
    let bytes = std::fs::read(cache_directory.join(format!("{key:016x}.json"))).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn write_cached_result(cache_directory: &Path, key: u64, result: &ReadingDiffResult) {
    let Ok(bytes) = serde_json::to_vec(result) else {
        return;
    };
    if std::fs::create_dir_all(cache_directory).is_ok() {
        let _ = std::fs::write(cache_directory.join(format!("{key:016x}.json")), bytes);
    }
}

fn effective_agent(configured: &str) -> &str {
    match configured {
        "codex" | "claude" | "copilot" | "pi" | "grok" => configured,
        _ => "codex",
    }
}

fn agent_label(agent: &str) -> &'static str {
    match agent {
        "claude" => "Claude Code",
        "copilot" => "GitHub Copilot",
        "pi" => "Pi",
        "grok" => "Grok Build",
        _ => "Codex",
    }
}

fn check_canceled(cancel: &AtomicBool) -> Result<(), String> {
    if cancel.load(Ordering::Relaxed) {
        Err("Reading Diff Generation Was Canceled.".to_string())
    } else {
        Ok(())
    }
}

fn request_cache_key(request: &ReadingDiffRequest, agent: &str) -> u64 {
    let mut hasher = DefaultHasher::new();
    request.raw_diff.hash(&mut hasher);
    agent.hash(&mut hasher);
    request.model.hash(&mut hasher);
    request.effort.hash(&mut hasher);
    request.instructions.hash(&mut hasher);
    reading_diff::RUBRIC_VERSION.hash(&mut hasher);
    reading_diff::SCHEMA_VERSION.hash(&mut hasher);
    hasher.finish()
}

fn build_prompt(prepared: &PreparedDiff, chunk: &ReadingDiffChunk, instructions: &str) -> String {
    format!(
        "You are preparing a non-applicable reading diff. Return only one JSON object matching the supplied schema.\n\nContract: MeatPlanV{}\nRubric: {}\n\nReturn an object that satisfies this exact schema:\n<output_schema>\n{}\n</output_schema>\n\nThe original numbered unified diff below is immutable. Line numbers before `|` are coordinates, not source text. You may only propose:\n- remove: inclusive ranges of hunk source rows that are review noise;\n- replace: one exact source span with a strict source projection that only removes text and inserts `...` or `…`;\n- fold: inclusive ranges of at least two rows within one hunk and one diff marker;\n- summary: one concise sentence describing the behavioral change.\n\nNever remove or alter file headers, hunk headers, rename/copy metadata, mode metadata, binary markers, no-newline markers, or format-patch trailers. Keep moved code symmetric. Keep Python decorators, suite owners, delimiter boundaries, and definitions needed by retained rows. Imports are elided deterministically by Alera and do not need plan entries. Prefer retaining uncertain lines. The Rust compiler rejects invented text and is the final authority.\n\n<user_instructions>\n{}\n</user_instructions>\n\n<numbered_diff chunk=\"{}\" total=\"{}\">\n{}\n</numbered_diff>",
        prepared.schema_version,
        prepared.rubric_version,
        reading_diff::plan_schema(),
        if instructions.trim().is_empty() { "(none)" } else { instructions.trim() },
        chunk.index + 1,
        prepared.chunks.len(),
        chunk.numbered_diff,
    )
}

fn build_repair_prompt(original: &str, rejected: &str, error: &str) -> String {
    format!(
        "{original}\n\nYour previous complete plan was rejected by the deterministic compiler:\n<compiler_error>\n{}\n</compiler_error>\n\n<rejected_plan>\n{}\n</rejected_plan>\n\nReturn a complete replacement plan against the original numbered coordinates. Do not return a patch or commentary.",
        truncate(error, 512),
        truncate(rejected, 2048),
    )
}

fn truncate(value: &str, max_chars: usize) -> String {
    if value.chars().count() <= max_chars {
        value.to_string()
    } else {
        format!("{}...", value.chars().take(max_chars).collect::<String>())
    }
}

#[cfg(test)]
mod tests {
    use super::{effective_agent, request_cache_key, ReadingDiffRequest};

    #[test]
    fn unsupported_agents_fall_back_to_codex_diff_only() {
        assert_eq!(effective_agent("cursor"), "codex");
        assert_eq!(effective_agent("fx"), "codex");
        assert_eq!(effective_agent("claude"), "claude");
    }

    #[test]
    fn cache_key_changes_with_instructions() {
        let request = ReadingDiffRequest {
            key: "diff".into(),
            raw_diff: b"diff --git a/a b/a\n".to_vec(),
            working_directory: ".".into(),
            agent: "codex".into(),
            model: "gpt-5.5".into(),
            effort: Some("low".into()),
            instructions: "first".into(),
            timeout_seconds: 30,
            ignore_cache: false,
        };
        let first = request_cache_key(&request, "codex");
        let mut changed = request;
        changed.instructions = "second".into();
        assert_ne!(first, request_cache_key(&changed, "codex"));
    }
}
