//! The text of a parent wake: one block per delegated task, with each
//! settled result inlined within a shared byte budget.
//!
//! The text depends only on the sealed cohort and the task rows it names, so
//! a resend after a restart is byte-identical and replays the send receipt.

use alera_core::runtime::{
    ChatOrchestrationTask, ChatOrchestrationTaskStatus, ChatOrchestrationWakeEntry,
};

/// The budget for every task block together (T3 Code's inline budget).
pub(super) const WAKE_TEXT_MAX_BYTES: usize = 16_000;
/// A result whose share is smaller than this is left out instead of cut to
/// a useless stub.
const MIN_SHARE: usize = 256;
const SEPARATOR: &str = "\n\n";
const FENCE: &str = "```";

/// One task of a cohort, as the wake describes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct WakeTask {
    pub task_id: String,
    pub title: Option<String>,
    /// The status the cohort froze, not the live one.
    pub status: Option<ChatOrchestrationTaskStatus>,
    pub child_chat_id: Option<String>,
    pub result: Option<String>,
    pub error: Option<(Option<String>, String)>,
}

impl WakeTask {
    /// The entry's frozen status, with the result and error only when the
    /// entry is terminal and the row is still the revision it froze. `None`
    /// for a task row that no longer exists.
    pub(super) fn from_entry(
        entry: &ChatOrchestrationWakeEntry,
        task: Option<&ChatOrchestrationTask>,
    ) -> Self {
        let mut wake = Self {
            task_id: entry.task_id.clone(),
            title: None,
            status: task.map(|_| entry.task_status),
            child_chat_id: None,
            result: None,
            error: None,
        };
        let Some(task) = task else {
            return wake;
        };
        wake.title = task.title.clone();
        wake.child_chat_id = task.child_chat_id.clone();
        if entry.task_status.is_terminal() && task.revision == entry.task_revision {
            wake.result = task
                .result_text
                .clone()
                .filter(|text| !text.trim().is_empty());
            if task.error.is_some() || task.error_code.is_some() {
                wake.error = Some((
                    task.error_code.clone(),
                    task.error.clone().unwrap_or_default(),
                ));
            }
        }
        wake
    }

    fn header(&self) -> String {
        let title = self
            .title
            .as_deref()
            .map(one_line)
            .filter(|title| !title.is_empty())
            .map(|title| format!(" ({title})"))
            .unwrap_or_default();
        match self.status {
            Some(status) => format!(
                "Delegated task {}{title} [{}]",
                self.task_id,
                status_label(status)
            ),
            None => format!("Delegated task {}", self.task_id),
        }
    }

    /// The full body, or `None` when there is nothing to inline.
    fn body(&self) -> Option<String> {
        let failed = matches!(
            self.status,
            Some(
                ChatOrchestrationTaskStatus::Failed
                    | ChatOrchestrationTaskStatus::Interrupted
                    | ChatOrchestrationTaskStatus::Cancelled
            )
        );
        let error = self
            .error
            .as_ref()
            .filter(|_| failed)
            .map(|(code, message)| {
                let message = if message.is_empty() {
                    "The delegated task did not complete."
                } else {
                    message
                };
                match code {
                    Some(code) => format!("Error ({code}): {message}"),
                    None => format!("Error: {message}"),
                }
            });
        match (error, &self.result) {
            (Some(error), Some(result)) => Some(format!("{error}\n{result}")),
            (Some(error), None) => Some(error),
            (None, Some(result)) => Some(result.clone()),
            (None, None) => None,
        }
    }

    /// Where the full result is read.
    fn reader(&self) -> String {
        match &self.child_chat_id {
            Some(chat) => format!("chat_read and chatId {chat}"),
            None => format!("chat_task_status and taskId {}", self.task_id),
        }
    }

    fn truncation_note(&self) -> String {
        format!(
            "\n[Truncated to fit this message. Read the full result with {}.]",
            self.reader()
        )
    }

    fn omission(&self) -> String {
        format!(
            "{}: the result did not fit in this message. Read it with {}.",
            self.header(),
            self.reader()
        )
    }

    fn bare(&self) -> String {
        match self.status {
            None => format!(
                "{} is no longer recorded. Check it with chat_task_status and taskId {}.",
                self.header(),
                self.task_id
            ),
            Some(_) => format!(
                "{}. Read it with chat_task_status and taskId {}.",
                self.header(),
                self.task_id
            ),
        }
    }
}

/// The wake text for a cohort's tasks, in entry order. Every task id always
/// appears; results share `WAKE_TEXT_MAX_BYTES` fairly.
pub(super) fn wake_text(tasks: &[WakeTask]) -> String {
    let bodies: Vec<Option<String>> = tasks.iter().map(WakeTask::body).collect();
    let headers: Vec<String> = tasks
        .iter()
        .map(|task| format!("{}:\n", task.header()))
        .collect();
    let fixed: usize = tasks
        .iter()
        .zip(&bodies)
        .zip(&headers)
        .map(|((task, body), header)| match body {
            Some(_) => header.len(),
            None => task.bare().len(),
        })
        .sum::<usize>()
        + SEPARATOR.len() * tasks.len().saturating_sub(1);
    let budget = WAKE_TEXT_MAX_BYTES.saturating_sub(fixed);
    let sizes: Vec<usize> = bodies
        .iter()
        .map(|body| body.as_ref().map_or(0, String::len))
        .collect();
    // A left-out result still costs its omission line, so leaving one out
    // shrinks the budget of the rest; repeat until no new share is too small.
    let mut omitted = vec![false; tasks.len()];
    let shares = loop {
        let cost: usize = (0..tasks.len())
            .filter(|&index| omitted[index])
            .map(|index| {
                tasks[index]
                    .omission()
                    .len()
                    .saturating_sub(headers[index].len())
            })
            .sum();
        let kept: Vec<usize> = (0..tasks.len())
            .map(|index| if omitted[index] { 0 } else { sizes[index] })
            .collect();
        let shares = fair_shares(&kept, budget.saturating_sub(cost));
        let mut changed = false;
        for index in 0..tasks.len() {
            if !omitted[index] && shares[index] < sizes[index] && shares[index] < MIN_SHARE {
                omitted[index] = true;
                changed = true;
            }
        }
        if !changed {
            break shares;
        }
    };
    tasks
        .iter()
        .enumerate()
        .map(|(index, task)| match &bodies[index] {
            None => task.bare(),
            Some(_) if omitted[index] => task.omission(),
            Some(body) if body.len() <= shares[index] => format!("{}{body}", headers[index]),
            Some(body) => {
                let note = task.truncation_note();
                let room = shares[index].saturating_sub(note.len() + FENCE.len() + 1);
                format!("{}{}{note}", headers[index], cut(body, room))
            }
        })
        .collect::<Vec<_>>()
        .join(SEPARATOR)
}

/// Max-min fair shares of `budget`: every size that fits under an equal
/// split gets all it asks, and the rest split what remains. Ties go to the
/// lower index.
pub(super) fn fair_shares(sizes: &[usize], budget: usize) -> Vec<usize> {
    let mut order: Vec<usize> = (0..sizes.len()).collect();
    order.sort_by_key(|&index| (sizes[index], index));
    let mut shares = vec![0; sizes.len()];
    let mut remaining = budget;
    for (position, &index) in order.iter().enumerate() {
        let left = order.len() - position;
        let equal = remaining / left;
        let share = sizes[index].min(equal);
        shares[index] = share;
        remaining -= share;
    }
    shares
}

/// `text` cut to at most `max` bytes on a char boundary, with an open code
/// fence closed.
fn cut(text: &str, max: usize) -> String {
    let mut end = max.min(text.len());
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    let mut cut = text[..end].to_owned();
    if cut.matches(FENCE).count() % 2 == 1 {
        if !cut.ends_with('\n') {
            cut.push('\n');
        }
        cut.push_str(FENCE);
    }
    cut
}

fn one_line(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn status_label(status: ChatOrchestrationTaskStatus) -> String {
    serde_json::to_value(status)
        .ok()
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .unwrap_or_default()
}
