use base64::prelude::*;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::time::Duration;

use crate::runtime_bridge::RuntimeBridge;
pub use crate::workspace_git::{GitAction, GitCommitChange, GitDiffResult, GitSnapshot};

#[derive(Clone)]
pub struct WorkspaceService {
    bridge: RuntimeBridge,
}

const GIT_SNAPSHOT_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Clone, Debug)]
pub struct FileEntry {
    pub relative_path: String,
    pub name: String,
    pub is_directory: bool,
    pub is_hidden: bool,
    pub is_symlink: bool,
    pub is_protected: bool,
    pub git_status: Option<String>,
}

#[derive(Clone, Debug, Default)]
pub struct ExplorerGitStatusSnapshot {
    statuses: BTreeMap<String, String>,
}

impl ExplorerGitStatusSnapshot {
    pub fn status_for(&self, relative_path: &str) -> Option<&str> {
        self.statuses.get(relative_path).map(String::as_str)
    }
}

#[derive(Clone, Debug)]
pub struct EditorDocument {
    pub relative_path: String,
    pub raw_content: String,
    pub display_content: String,
    pub content_token: String,
}

#[derive(Clone, Debug)]
pub struct WorkspaceImage {
    pub format: String,
    pub bytes: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct SearchOptions {
    pub workspace_path: String,
    pub query: String,
    pub case_sensitive: bool,
    pub whole_word: bool,
    pub use_regex: bool,
    pub include_pattern: Option<String>,
    pub exclude_pattern: Option<String>,
    pub include_ignored: bool,
}

#[derive(Clone, Debug, Default)]
pub struct SearchResults {
    pub files: Vec<SearchFile>,
    pub total_matches: u32,
    pub truncated: bool,
}

#[derive(Clone, Debug)]
pub struct SearchFile {
    pub relative_path: String,
    pub content_token: String,
    pub matches: Vec<SearchMatch>,
}

#[derive(Clone, Debug)]
pub struct SearchMatch {
    pub id: String,
    pub line: u32,
    pub column: u32,
    pub match_length: u32,
    pub display_column: Option<u32>,
    pub display_match_length: Option<u32>,
    pub line_content: String,
    pub replacement_preview: Option<String>,
}

#[derive(Clone, Debug)]
pub struct ReplaceSummary {
    pub files_changed: u32,
    pub matches_replaced: u32,
    pub conflicts: Vec<String>,
}

impl WorkspaceService {
    pub fn start(bridge: RuntimeBridge) -> Self {
        Self { bridge }
    }

    pub async fn list(
        &self,
        workspace_path: String,
        relative_path: String,
        hide_ignored: bool,
    ) -> Result<Vec<FileEntry>, String> {
        self.bridge
            .request(
                "workspaceFiles.list",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path.clone(),
                    "hideIgnored": hide_ignored,
                }),
            )
            .await
            .and_then(parse_file_entries)
    }

    pub async fn explorer_status_snapshot(
        &self,
        workspace_path: String,
    ) -> Result<ExplorerGitStatusSnapshot, String> {
        let value = self
            .bridge
            .request(
                "workspaceGit.explorerStatus",
                json!({"workspacePath": workspace_path}),
            )
            .await?;
        parse_explorer_git_status_snapshot(value)
    }

    pub async fn read(
        &self,
        workspace_path: String,
        relative_path: String,
    ) -> Result<EditorDocument, String> {
        let value = self
            .bridge
            .request(
                "workspaceFiles.readEditor",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path.clone(),
                    "tabSize": 4,
                }),
            )
            .await?;
        parse_editor_document(value, relative_path)
    }

    pub async fn write(
        &self,
        workspace_path: String,
        document: EditorDocument,
        display_content: String,
        overwrite: bool,
    ) -> Result<EditorDocument, String> {
        let relative_path = document.relative_path.clone();
        let value = self
            .bridge
            .request(
                "workspaceFiles.writeEditor",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path,
                    "currentDisplayContent": display_content,
                    "originalRawContent": document.raw_content,
                    "originalDisplayContent": document.display_content,
                    "expectedContentToken": document.content_token,
                    "overwriteIfChanged": overwrite,
                    "tabSize": 4,
                }),
            )
            .await?;
        parse_editor_document(value, relative_path)
    }

    pub async fn create(
        &self,
        workspace_path: String,
        parent_relative_path: String,
        name: String,
        directory: bool,
    ) -> Result<FileEntry, String> {
        let value = self
            .bridge
            .request(
                if directory {
                    "workspaceFiles.createDirectory"
                } else {
                    "workspaceFiles.createFile"
                },
                json!({
                    "workspacePath": workspace_path,
                    "parentRelativePath": parent_relative_path,
                    "name": name,
                }),
            )
            .await?;
        parse_file_entry(&value)
    }

    pub async fn rename(
        &self,
        workspace_path: String,
        relative_path: String,
        new_name: String,
    ) -> Result<FileEntry, String> {
        let value = self
            .bridge
            .request(
                "workspaceFiles.rename",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path,
                    "newName": new_name,
                }),
            )
            .await?;
        parse_file_entry(&value)
    }

    pub async fn copy(
        &self,
        workspace_path: String,
        relative_path: String,
        target_parent_relative_path: String,
    ) -> Result<FileEntry, String> {
        let value = self
            .bridge
            .request(
                "workspaceFiles.copy",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path,
                    "targetParentRelativePath": target_parent_relative_path,
                }),
            )
            .await?;
        parse_file_entry(&value)
    }

    pub async fn move_entry(
        &self,
        workspace_path: String,
        relative_path: String,
        target_parent_relative_path: String,
    ) -> Result<FileEntry, String> {
        let value = self
            .bridge
            .request(
                "workspaceFiles.move",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path,
                    "targetParentRelativePath": target_parent_relative_path,
                }),
            )
            .await?;
        parse_file_entry(&value)
    }

    pub async fn delete(
        &self,
        workspace_path: String,
        relative_path: String,
    ) -> Result<(), String> {
        self.bridge
            .request(
                "workspaceFiles.delete",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path,
                    "useTrash": true,
                }),
            )
            .await?;
        Ok(())
    }

    pub async fn search(&self, options: SearchOptions) -> Result<SearchResults, String> {
        let value = self
            .bridge
            .request("workspaceSearch.search", search_payload(&options))
            .await?;
        parse_search_results(value)
    }

    pub async fn preview_replace(
        &self,
        options: SearchOptions,
        replacement: String,
        preserve_case: bool,
    ) -> Result<SearchResults, String> {
        let mut payload = search_payload(&options);
        let object = payload
            .as_object_mut()
            .expect("workspace search payload must be an object");
        object.insert("replacement".to_owned(), Value::String(replacement));
        object.insert("preserveCase".to_owned(), Value::Bool(preserve_case));
        let value = self
            .bridge
            .request("workspaceSearch.previewReplace", payload)
            .await?;
        parse_search_results(value)
    }

    pub async fn replace_all(
        &self,
        options: SearchOptions,
        replacement: String,
        preserve_case: bool,
    ) -> Result<ReplaceSummary, String> {
        let mut payload = search_payload(&options);
        payload
            .as_object_mut()
            .expect("workspace search payload must be an object")
            .insert("replacement".to_owned(), Value::String(replacement));
        payload
            .as_object_mut()
            .expect("workspace search payload must be an object")
            .insert("preserveCase".to_owned(), Value::Bool(preserve_case));
        let value = self
            .bridge
            .request("workspaceSearch.replaceAll", payload)
            .await?;
        parse_replace_summary(value)
    }

    pub async fn replace_matches(
        &self,
        options: SearchOptions,
        replacement: String,
        preserve_case: bool,
        match_ids: Vec<String>,
        expected_files: Vec<(String, String)>,
    ) -> Result<ReplaceSummary, String> {
        let mut payload = search_payload(&options);
        let object = payload
            .as_object_mut()
            .expect("workspace search payload must be an object");
        object.insert("replacement".to_owned(), Value::String(replacement));
        object.insert("preserveCase".to_owned(), Value::Bool(preserve_case));
        object.insert(
            "matchIds".to_owned(),
            Value::Array(match_ids.into_iter().map(Value::String).collect()),
        );
        object.insert(
            "expectedFiles".to_owned(),
            Value::Array(
                expected_files
                    .into_iter()
                    .map(|(relative_path, content_token)| {
                        json!({
                            "relativePath": relative_path,
                            "contentToken": content_token,
                        })
                    })
                    .collect(),
            ),
        );
        let value = self
            .bridge
            .request("workspaceSearch.replaceMatches", payload)
            .await?;
        parse_replace_summary(value)
    }

    pub async fn mermaid(
        &self,
        workspace_path: String,
        relative_path: String,
    ) -> Result<String, String> {
        let value = self
            .bridge
            .request(
                "workspacePreview.mermaid",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path,
                }),
            )
            .await?;
        required_string(&value, "svg")
    }

    pub async fn image(
        &self,
        workspace_path: String,
        relative_path: String,
    ) -> Result<WorkspaceImage, String> {
        let value = self
            .bridge
            .request(
                "workspacePreview.image",
                json!({
                    "workspacePath": workspace_path,
                    "relativePath": relative_path,
                }),
            )
            .await?;
        let format = required_string(&value, "format")?;
        let encoded = required_string(&value, "bytesBase64")?;
        let bytes = BASE64_STANDARD
            .decode(encoded)
            .map_err(|error| format!("Workspace Image Response Is Invalid: {error}"))?;
        Ok(WorkspaceImage { format, bytes })
    }

    pub async fn git_snapshot(&self, workspace_path: String) -> Result<GitSnapshot, String> {
        let value = self
            .bridge
            .request_with_timeout(
                "workspaceGit.snapshot",
                json!({ "workspacePath": workspace_path }),
                GIT_SNAPSHOT_TIMEOUT,
            )
            .await?;
        parse_git_snapshot(value)
    }

    pub async fn git_action(
        &self,
        workspace_path: String,
        action: GitAction,
    ) -> Result<String, String> {
        let (action, path, message, index) = match action {
            GitAction::StageAll => ("stageAll", None, None, None),
            GitAction::StagePath(path) => ("stagePath", Some(path), None, None),
            GitAction::UnstageAll => ("unstageAll", None, None, None),
            GitAction::UnstagePath(path) => ("unstagePath", Some(path), None, None),
            GitAction::DiscardAll => ("discardAll", None, None, None),
            GitAction::DiscardPath(path) => ("discardPath", Some(path), None, None),
            GitAction::Commit(message) => ("commit", None, Some(message), None),
            GitAction::Amend(message) => ("amend", None, Some(message), None),
            GitAction::Fetch => ("fetch", None, None, None),
            GitAction::Pull => ("pull", None, None, None),
            GitAction::Push => ("push", None, None, None),
            GitAction::Sync => ("sync", None, None, None),
            GitAction::Stash => ("stash", None, None, None),
            GitAction::StashPop(index) => ("stashPop", None, None, Some(index)),
        };
        let value = self
            .bridge
            .request(
                "workspaceGit.action",
                json!({
                    "workspacePath": workspace_path,
                    "action": action,
                    "path": path,
                    "message": message,
                    "index": index,
                }),
            )
            .await?;
        required_string(&value, "message")
    }

    pub async fn git_commit_compare(
        &self,
        workspace_path: String,
        commit_id: String,
    ) -> Result<Vec<GitCommitChange>, String> {
        let value = self
            .bridge
            .request(
                "workspaceGit.commitCompare",
                json!({
                    "workspacePath": workspace_path,
                    "commitId": commit_id,
                }),
            )
            .await?;
        value
            .get("files")
            .and_then(Value::as_array)
            .ok_or_else(|| "Workspace Git Commit Compare Omitted Files.".to_string())?
            .iter()
            .map(|entry| {
                Ok(GitCommitChange {
                    path: required_string(entry, "path")?,
                    old_path: entry
                        .get("oldPath")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    status: required_string(entry, "status")?,
                    added: entry.get("added").and_then(Value::as_u64).map(|v| v as u32),
                    removed: entry
                        .get("removed")
                        .and_then(Value::as_u64)
                        .map(|v| v as u32),
                })
            })
            .collect()
    }

    pub async fn git_diff(
        &self,
        workspace_path: String,
        file_path: Option<String>,
        area: Option<String>,
        commit_id: Option<String>,
        parent_id: Option<String>,
        old_path: Option<String>,
    ) -> Result<GitDiffResult, String> {
        let value = self
            .bridge
            .request(
                "workspaceGit.diff",
                json!({
                    "workspacePath": workspace_path,
                    "filePath": file_path,
                    "area": area,
                    "commitId": commit_id,
                    "parentId": parent_id,
                    "oldPath": old_path,
                }),
            )
            .await?;
        parse_git_diff(value)
    }

    pub async fn git_diff_blob(
        &self,
        workspace_path: String,
        file_path: String,
        old_path: Option<String>,
        area: Option<String>,
        commit_id: Option<String>,
        parent_id: Option<String>,
        old_side: bool,
    ) -> Result<Option<WorkspaceImage>, String> {
        let value = self
            .bridge
            .request(
                "workspaceGit.diffBlob",
                json!({
                    "workspacePath": workspace_path,
                    "filePath": file_path,
                    "oldPath": old_path,
                    "area": area,
                    "commitId": commit_id,
                    "parentId": parent_id,
                    "oldSide": old_side,
                }),
            )
            .await?;
        let format = required_string(&value, "format")?;
        let Some(encoded) = value.get("bytesBase64").and_then(Value::as_str) else {
            return Ok(None);
        };
        let bytes = BASE64_STANDARD
            .decode(encoded)
            .map_err(|error| format!("Workspace Git Diff Blob Is Invalid: {error}"))?;
        Ok(Some(WorkspaceImage { format, bytes }))
    }
}

pub fn apply_explorer_git_status(
    entries: Vec<FileEntry>,
    snapshot: &ExplorerGitStatusSnapshot,
) -> Vec<FileEntry> {
    entries
        .into_iter()
        .map(|mut entry| {
            if let Some(status) = snapshot.status_for(&entry.relative_path) {
                entry.git_status = Some(status.to_owned());
            }
            entry
        })
        .collect()
}

fn parse_file_entries(value: Value) -> Result<Vec<FileEntry>, String> {
    value
        .as_array()
        .ok_or_else(|| "Workspace File Response Must Be An Array.".to_string())?
        .iter()
        .map(parse_file_entry)
        .collect()
}

fn parse_explorer_git_status_snapshot(value: Value) -> Result<ExplorerGitStatusSnapshot, String> {
    let entries = value
        .get("entries")
        .and_then(Value::as_array)
        .ok_or_else(|| "Workspace Git Explorer Response Omitted Entries.".to_string())?;
    let mut statuses = BTreeMap::new();
    for entry in entries {
        let path = required_string(entry, "path")?;
        let status = match entry
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_ascii_lowercase()
            .as_str()
        {
            "untracked" => "U",
            "added" => "A",
            "modified" => "M",
            _ => continue,
        };
        statuses.insert(path.replace('\\', "/"), status.to_owned());
    }
    Ok(ExplorerGitStatusSnapshot { statuses })
}

fn parse_file_entry(entry: &Value) -> Result<FileEntry, String> {
    Ok(FileEntry {
        relative_path: required_string(entry, "relativePath")?,
        name: required_string(entry, "name")?,
        is_directory: entry.get("kind").and_then(Value::as_str) == Some("directory"),
        is_hidden: entry
            .get("isHidden")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        is_symlink: entry
            .get("isSymlink")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        is_protected: entry
            .get("isProtected")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        git_status: match entry.get("gitStatus").and_then(Value::as_str) {
            Some("untracked") => Some("U".to_owned()),
            Some("added") => Some("A".to_owned()),
            Some("modified") => Some("M".to_owned()),
            _ => None,
        },
    })
}

fn parse_editor_document(value: Value, relative_path: String) -> Result<EditorDocument, String> {
    Ok(EditorDocument {
        relative_path,
        raw_content: required_string(&value, "rawContent")?,
        display_content: required_string(&value, "displayContent")?,
        content_token: required_string(&value, "contentToken")?,
    })
}

fn required_string(value: &Value, key: &str) -> Result<String, String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| format!("Workspace File Response Omitted {key}."))
}

fn search_payload(options: &SearchOptions) -> Value {
    json!({
        "workspacePath": options.workspace_path,
        "query": options.query,
        "caseSensitive": options.case_sensitive,
        "wholeWord": options.whole_word,
        "useRegex": options.use_regex,
        "includePattern": options.include_pattern,
        "excludePattern": options.exclude_pattern,
        "includeIgnored": options.include_ignored,
    })
}

fn parse_search_results(value: Value) -> Result<SearchResults, String> {
    let files = value
        .get("files")
        .and_then(Value::as_array)
        .ok_or_else(|| "Workspace Search Response Omitted Files.".to_string())?
        .iter()
        .map(|file| {
            let matches = file
                .get("matches")
                .and_then(Value::as_array)
                .ok_or_else(|| "Workspace Search File Omitted Matches.".to_string())?
                .iter()
                .map(|item| {
                    Ok(SearchMatch {
                        id: required_string(item, "id")?,
                        line: item.get("line").and_then(Value::as_u64).unwrap_or_default() as u32,
                        column: item
                            .get("column")
                            .and_then(Value::as_u64)
                            .unwrap_or_default() as u32,
                        match_length: item
                            .get("matchLength")
                            .and_then(Value::as_u64)
                            .unwrap_or_default() as u32,
                        display_column: item
                            .get("displayColumn")
                            .and_then(Value::as_u64)
                            .map(|value| value as u32),
                        display_match_length: item
                            .get("displayMatchLength")
                            .and_then(Value::as_u64)
                            .map(|value| value as u32),
                        line_content: required_string(item, "lineContent")?,
                        replacement_preview: item
                            .get("replacementPreview")
                            .and_then(Value::as_str)
                            .map(str::to_owned),
                    })
                })
                .collect::<Result<Vec<_>, String>>()?;
            Ok(SearchFile {
                relative_path: required_string(file, "relativePath")?,
                content_token: required_string(file, "contentToken")?,
                matches,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(SearchResults {
        files,
        total_matches: value
            .get("totalMatches")
            .and_then(Value::as_u64)
            .unwrap_or_default() as u32,
        truncated: value
            .get("truncated")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

fn parse_replace_summary(value: Value) -> Result<ReplaceSummary, String> {
    let conflicts = value
        .get("conflicts")
        .and_then(Value::as_array)
        .ok_or_else(|| "Workspace Replace Response Omitted Conflicts.".to_string())?
        .iter()
        .map(|conflict| {
            Ok(format!(
                "{}: {}",
                required_string(conflict, "relativePath")?,
                required_string(conflict, "reason")?,
            ))
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(ReplaceSummary {
        files_changed: value
            .get("filesChanged")
            .and_then(Value::as_u64)
            .unwrap_or_default() as u32,
        matches_replaced: value
            .get("matchesReplaced")
            .and_then(Value::as_u64)
            .unwrap_or_default() as u32,
        conflicts,
    })
}

fn parse_git_snapshot(value: Value) -> Result<GitSnapshot, String> {
    let branch = required_string(&value, "branch")?;
    let upstream = value
        .get("upstream")
        .and_then(Value::as_str)
        .map(str::to_owned);
    let ahead = value
        .get("ahead")
        .and_then(Value::as_u64)
        .unwrap_or_default() as u32;
    let behind = value
        .get("behind")
        .and_then(Value::as_u64)
        .unwrap_or_default() as u32;
    let changes = value
        .get("changes")
        .and_then(Value::as_array)
        .ok_or_else(|| "Workspace Git Response Omitted Changes.".to_string())?
        .iter()
        .map(|change| {
            Ok(crate::workspace_git::GitChange {
                path: required_string(change, "path")?,
                area: required_string(change, "area")?,
                status: required_string(change, "status")?,
                added: change
                    .get("added")
                    .and_then(Value::as_u64)
                    .map(|v| v as u32),
                removed: change
                    .get("removed")
                    .and_then(Value::as_u64)
                    .map(|v| v as u32),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let history = value
        .get("history")
        .and_then(Value::as_array)
        .ok_or_else(|| "Workspace Git Response Omitted History.".to_string())?
        .iter()
        .map(|item| {
            Ok(crate::workspace_git::GitHistoryItem {
                full_id: item
                    .get("fullId")
                    .and_then(Value::as_str)
                    .or_else(|| item.get("id").and_then(Value::as_str))
                    .map(str::to_owned)
                    .ok_or_else(|| "Workspace Git History Item Omitted Id.".to_string())?,
                id: required_string(item, "id")?,
                parent_ids: item
                    .get("parentIds")
                    .and_then(Value::as_array)
                    .map(|parents| {
                        parents
                            .iter()
                            .filter_map(Value::as_str)
                            .map(str::to_owned)
                            .collect()
                    })
                    .unwrap_or_default(),
                subject: required_string(item, "subject")?,
                message: item
                    .get("message")
                    .and_then(Value::as_str)
                    .unwrap_or_else(|| {
                        item.get("subject")
                            .and_then(Value::as_str)
                            .unwrap_or_default()
                    })
                    .to_owned(),
                author: item
                    .get("author")
                    .and_then(Value::as_str)
                    .map(str::to_owned),
                timestamp_millis: item.get("timestampMillis").and_then(Value::as_i64),
                references: item
                    .get("references")
                    .and_then(Value::as_array)
                    .map(|references| {
                        references
                            .iter()
                            .map(parse_git_history_ref)
                            .collect::<Result<Vec<_>, String>>()
                    })
                    .transpose()?
                    .unwrap_or_default(),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let history_metadata = crate::workspace_git::complete_history_metadata(
        &branch,
        upstream.as_deref(),
        ahead,
        behind,
        &history,
        parse_git_history_metadata(&value)?,
    );
    Ok(GitSnapshot {
        branch,
        upstream,
        ahead,
        behind,
        has_conflicts: value
            .get("hasConflicts")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        head_message: value
            .get("headMessage")
            .and_then(Value::as_str)
            .map(str::to_owned),
        changes,
        history,
        history_metadata,
        stashes: value
            .get("stashes")
            .and_then(Value::as_array)
            .ok_or_else(|| "Workspace Git Response Omitted Stashes.".to_string())?
            .iter()
            .enumerate()
            .map(|(fallback_index, stash)| {
                if let Some(text) = stash.as_str() {
                    return Ok(crate::workspace_git::GitStash {
                        index: fallback_index as u32,
                        reference: format!("stash@{{{fallback_index}}}"),
                        message: text.to_owned(),
                    });
                }
                Ok(crate::workspace_git::GitStash {
                    index: stash
                        .get("index")
                        .and_then(Value::as_u64)
                        .unwrap_or(fallback_index as u64) as u32,
                    reference: required_string(stash, "reference")?,
                    message: required_string(stash, "message")?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?,
    })
}

fn parse_git_history_metadata(
    value: &Value,
) -> Result<crate::workspace_git::GitHistoryMetadata, String> {
    let Some(metadata) = value.get("historyMetadata") else {
        return Ok(crate::workspace_git::GitHistoryMetadata::default());
    };
    Ok(crate::workspace_git::GitHistoryMetadata {
        current_ref: metadata
            .get("currentRef")
            .filter(|value| !value.is_null())
            .map(parse_git_history_ref)
            .transpose()?,
        remote_ref: metadata
            .get("remoteRef")
            .filter(|value| !value.is_null())
            .map(parse_git_history_ref)
            .transpose()?,
        base_ref: metadata
            .get("baseRef")
            .filter(|value| !value.is_null())
            .map(parse_git_history_ref)
            .transpose()?,
        merge_base: metadata
            .get("mergeBase")
            .and_then(Value::as_str)
            .map(str::to_owned),
        has_incoming_changes: metadata
            .get("hasIncomingChanges")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        has_outgoing_changes: metadata
            .get("hasOutgoingChanges")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        has_more: metadata
            .get("hasMore")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        limit: metadata
            .get("limit")
            .and_then(Value::as_u64)
            .unwrap_or_default() as u32,
    })
}

fn parse_git_history_ref(value: &Value) -> Result<crate::workspace_git::GitHistoryRef, String> {
    let name = required_string(value, "name")?;
    Ok(crate::workspace_git::GitHistoryRef {
        id: value
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or(&name)
            .to_owned(),
        name,
        revision: value
            .get("revision")
            .and_then(Value::as_str)
            .map(str::to_owned),
        category: value
            .get("category")
            .and_then(Value::as_str)
            .unwrap_or("Commits")
            .to_owned(),
        color: None,
    })
}

fn parse_git_diff(value: Value) -> Result<GitDiffResult, String> {
    let files = value
        .get("files")
        .and_then(Value::as_array)
        .ok_or_else(|| "Workspace Git Diff Response Omitted Files.".to_string())?
        .iter()
        .map(|file| {
            let lines = file
                .get("lines")
                .and_then(Value::as_array)
                .ok_or_else(|| "Workspace Git Diff File Omitted Lines.".to_string())?
                .iter()
                .map(|line| {
                    Ok(crate::workspace_git::GitDiffLine {
                        text: required_string(line, "text")?,
                        kind: required_string(line, "kind")?,
                    })
                })
                .collect::<Result<Vec<_>, String>>()?;
            Ok(crate::workspace_git::GitDiffFile {
                path: required_string(file, "path")?,
                old_path: file
                    .get("oldPath")
                    .and_then(Value::as_str)
                    .map(str::to_owned),
                area: required_string(file, "area")?,
                status: required_string(file, "status")?,
                lines,
                added: file.get("added").and_then(Value::as_u64).map(|v| v as u32),
                removed: file
                    .get("removed")
                    .and_then(Value::as_u64)
                    .map(|v| v as u32),
                is_binary: file
                    .get("isBinary")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                is_large: file
                    .get("isLarge")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                is_gitlink: file
                    .get("isGitlink")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                truncated: file
                    .get("truncated")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                line_preview_truncated: file
                    .get("linePreviewTruncated")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(GitDiffResult {
        files,
        truncated: value
            .get("truncated")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explorer_git_status_snapshot_applies_ancestor_statuses() {
        let snapshot = parse_explorer_git_status_snapshot(json!({
            "entries": [
                {"path": "src/components/stats/top-languages-stat.astro", "status": "Modified"},
                {"path": "src/components/stats", "status": "Modified"},
                {"path": "src", "status": "Modified"},
            ],
        }))
        .unwrap();
        let entries = apply_explorer_git_status(
            vec![FileEntry {
                relative_path: "src".to_owned(),
                name: "src".to_owned(),
                is_directory: true,
                is_hidden: false,
                is_symlink: false,
                is_protected: false,
                git_status: None,
            }],
            &snapshot,
        );

        assert_eq!(entries[0].git_status.as_deref(), Some("M"));
    }

    #[test]
    fn explorer_git_status_snapshot_normalizes_windows_paths() {
        let snapshot = parse_explorer_git_status_snapshot(json!({
            "entries": [
                {"path": "src\\main.dart", "status": "Untracked"},
            ],
        }))
        .unwrap();

        assert_eq!(snapshot.status_for("src/main.dart"), Some("U"));
    }
}
