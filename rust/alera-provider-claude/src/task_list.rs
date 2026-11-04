//! Claude's task tools as the turn plan, as T3 Code: `TaskCreate`,
//! `TaskUpdate` and `TaskList`, from the main agent and sub-agents alike,
//! update one task list per native session, and each change publishes the
//! whole list as `turn.plan.updated`. After a restart the first task tool
//! reads the list once from Claude's own store,
//! `<config>/tasks/<sanitized list id>/N.json`.

use super::*;
use crate::skills::SkillEnvironment;
use std::path::Path;

const TASK_TOOLS: [&str; 3] = ["TaskCreate", "TaskUpdate", "TaskList"];
const MAX_STORED_TASKS: usize = 1000;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum TaskStatus {
    Pending,
    InProgress,
    Completed,
}

impl TaskStatus {
    fn parse(value: Option<&Value>) -> Option<Self> {
        match value?.as_str()? {
            "pending" => Some(Self::Pending),
            "in_progress" => Some(Self::InProgress),
            "completed" => Some(Self::Completed),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::InProgress => "in_progress",
            Self::Completed => "completed",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub(super) struct ClaudeTask {
    id: String,
    subject: String,
    status: TaskStatus,
    active_form: Option<String>,
    blocked_by: Vec<String>,
}

pub(super) type TaskList = Vec<ClaudeTask>;

#[derive(Debug, Default)]
pub(crate) struct TaskTools {
    /// Running task tool calls: tool use id to name and input.
    calls: HashMap<String, (String, Value)>,
    /// Each native session's list. `None` means the store was unreadable,
    /// so it is not read again.
    lists: HashMap<String, Option<TaskList>>,
}

impl TaskTools {
    pub(super) fn remember(&mut self, tool_use_id: &str, name: &str, input: &Value) {
        if TASK_TOOLS.contains(&name) {
            self.calls
                .insert(tool_use_id.to_owned(), (name.to_owned(), input.clone()));
        }
    }
}

fn task_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)?
        .as_str()
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}

/// `Task #<id> created successfully: <subject>`, a sub-agent's text result.
fn created_from_text(result: &Value) -> Option<(String, String)> {
    let rest = result.as_str()?.strip_prefix("Task #")?;
    let end = rest.find(char::is_whitespace)?;
    let (id, rest) = rest.split_at(end);
    let subject = rest.strip_prefix(" created successfully: ")?.trim();
    (!id.is_empty() && !subject.is_empty()).then(|| (id.to_owned(), subject.to_owned()))
}

fn upsert(tasks: &mut TaskList, task: ClaudeTask) {
    match tasks.iter_mut().find(|known| known.id == task.id) {
        Some(known) => *known = task,
        None => tasks.push(task),
    }
}

fn blocked_by(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|id| id.as_str().map(str::trim).filter(|id| !id.is_empty()))
        .map(str::to_owned)
        .collect()
}

/// The list after one task tool result, or None when nothing changed.
pub(super) fn apply(
    tasks: &TaskList,
    tool: &str,
    input: &Value,
    result: &Value,
) -> Option<TaskList> {
    match tool {
        "TaskList" => {
            let entries = result.get("tasks")?.as_array()?;
            let next = entries
                .iter()
                .filter_map(|entry| {
                    let id = task_string(entry, "id")?;
                    let known = tasks.iter().find(|task| task.id == id);
                    Some(ClaudeTask {
                        subject: task_string(entry, "subject")?,
                        status: TaskStatus::parse(entry.get("status"))?,
                        active_form: known.and_then(|task| task.active_form.clone()),
                        blocked_by: blocked_by(entry.get("blockedBy")),
                        id,
                    })
                })
                .collect::<TaskList>();
            (!(next.is_empty() && tasks.is_empty())).then_some(next)
        }
        "TaskCreate" => {
            let task = result.get("task").unwrap_or(&Value::Null);
            let text = created_from_text(result);
            let id = task_string(task, "id").or_else(|| text.as_ref().map(|(id, _)| id.clone()))?;
            let subject = task_string(task, "subject")
                .or_else(|| text.map(|(_, subject)| subject))
                .or_else(|| task_string(input, "subject"))?;
            let mut next = tasks.clone();
            upsert(
                &mut next,
                ClaudeTask {
                    id,
                    subject,
                    status: TaskStatus::Pending,
                    active_form: task_string(input, "activeForm"),
                    blocked_by: Vec::new(),
                },
            );
            Some(next)
        }
        "TaskUpdate" => {
            if result.get("success").and_then(Value::as_bool) == Some(false) {
                return None;
            }
            if result
                .as_str()
                .is_some_and(|text| !text.starts_with("Updated task #"))
            {
                return None;
            }
            let id = task_string(input, "taskId").or_else(|| task_string(result, "taskId"))?;
            let index = tasks.iter().position(|task| task.id == id)?;
            let mut next = tasks.clone();
            if input.get("status").and_then(Value::as_str) == Some("deleted") {
                next.remove(index);
                return Some(next);
            }
            let current = &tasks[index];
            let mut task = current.clone();
            if let Some(subject) = task_string(input, "subject") {
                task.subject = subject;
            }
            if let Some(status) = TaskStatus::parse(input.get("status")) {
                task.status = status;
            }
            if let Some(active_form) = task_string(input, "activeForm") {
                task.active_form = Some(active_form);
            }
            for blocker in blocked_by(input.get("addBlockedBy")) {
                if !task.blocked_by.contains(&blocker) {
                    task.blocked_by.push(blocker);
                }
            }
            if task == *current {
                return None;
            }
            next[index] = task;
            Some(next)
        }
        _ => None,
    }
}

/// The CLI's task list directory name: each UTF-16 unit that is not ASCII
/// alphanumeric, `_` or `-` becomes `-`.
pub(super) fn sanitize(id: &str) -> String {
    id.encode_utf16()
        .map(|unit| match char::from_u32(u32::from(unit)) {
            Some(c) if c.is_ascii_alphanumeric() || c == '_' || c == '-' => c,
            _ => '-',
        })
        .collect()
}

/// The list Claude stored in [directory], or None when it is unreadable.
pub(super) fn read_stored(directory: &Path) -> Option<TaskList> {
    let mut files = std::fs::read_dir(directory)
        .ok()?
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_str()?.to_owned();
            let stem = name.strip_suffix(".json")?;
            if stem.is_empty() || !stem.bytes().all(|byte| byte.is_ascii_digit()) {
                return None;
            }
            Some((stem.parse::<u64>().unwrap_or(u64::MAX), entry.path()))
        })
        .collect::<Vec<_>>();
    files.sort();
    let tasks = files
        .into_iter()
        .take(MAX_STORED_TASKS)
        .filter_map(|(_, path)| {
            let task: Value = serde_json::from_str(&std::fs::read_to_string(path).ok()?).ok()?;
            let internal = task
                .get("metadata")
                .and_then(|metadata| metadata.get("_internal"));
            if !matches!(
                internal,
                None | Some(Value::Null) | Some(Value::Bool(false))
            ) {
                return None;
            }
            Some(ClaudeTask {
                id: task_string(&task, "id")?,
                subject: task_string(&task, "subject")?,
                status: TaskStatus::parse(task.get("status"))?,
                active_form: task_string(&task, "activeForm"),
                blocked_by: blocked_by(task.get("blockedBy")),
            })
        })
        .collect();
    Some(tasks)
}

fn plan_payload(tasks: &TaskList) -> Value {
    let plan = tasks
        .iter()
        .map(|task| {
            let mut step = json!({
                "id": task.id,
                "content": task.subject,
                "status": task.status.as_str(),
            });
            if let Some(active_form) = &task.active_form {
                step["activeForm"] = json!(active_form);
            }
            if !task.blocked_by.is_empty() {
                step["blockedBy"] = json!(task.blocked_by);
            }
            step
        })
        .collect::<Vec<_>>();
    json!({ "plan": plan })
}

/// A tool result's output: the structured result when the frame has one
/// result, else its text.
fn tool_output(block: &Value, structured: Option<&Value>) -> Value {
    if let Some(structured) = structured {
        return structured.clone();
    }
    match block.get("content") {
        Some(Value::String(text)) => Value::String(text.clone()),
        Some(Value::Array(parts)) => Value::String(
            parts
                .iter()
                .filter(|part| part["type"] == "text")
                .filter_map(|part| part["text"].as_str())
                .collect(),
        ),
        _ => Value::Null,
    }
}

impl ClaudeProvider {
    /// The plan updates a user frame's task tool results cause.
    pub(super) fn task_plan_events(
        &mut self,
        message: &claude_agent_sdk::UserMessage,
    ) -> Vec<ProviderEvent> {
        let blocks = message
            .content
            .as_array()
            .into_iter()
            .flatten()
            .filter(|block| block["type"] == "tool_result")
            .collect::<Vec<_>>();
        let structured = message
            .tool_use_result
            .as_ref()
            .filter(|_| blocks.len() == 1);
        let mut events = Vec::new();
        for block in blocks {
            let Some(tool_use_id) = block["tool_use_id"].as_str() else {
                continue;
            };
            let Some((tool, input)) = self.task_tools.calls.remove(tool_use_id) else {
                continue;
            };
            let not_run = message.raw["tool_result_meta"]
                .as_array()
                .into_iter()
                .flatten()
                .any(|meta| meta["id"] == tool_use_id && meta["non_execution_kind"].is_string());
            if block["is_error"] == true || not_run {
                continue;
            }
            let output = tool_output(block, structured);
            let Some(native) = self.session.as_ref().map(|s| s.native_thread_id.clone()) else {
                continue;
            };
            let known = self.task_tools.lists.get(&native).cloned();
            let snapshot = tool == "TaskList" && output["tasks"].is_array();
            let stored = if known.is_none() && !snapshot && !native.starts_with("pending:") {
                self.stored_task_list(&native)
            } else {
                None
            };
            let base = known
                .clone()
                .flatten()
                .or_else(|| stored.clone())
                .unwrap_or_default();
            let next = apply(&base, &tool, &input, &output).or(stored);
            let kept = next.clone().or_else(|| known.flatten());
            self.task_tools.lists.insert(native, kept);
            if let Some(tasks) = next {
                events.push(self.event(
                    EventKind::TurnPlanUpdated,
                    plan_payload(&tasks),
                    self.raw("user", message.raw.clone()),
                ));
            }
        }
        events
    }

    fn stored_task_list(&self, native: &str) -> Option<TaskList> {
        let cwd = self
            .session
            .as_ref()
            .and_then(|session| session.cwd.clone());
        let environment = SkillEnvironment::new(&self.config.options, cwd.as_deref());
        let list_id = environment
            .var("CLAUDE_CODE_TASK_LIST_ID")
            .map(|id| id.trim().to_owned())
            .filter(|id| !id.is_empty())
            .unwrap_or_else(|| native.to_owned());
        read_stored(
            &environment
                .config_dir()?
                .join("tasks")
                .join(sanitize(&list_id)),
        )
    }
}

#[cfg(test)]
#[path = "task_list_tests.rs"]
mod tests;
