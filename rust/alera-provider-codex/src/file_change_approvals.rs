//! The files a Codex file-change approval asks about, as T3 Code's
//! `codexFileChangeApprovalPrompt`.
//!
//! `item/fileChange/requestApproval` names only its item, so the paths come
//! from that item's `item/started`. An approval that arrives before its item
//! started gets no file list and never borrows another item's. The legacy
//! `applyPatchApproval` carries its own `fileChanges` map.

use crate::wire;
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};

/// Items tracked at once; later file-change items go without a file list.
const MAX_TRACKED_ITEMS: usize = 256;
/// Files listed in one approval before the rest become `+N more`.
const MAX_LISTED_FILES: usize = 20;

/// What one file change does: `add`, `delete` or `update`, and where an
/// update moves the file.
struct Change {
    kind: String,
    move_path: Option<String>,
}

type Changes = BTreeMap<String, Change>;

/// The changed files of each running file-change item, by native item id,
/// with the native turn it runs in.
#[derive(Default)]
pub(crate) struct FileChangePaths {
    by_item: HashMap<String, (Option<String>, Changes)>,
}

impl FileChangePaths {
    /// Follows a notification: a started or patched file-change item records
    /// its files, and a completed item or a settled turn forgets them.
    pub(crate) fn observe(&mut self, method: &str, params: &Value) {
        match method {
            "item/started" | "item/updated" | "item/completed" => {
                let Some(item) = params
                    .get("item")
                    .filter(|item| item["type"] == "fileChange")
                else {
                    return;
                };
                let Some(id) = wire::string(item, "id") else {
                    return;
                };
                if method == "item/completed" {
                    self.by_item.remove(&id);
                } else {
                    self.record(id, turn_id(params), item.get("changes"));
                }
            }
            "item/fileChange/patchUpdated" => {
                if let Some(id) = wire::string(params, "itemId") {
                    self.record(id, turn_id(params), params.get("changes"));
                }
            }
            "turn/completed" | "turn/aborted" => {
                let turn = turn_id(params);
                if turn.is_some() {
                    self.by_item.retain(|_, (item_turn, _)| *item_turn != turn);
                }
            }
            _ => {}
        }
    }

    /// The approval's detail: its reason, else the files it changes, else
    /// the root it asks write access for.
    pub(crate) fn approval_detail(&self, method: &str, params: &Value) -> Option<String> {
        if let Some(reason) = trimmed(params, "reason") {
            return Some(reason);
        }
        let files = match method {
            "item/fileChange/requestApproval" => wire::string(params, "itemId")
                .and_then(|id| self.by_item.get(&id))
                .and_then(|(_, changes)| describe(changes)),
            "applyPatchApproval" => params
                .get("fileChanges")
                .and_then(Value::as_object)
                .map(|changes| {
                    changes
                        .iter()
                        .map(|(path, change)| (path.clone(), parse_kind(change)))
                        .collect::<Changes>()
                })
                .and_then(|changes| describe(&changes)),
            _ => None,
        };
        files.or_else(|| trimmed(params, "grantRoot"))
    }

    fn record(&mut self, id: String, turn: Option<String>, changes: Option<&Value>) {
        if !self.by_item.contains_key(&id) && self.by_item.len() >= MAX_TRACKED_ITEMS {
            return;
        }
        let changes = changes
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|change| {
                let path = wire::string(change, "path").filter(|path| !path.is_empty())?;
                Some((path, parse_kind(change.get("kind").unwrap_or(change))))
            })
            .collect();
        self.by_item.insert(id, (turn, changes));
    }
}

/// A change kind is `{type, move_path}` in v2 items and legacy patches, or a
/// bare string.
fn parse_kind(value: &Value) -> Change {
    if let Some(kind) = value.as_str() {
        return Change {
            kind: kind.to_owned(),
            move_path: None,
        };
    }
    Change {
        kind: wire::string(value, "type").unwrap_or_else(|| "update".into()),
        move_path: wire::string(value, "move_path")
            .or_else(|| wire::string(value, "movePath"))
            .filter(|path| !path.is_empty()),
    }
}

/// One `kind path` line per file, sorted by path, at most 20 and then
/// `+N more`. A move reads `update path -> new path`.
fn describe(changes: &Changes) -> Option<String> {
    if changes.is_empty() {
        return None;
    }
    let mut lines = changes
        .iter()
        .take(MAX_LISTED_FILES)
        .map(|(path, change)| match &change.move_path {
            Some(target) if change.kind == "update" => format!("update {path} -> {target}"),
            _ => format!("{} {path}", change.kind),
        })
        .collect::<Vec<_>>();
    if changes.len() > MAX_LISTED_FILES {
        lines.push(format!("+{} more", changes.len() - MAX_LISTED_FILES));
    }
    Some(lines.join("\n"))
}

fn turn_id(params: &Value) -> Option<String> {
    wire::string(params, "turnId").or_else(|| wire::nested_string(params, "turn", "id"))
}

fn trimmed(params: &Value, key: &str) -> Option<String> {
    wire::string(params, key)
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}
