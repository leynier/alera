//! Runtime automations and their runs.

use super::{execute, read};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string};
use crate::mcp_tools::{Invocation, ToolSpec};

const BUCKETS: &[&str] = &[
    "all",
    "needsAttention",
    "completed",
    "draft",
    "active",
    "paused",
    "blocked",
    "trashed",
];

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_automations",
            "List Automations",
            "List runtime automations with the same filters as the Automations view: state, bucket, project, agent profile, tag, workspace, section, host, or search text.",
            || {
                object(
                    &[
                        ("state", string("Automation state: draft, active, paused, blocked, archived, or trashed.")),
                        ("bucket", one_of("View bucket. needsAttention covers blocked or not ready automations and runs waiting for you.", BUCKETS)),
                        ("projectId", string("Project id.")),
                        ("profileId", string("Agent profile id the automation runs.")),
                        ("tagId", string("Automation tag id from list_automation_tags.")),
                        ("workspaceId", string("Workspace the automation belongs to.")),
                        ("sectionId", string("Workspace section id.")),
                        ("hostId", string("Host the automation runs on.")),
                        ("search", string("Text to search for in the name, slug, or description.")),
                        ("includeTrashed", boolean("Include automations in the trash.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("automation", &["list"])
                    .option_if("--state", arguments.string("state"))
                    .option_if("--bucket", arguments.string("bucket"))
                    .option_if("--project-id", arguments.string("projectId"))
                    .option_if("--profile-id", arguments.string("profileId"))
                    .option_if("--tag", arguments.string("tagId"))
                    .option_if("--workspace-id", arguments.string("workspaceId"))
                    .option_if("--section-id", arguments.string("sectionId"))
                    .option_if("--host-id", arguments.string("hostId"))
                    .option_if("--search", arguments.string("search"))
                    .flag_if("--include-trashed", arguments.flag("includeTrashed")))
            },
        ),
        read(
            "list_automation_runs",
            "List Automation Runs",
            "List automation runs, newest first, optionally for one automation.",
            || {
                object(
                    &[
                        ("automationId", string("Automation id.")),
                        ("limit", integer("Maximum runs (default 20).", 1, 100)),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("automation", &["runs"])
                    .option_if("--automation-id", arguments.string("automationId"))
                    .option(
                        "--limit",
                        arguments.integer("limit").unwrap_or(20).to_string(),
                    ))
            },
        ),
        execute(
            "run_automation",
            "Run Automation",
            "Start one run of an automation immediately, as Run Now does. By default it follows the automation's own precheck and overlap settings.",
            || {
                object(
                    &[
                        ("automationId", string("Automation id from list_automations.")),
                        ("precheck", one_of("Run or skip the configured precheck for this run.", &["run", "skip"])),
                        ("overlap", one_of("What to do when another run is active: skip, queue behind it, run the latest once, or run in parallel.", &["skip", "queue", "runLatestOnce", "forceParallel"])),
                        ("continueFromRunId", string("Earlier run whose conversation this run continues.")),
                        ("expectedRevision", integer("Refuse to run if the automation changed since this revision.", 0, u64::MAX >> 11)),
                    ],
                    &["automationId"],
                )
            },
            |arguments| {
                let precheck = arguments.string("precheck");
                Ok(Invocation::new("automation", &["run-now"])
                    .option("--id", arguments.required("automationId")?)
                    .flag_if("--precheck", precheck.as_deref() == Some("run"))
                    .flag_if("--skip-precheck", precheck.as_deref() == Some("skip"))
                    .option_if("--overlap", arguments.string("overlap"))
                    .option_if("--continue-from-run", arguments.string("continueFromRunId"))
                    .option_if(
                        "--revision",
                        arguments.integer("expectedRevision").map(|value| value.to_string()),
                    ))
            },
        ),
    ]
}
