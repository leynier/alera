use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::cli::TabCreateArgs;

const SUPPORTED_TAB_KINDS: &[&str] = &[
    "terminal",
    "codex",
    "editor",
    "markdownViewer",
    "pdf",
    "gitDiff",
];

pub(crate) fn tab_from_args(args: TabCreateArgs) -> Result<WorkspaceTabRecord, String> {
    let now = Utc::now();
    let id = Uuid::new_v4().to_string();
    let kind = SUPPORTED_TAB_KINDS
        .iter()
        .copied()
        .find(|supported| *supported == args.kind)
        .ok_or_else(|| {
            format!(
                "Unsupported tab kind \"{}\". Supported kinds: {}.",
                args.kind,
                SUPPORTED_TAB_KINDS.join(", ")
            )
        })?;
    if (args.command.is_some() || args.spawn) && kind != "terminal" {
        return Err("--command and --spawn are only supported for terminal tabs.".to_string());
    }
    let mut payload = serde_json::Map::new();
    if kind == "terminal" {
        payload.insert("terminalSessionId".to_string(), json!(id));
        if let Some(command) = args
            .command
            .as_deref()
            .map(str::trim)
            .filter(|command| !command.is_empty())
        {
            payload.insert("initialCommand".to_string(), json!(command));
        }
        if args.spawn {
            payload.insert("spawnOnCreate".to_string(), json!(true));
        }
    }
    Ok(WorkspaceTabRecord {
        id: id.clone(),
        workspace_id: args.workspace_id,
        kind: kind.to_string(),
        title: args.title,
        created_at: now,
        updated_at: now,
        payload: Value::Object(payload),
    })
}
