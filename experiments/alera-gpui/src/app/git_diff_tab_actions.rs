use std::path::Path;

use gpui::Context;
use serde_json::json;

use super::AleraApp;

impl AleraApp {
    pub(super) fn open_git_commit_diff_tab(
        &mut self,
        relative_path: Option<String>,
        old_path: Option<String>,
        scope: &'static str,
        commit_id: String,
        subject: String,
        cx: &mut Context<Self>,
    ) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(source_scope) = self.selected_source_control_scope() else {
            return;
        };
        let source_relative_path = relative_path;
        let source_old_path = old_path;
        let workspace_relative_path = source_relative_path
            .as_deref()
            .and_then(|path| source_scope.to_workspace_relative_path(path));
        let workspace_old_path = source_old_path
            .as_deref()
            .and_then(|path| source_scope.to_workspace_relative_path(path));
        let source_root = source_scope.relative_root.clone();
        if let Some(tab) = self.snapshot.tabs.iter().find(|tab| {
            tab.kind == "gitDiff"
                && tab
                    .payload
                    .get("gitDiffSource")
                    .and_then(serde_json::Value::as_str)
                    == Some("commit")
                && tab
                    .payload
                    .get("gitDiffCommitOid")
                    .and_then(serde_json::Value::as_str)
                    == Some(commit_id.as_str())
                && tab.payload.get("filePath").and_then(|value| value.as_str())
                    == workspace_relative_path.as_deref()
                && tab
                    .payload
                    .get("gitDiffRoot")
                    .and_then(|value| value.as_str())
                    == source_root.as_deref()
        }) {
            self.activate_workspace_tab(tab.id.clone(), cx);
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let workspace_path = source_scope.path;
        let timestamp = chrono::Utc::now();
        let tab_id = format!(
            "gpui-commit-diff-{}-{}",
            std::process::id(),
            timestamp.timestamp_millis()
        );
        let compare_ref = commit_id.chars().take(7).collect::<String>();
        let title = match &source_relative_path {
            Some(path) => format!(
                "{} {compare_ref}",
                Path::new(path)
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or(path)
            ),
            None => format!("Commit {compare_ref}"),
        };
        let payload = json!({
            "gitDiffScope": scope,
            "gitDiffSource": "commit",
            "gitDiffCommitOid": commit_id,
            "gitDiffCompareRef": compare_ref,
            "gitDiffCommitSubject": subject,
            "filePath": workspace_relative_path,
            "gitDiffOldPath": workspace_old_path,
            "gitDiffRoot": source_root,
        });
        let bridge = self.bridge.clone();
        let service = self.workspace_service.clone();
        let mut layout = self.snapshot.layout.clone();
        if let Some(layout) = layout.as_mut() {
            layout.add_tab_to_active_group(tab_id.clone());
        }
        self.tab_mutation_busy = true;
        self.git_diff_loading_tab = Some(tab_id.clone());
        self.git_diff_errors.remove(&tab_id);
        let preload_payload = payload.clone();
        let result_tab_id = tab_id.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "tab.upsert",
                    json!({
                        "id": tab_id,
                        "workspaceId": workspace_id,
                        "kind": "gitDiff",
                        "title": title,
                        "createdAt": timestamp.to_rfc3339(),
                        "updatedAt": timestamp.to_rfc3339(),
                        "payload": payload,
                    }),
                )
                .await;
            let result = match result {
                Ok(tab) => super::tab_actions::persist_layout(&bridge, layout)
                    .await
                    .map(|_| tab),
                Err(error) => Err(error),
            };
            let diff = if result.is_ok() {
                service
                    .git_diff(
                        workspace_path,
                        source_relative_path,
                        None,
                        Some(commit_id),
                        None,
                        source_old_path,
                    )
                    .await
            } else {
                Err("Commit Diff Tab Could Not Be Created.".to_owned())
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                this.git_diff_loading_tab = None;
                match (result, diff) {
                    (Ok(_), Ok(diff)) => {
                        this.selected_tab_id = Some(result_tab_id.clone());
                        let diff_for_images = diff.clone();
                        this.git_diff = diff;
                        this.git_diff_loaded_tab = Some(result_tab_id.clone());
                        this.preload_git_diff_images(
                            result_tab_id.clone(),
                            preload_payload.clone(),
                            &diff_for_images,
                            cx,
                        );
                        this.refresh(cx);
                    }
                    (Err(error), _) | (_, Err(error)) => {
                        this.git_diff_errors
                            .insert(result_tab_id.clone(), "Could not load diff.".into());
                        let _ = error;
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn preload_git_diff_images(
        &mut self,
        tab_id: String,
        payload: serde_json::Value,
        diff: &crate::workspace_git::GitDiffResult,
        cx: &mut Context<Self>,
    ) {
        let source_root = payload
            .get("gitDiffRoot")
            .and_then(serde_json::Value::as_str);
        let Some(source_scope) = self.source_control_scope_for_root(source_root) else {
            return;
        };
        let area = payload
            .get("gitDiffArea")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let commit_id = payload
            .get("gitDiffCommitOid")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let parent_id = payload
            .get("gitDiffParentOid")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        for file in diff
            .files
            .iter()
            .filter(|file| file.is_binary && super::git_diff_surface::is_image_path(&file.path))
        {
            let key = (tab_id.clone(), file.path.clone());
            if self.git_diff_image_sides.contains_key(&key)
                || !self.git_diff_image_loading.insert(key.clone())
            {
                continue;
            }
            let service = self.workspace_service.clone();
            let workspace_path = source_scope.path.clone();
            let file_path = file.path.clone();
            let old_path = file.old_path.clone();
            // An "all changes" tab omits gitDiffArea, but each diff file still
            // carries the area needed to read its index/worktree blob. Commit
            // diffs intentionally keep area absent so the commit tree path is
            // used by the native API.
            let area = area.clone().or_else(|| {
                commit_id.is_none().then_some(file.area.clone())
            });
            let commit_id = commit_id.clone();
            let parent_id = parent_id.clone();
            cx.spawn(async move |this, cx| {
                let old = service
                    .git_diff_blob(
                        workspace_path.clone(),
                        file_path.clone(),
                        old_path.clone(),
                        area.clone(),
                        commit_id.clone(),
                        parent_id.clone(),
                        true,
                    )
                    .await
                    .ok()
                    .flatten()
                    .and_then(super::git_diff_surface::to_git_diff_image_side);
                let new = service
                    .git_diff_blob(
                        workspace_path,
                        file_path,
                        old_path,
                        area,
                        commit_id,
                        parent_id,
                        false,
                    )
                    .await
                    .ok()
                    .flatten()
                    .and_then(super::git_diff_surface::to_git_diff_image_side);
                let _ = this.update(cx, |this, cx| {
                    this.git_diff_image_loading.remove(&key);
                    this.git_diff_image_sides.insert(
                        key,
                        super::git_diff_surface::GitDiffImageSides { old, new },
                    );
                    cx.notify();
                });
            })
            .detach();
        }
    }
}
