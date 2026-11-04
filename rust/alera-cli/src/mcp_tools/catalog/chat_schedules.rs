//! Scheduled tasks that post into an agent chat
//! (`chatOrchestrationSchedulesV1`), ported from T3 Code: `schedule_task`,
//! `list_scheduled_tasks`, `delete_scheduled_task` and
//! `run_scheduled_task_now`. Each task is an Alera automation; Alera has no
//! inbound path, so there are no webhook schedules.

use serde_json::{json, Value};

use super::{execute, read};
use crate::mcp_tools::schema::{boolean, object, string, text};
use crate::mcp_tools::{Invocation, ToolSpec};

fn schedule() -> Value {
    json!({
        "type": "object",
        "description": "Trigger, as an object: {type:'interval', everyMs} (at least 60000) or {type:'fixed_time', timeOfDay:'HH:MM', weekdays?, timezone?}. Webhook triggers are not available in Alera.",
        "properties": {
            "type": {"type": "string", "enum": ["interval", "fixed_time"]},
            "everyMs": {"type": "integer", "minimum": 60_000, "description": "Milliseconds between runs; min 60000."},
            "timeOfDay": {"type": "string", "description": "Local time as HH:MM, such as 09:30."},
            "weekdays": {
                "type": "array",
                "items": {"type": "integer", "minimum": 0, "maximum": 6},
                "description": "0 is Sunday, 6 is Saturday. Default: every day."
            },
            "timezone": {"type": "string", "description": "IANA time zone; this computer's when omitted."}
        },
        "required": ["type"],
        "additionalProperties": false
    })
}

fn task_id() -> Value {
    object(
        &[(
            "scheduledTaskId",
            string("The task id from schedule_task or list_scheduled_tasks."),
        )],
        &["scheduledTaskId"],
    )
}

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut save = execute(
        "schedule_task",
        "Schedule a Task",
        "Create scheduled work that runs later with no turn active; it needs `prompt` and `schedule`. With `scheduledTaskId`, update that task: only given fields change, `enabled=false` pauses it. `schedule` is an object, not text. By default each run posts the prompt into this chat as a new message, at most at this chat's runtime mode. Report the returned `nextRunAt`. When asked only to schedule, do not run the prompt now. Alera has no webhook triggers. Delegated children cannot schedule.",
        || {
            object(
                &[
                    ("scheduledTaskId", string("Update this task instead of creating one.")),
                    ("prompt", text("What each run does. Required for a new task.", 64 * 1024)),
                    ("schedule", schedule()),
                    ("title", text("Short name; the prompt's first line when omitted.", 120)),
                    ("enabled", boolean("Default true. false pauses the task.")),
                    (
                        "bindToCurrentChat",
                        boolean("Default true: runs post in this chat. false: a new chat per run."),
                    ),
                ],
                &[],
            )
        },
        |arguments| {
            let schedule = arguments
                .object("schedule")
                .map(|schedule| Value::Object(schedule.clone()).to_string());
            Ok(Invocation::new("chat", &["schedule", "save"])
                .option_if("--id", arguments.string("scheduledTaskId"))
                .option_if("--prompt", arguments.string("prompt"))
                .option_if("--schedule", schedule)
                .option_if("--title", arguments.string("title"))
                .option_if(
                    "--enabled",
                    arguments.optional_flag("enabled").map(|value| value.to_string()),
                )
                .option_if(
                    "--bind-to-current-chat",
                    arguments
                        .optional_flag("bindToCurrentChat")
                        .map(|value| value.to_string()),
                ))
        },
    );
    save.client_request_flag = Some("--request-id");
    let mut list = read(
        "list_scheduled_tasks",
        "List Scheduled Tasks",
        "List the scheduled tasks of this chat's project. Pass a `scheduledTaskId` to schedule_task or delete_scheduled_task. In a scheduled run, do not call this to find your task: do the prompt.",
        super::no_arguments,
        |_| Ok(Invocation::new("chat", &["schedule", "list"])),
    );
    list.idempotent = true;
    let mut delete = execute(
        "delete_scheduled_task",
        "Delete a Scheduled Task",
        "Delete one scheduled task by `scheduledTaskId`; it moves to the Automations trash and stops at once. To pause instead, use schedule_task with enabled=false.",
        task_id,
        |arguments| {
            Ok(Invocation::new("chat", &["schedule", "delete"])
                .option("--id", arguments.required("scheduledTaskId")?))
        },
    );
    delete.destructive = true;
    let run = execute(
        "run_scheduled_task_now",
        "Run a Scheduled Task Now",
        "Run one scheduled task now. Needs a full-access chat in the default interaction mode. Returns its chatId and runId. Success means started, not finished.",
        task_id,
        |arguments| {
            Ok(Invocation::new("chat", &["schedule", "run"])
                .option("--id", arguments.required("scheduledTaskId")?))
        },
    );
    vec![save, list, delete, run]
}
