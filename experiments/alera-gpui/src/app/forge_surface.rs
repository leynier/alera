use gpui::Context;
use serde_json::json;

use super::AleraApp;
use crate::forge_service::{
    github_identity, unavailable_snapshot, ForgeAction, ForgeIdentity, ForgeUnavailableReason,
};
use crate::workspace_git::GitSnapshot;

impl AleraApp {
    pub(super) fn refresh_forge(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let project_id = self
            .snapshot
            .project_for_workspace(&workspace_id)
            .map(|project| project.id.clone());
        self.forge_generation += 1;
        let generation = self.forge_generation;
        self.forge_busy = true;
        self.forge_error = None;
        let service = self.forge_service.clone();
        let bridge = self.bridge.clone();
        let workspace_service = self.workspace_service.clone();
        cx.spawn(async move |weak, cx| {
            let identity = resolve_forge_identity(
                &bridge,
                &workspace_service,
                &workspace_id,
                &workspace_path,
                project_id.as_deref(),
            )
            .await;
            let result = match identity.as_ref() {
                Ok(identity) => {
                    service
                        .snapshot(workspace_path.clone(), identity.clone(), None, false)
                        .await
                }
                Err(reason) => Ok(unavailable_snapshot(*reason)),
            };
            let Some(entity) = weak.upgrade() else {
                return;
            };
            let _ = entity.update(cx, |this, cx| {
                if generation != this.forge_generation {
                    return;
                }
                this.forge_busy = false;
                match result {
                    Ok(snapshot) => {
                        this.forge_snapshot = snapshot;
                        this.forge_error = None;
                        this.local_message = None;
                    }
                    Err(error) => this.forge_error = Some(error.into()),
                }
                cx.notify();
            });
            let Ok(identity) = identity else {
                return;
            };
            let Ok(value) = bridge
                .request(
                    "linkedReview.find",
                    json!({"workspaceId": workspace_id.clone()}),
                )
                .await
            else {
                return;
            };
            let dismissed = value
                .get("dismissed")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false);
            let number = (!dismissed)
                .then(|| value.get("number").and_then(serde_json::Value::as_u64))
                .flatten();
            if number.is_none() && !dismissed {
                return;
            }
            let linked_result = service
                .snapshot(workspace_path, identity, number, dismissed)
                .await;
            let Some(entity) = weak.upgrade() else {
                return;
            };
            let _ = entity.update(cx, |this, cx| {
                if generation != this.forge_generation {
                    return;
                }
                match linked_result {
                    Ok(snapshot) => {
                        this.forge_snapshot = snapshot;
                        this.forge_error = None;
                    }
                    Err(error) => this.forge_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn run_forge_action(&mut self, action: ForgeAction, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let project_id = self
            .snapshot
            .project_for_workspace(&workspace_id)
            .map(|project| project.id.clone());
        self.forge_generation += 1;
        let generation = self.forge_generation;
        self.forge_busy = true;
        self.forge_error = None;
        self.forge_review_confirmation = None;
        let service = self.forge_service.clone();
        let bridge = self.bridge.clone();
        let workspace_service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let identity = resolve_forge_identity(
                &bridge,
                &workspace_service,
                &workspace_id,
                &workspace_path,
                project_id.as_deref(),
            )
            .await;
            let (result, snapshot) = match identity {
                Ok(identity) => {
                    let result = service
                        .action(workspace_path.clone(), identity.clone(), action)
                        .await;
                    let snapshot = if result.is_ok() {
                        service
                            .snapshot(workspace_path, identity, None, false)
                            .await
                            .ok()
                    } else {
                        None
                    };
                    (result, snapshot)
                }
                Err(reason) => (
                    Err(unavailable_message(reason).to_string()),
                    Some(unavailable_snapshot(reason)),
                ),
            };
            if let Some(review) = snapshot
                .as_ref()
                .and_then(|snapshot| snapshot.review.as_ref())
            {
                let _ = bridge
                    .request(
                        "linkedReview.upsert",
                        json!({
                            "workspaceId": workspace_id,
                            "dismissed": false,
                            "provider": "github",
                            "number": review.number,
                            "url": review.url,
                            "linkedAt": chrono::Utc::now().to_rfc3339(),
                        }),
                    )
                    .await;
            }
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.forge_generation {
                    return;
                }
                this.forge_busy = false;
                match result {
                    Ok(message) => {
                        this.forge_error = None;
                        this.local_message = Some(message.into());
                        if let Some(snapshot) = snapshot {
                            this.forge_snapshot = snapshot;
                        }
                    }
                    Err(error) => this.forge_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn create_review(&mut self, draft: bool, cx: &mut Context<Self>) {
        let title = self.forge_title_input.read(cx).value().trim().to_string();
        let body = self.forge_body_input.read(cx).value().to_string();
        let base = self.forge_base_input.read(cx).value().trim().to_string();
        if title.is_empty() || base.is_empty() {
            self.forge_form_error = Some("Title And Base Branch Are Required".into());
            cx.notify();
            return;
        }
        self.forge_form_error = None;
        self.run_forge_action(
            ForgeAction::Create {
                title,
                body,
                base,
                draft,
            },
            cx,
        );
    }

    pub(super) fn update_review(&mut self, cx: &mut Context<Self>) {
        let Some(review) = self.forge_snapshot.review.as_ref() else {
            return;
        };
        let title = self.forge_title_input.read(cx).value().trim().to_string();
        let body = self.forge_body_input.read(cx).value().to_string();
        let base = self.forge_base_input.read(cx).value().trim().to_string();
        if title.is_empty() || base.is_empty() {
            self.forge_form_error = Some("Title And Base Branch Are Required".into());
            cx.notify();
            return;
        }
        self.forge_form_error = None;
        self.run_forge_action(
            ForgeAction::Update {
                number: review.number,
                title,
                body,
                base,
            },
            cx,
        );
    }
}

async fn resolve_forge_identity(
    bridge: &crate::runtime_bridge::RuntimeBridge,
    workspace_service: &crate::workspace_service::WorkspaceService,
    workspace_id: &str,
    workspace_path: &str,
    project_id: Option<&str>,
) -> Result<ForgeIdentity, ForgeUnavailableReason> {
    let git_snapshot = workspace_service
        .git_snapshot(workspace_path.to_string())
        .await
        .map_err(|_| ForgeUnavailableReason::ProviderNotDetected)?;
    let remote = bridge
        .request(
            "workspace.repositoryWebUrl",
            json!({
                "workspaceId": workspace_id,
                "workspacePath": workspace_path,
            }),
        )
        .await
        .map_err(|_| ForgeUnavailableReason::NoRemote)?
        .get("remoteUrl")
        .and_then(serde_json::Value::as_str)
        .filter(|remote| !remote.trim().is_empty())
        .map(str::to_string)
        .ok_or(ForgeUnavailableReason::NoRemote)?;
    let base_branches = if let Some(project_id) = project_id {
        bridge
            .request("project.branches.list", json!({"projectId": project_id}))
            .await
            .ok()
            .and_then(|value| value.get("branches").cloned())
            .and_then(|value| value.as_array().cloned())
            .map(|branches| {
                let mut branches = branches
                    .into_iter()
                    .filter_map(|branch| branch.as_str().map(short_branch_name))
                    .filter(|branch| !branch.is_empty())
                    .collect::<Vec<_>>();
                branches.sort();
                branches.dedup();
                branches
            })
            .filter(|branches| !branches.is_empty())
            .unwrap_or_else(|| forge_base_branches(&git_snapshot))
    } else {
        forge_base_branches(&git_snapshot)
    };
    github_identity(&remote, git_snapshot.branch.clone(), base_branches)
}

fn short_branch_name(name: &str) -> String {
    let trimmed = name.trim();
    trimmed
        .split_once('/')
        .map_or_else(|| trimmed.to_owned(), |(_, branch)| branch.to_owned())
}

fn forge_base_branches(snapshot: &GitSnapshot) -> Vec<String> {
    let mut branches = snapshot
        .history
        .iter()
        .flat_map(|item| item.references.iter())
        .filter(|item_ref| matches!(item_ref.category.as_str(), "Branches" | "RemoteBranches"))
        .map(|item_ref| {
            if item_ref.category == "RemoteBranches" {
                item_ref
                    .name
                    .split_once('/')
                    .map(|(_, branch)| branch)
                    .unwrap_or(&item_ref.name)
                    .to_string()
            } else {
                item_ref.name.clone()
            }
        })
        .collect::<Vec<_>>();
    branches.push(snapshot.branch.clone());
    branches.sort();
    branches.dedup();
    branches
}

fn unavailable_message(reason: ForgeUnavailableReason) -> &'static str {
    match reason {
        ForgeUnavailableReason::NoRemote => "Repository Has No Git Remote",
        ForgeUnavailableReason::ProviderNotDetected => "Git Provider Could Not Be Detected",
        ForgeUnavailableReason::UnsupportedProvider => "Git Provider Is Not Supported",
    }
}
