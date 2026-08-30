use std::collections::{BTreeMap, BTreeSet};

use gpui::EntityId;

use crate::model::WorkspaceTab;

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub(super) struct EditorKey {
    pub workspace: String,
    pub path: String,
}

#[derive(Clone)]
pub(super) struct EditorWrite {
    pub key: EditorKey,
    pub editor: EntityId,
    pub workspace_path: String,
    pub content: String,
    pub overwrite: bool,
    sequence: u64,
}

#[derive(Clone)]
pub(super) struct EditorAutosave {
    pub key: EditorKey,
    pub editor: EntityId,
    sequence: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct EditorConfirmation {
    pub key: EditorKey,
    pub editor: EntityId,
    sequence: u64,
}

struct EditorFailure {
    target: EditorConfirmation,
    message: String,
}

#[derive(Default)]
pub(super) struct EditorRequests {
    sequence: u64,
    pending: BTreeMap<EditorKey, u64>,
    autosaves: BTreeMap<EditorKey, u64>,
    failures: BTreeMap<EditorKey, EditorFailure>,
}

impl EditorRequests {
    pub fn begin_write(&mut self, key: EditorKey, editor: EntityId, workspace_path: String, content: String, overwrite: bool) -> Option<EditorWrite> {
        if self.pending.contains_key(&key) { return None; }
        self.sequence = self.sequence.wrapping_add(1);
        self.pending.insert(key.clone(), self.sequence);
        self.autosaves.remove(&key);
        self.failures.remove(&key);
        Some(EditorWrite { key, editor, workspace_path, content, overwrite, sequence: self.sequence })
    }

    pub fn finish_write(&mut self, request: &EditorWrite) -> bool {
        if self.pending.get(&request.key) != Some(&request.sequence) { return false; }
        self.pending.remove(&request.key);
        true
    }

    pub fn is_writing(&self, key: &EditorKey) -> bool { self.pending.contains_key(key) }
    pub fn failure(&self, key: &EditorKey) -> Option<&str> { self.failures.get(key).map(|failure| failure.message.as_str()) }
    pub fn confirmation(&self, key: &EditorKey) -> Option<EditorConfirmation> { self.failures.get(key).map(|failure| failure.target.clone()) }
    pub fn fail(&mut self, request: &EditorWrite, error: String) {
        self.failures.insert(request.key.clone(), EditorFailure {
            target: EditorConfirmation { key: request.key.clone(), editor: request.editor, sequence: request.sequence },
            message: error,
        });
    }
    pub fn clear_failure(&mut self, key: &EditorKey) { self.failures.remove(key); }

    pub fn schedule_auto(&mut self, key: EditorKey, editor: EntityId) -> EditorAutosave {
        self.sequence = self.sequence.wrapping_add(1);
        self.autosaves.insert(key.clone(), self.sequence);
        EditorAutosave { key, editor, sequence: self.sequence }
    }

    pub fn take_auto(&mut self, request: &EditorAutosave) -> bool {
        if self.autosaves.get(&request.key) != Some(&request.sequence) { return false; }
        self.autosaves.remove(&request.key);
        true
    }

    pub fn cancel_auto(&mut self, key: &EditorKey) { self.autosaves.remove(key); }

    pub fn retain_live_tabs(&mut self, tabs: &[WorkspaceTab]) {
        let live = tabs.iter().filter_map(|tab| {
            let path = tab.payload.get("filePath")?.as_str()?;
            Some(EditorKey { workspace: tab.workspace_id.clone(), path: path.to_owned() })
        }).collect::<BTreeSet<_>>();
        self.failures.retain(|key, _| live.contains(key));
        self.autosaves.retain(|key, _| live.contains(key));
        // A closed tab does not cancel an already dispatched disk write. Keep
        // its lease until completion so reopening cannot start a racing write.
    }
}
