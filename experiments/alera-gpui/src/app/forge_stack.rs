use std::collections::{BTreeMap, BTreeSet};

use gpui::{Context, Window};

use super::forge_surface::resolve_forge_identity;
use super::AleraApp;
use crate::forge_service::{ForgeStackAction, MergeMethod};

#[derive(Clone)]
pub(super) struct StackWorkspaceCandidate {
    pub(super) id: String,
    pub(super) name: String,
    pub(super) branch: String,
    pub(super) depth: usize,
}

impl AleraApp {
    pub(super) fn begin_forge_stack_link(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let current = self
            .forge_snapshot
            .review
            .as_ref()
            .map(|review| review.number.to_string())
            .unwrap_or_default();
        self.forge_link_input
            .update(cx, |input, cx| input.set_value(current, window, cx));
        self.forge_stack_editing = true;
        self.forge_stack_workspace_editing = false;
        self.forge_form_error = None;
        cx.notify();
    }

    pub(super) fn begin_forge_stack_workspace_link(&mut self, cx: &mut Context<Self>) {
        self.forge_stack_selected_workspace_ids = self
            .forge_stack_workspace_candidates()
            .into_iter()
            .map(|workspace| workspace.id)
            .collect();
        self.forge_stack_workspace_editing = true;
        self.forge_stack_editing = false;
        self.forge_form_error = None;
        cx.notify();
    }

    pub(super) fn close_forge_stack_editor(&mut self, cx: &mut Context<Self>) {
        self.forge_stack_editing = false;
        self.forge_stack_workspace_editing = false;
        self.forge_form_error = None;
        cx.notify();
    }

    pub(super) fn toggle_forge_stack_workspace(
        &mut self,
        workspace_id: String,
        cx: &mut Context<Self>,
    ) {
        if !self
            .forge_stack_selected_workspace_ids
            .remove(&workspace_id)
        {
            self.forge_stack_selected_workspace_ids
                .insert(workspace_id);
        }
        cx.notify();
    }

    pub(super) fn submit_forge_stack_link(&mut self, cx: &mut Context<Self>) {
        let mut review_numbers = parse_stack_review_numbers(
            self.forge_link_input.read(cx).value().as_ref(),
        );
        let stack_number = self.forge_snapshot.stack.as_ref().map(|stack| stack.number);
        if stack_number.is_none() {
            if let Some(current) = self.forge_snapshot.review.as_ref().map(|review| review.number) {
                if !review_numbers.contains(&current) {
                    review_numbers.insert(0, current);
                }
            }
        }
        self.run_forge_stack_action(
            ForgeStackAction::Link {
                review_numbers,
                stack_number,
                base: self.forge_stack_base_branch(),
            },
            cx,
        );
    }

    pub(super) fn submit_forge_stack_workspaces(&mut self, cx: &mut Context<Self>) {
        let branches = self
            .forge_stack_workspace_candidates()
            .into_iter()
            .filter(|workspace| {
                self.forge_stack_selected_workspace_ids
                    .contains(&workspace.id)
            })
            .map(|workspace| workspace.branch)
            .collect::<Vec<_>>();
        self.run_forge_stack_action(
            ForgeStackAction::LinkBranches {
                branches,
                stack_number: self.forge_snapshot.stack.as_ref().map(|stack| stack.number),
                base: self.forge_stack_base_branch(),
            },
            cx,
        );
    }

    pub(super) fn merge_forge_stack(
        &mut self,
        review_number: u64,
        method: MergeMethod,
        cx: &mut Context<Self>,
    ) {
        self.run_forge_stack_action(
            ForgeStackAction::Merge {
                review_number,
                method,
            },
            cx,
        );
    }

    fn run_forge_stack_action(&mut self, action: ForgeStackAction, cx: &mut Context<Self>) {
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
        self.forge_generation = self.forge_generation.wrapping_add(1);
        let generation = self.forge_generation;
        self.forge_busy = true;
        self.forge_error = None;
        let bridge = self.bridge.clone();
        let workspace_service = self.workspace_service.clone();
        let service = self.forge_service.clone();
        cx.spawn(async move |this, cx| {
            let identity = resolve_forge_identity(
                &bridge,
                &workspace_service,
                &workspace_id,
                &workspace_path,
                project_id.as_deref(),
            )
            .await
            .map_err(|reason| format!("Stacked Pull Requests Are Unavailable: {reason:?}"));
            let result = match identity {
                Ok(identity) => service
                    .stack_action(workspace_path, identity, action)
                    .await,
                Err(error) => Err(error),
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if this.forge_generation != generation {
                    return;
                }
                this.forge_busy = false;
                match result {
                    Ok(message) => {
                        this.forge_stack_editing = false;
                        this.forge_stack_workspace_editing = false;
                        this.forge_form_error = None;
                        this.local_message = Some(message.into());
                        this.refresh_forge(cx);
                    }
                    Err(error) => {
                        this.forge_form_error = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
        cx.notify();
    }

    fn forge_stack_base_branch(&self) -> Option<String> {
        self.forge_snapshot
            .stack
            .as_ref()
            .map(|stack| stack.base_branch.trim())
            .filter(|branch| !branch.is_empty())
            .map(str::to_string)
            .or_else(|| {
                self.forge_snapshot
                    .review
                    .as_ref()
                    .map(|review| review.base_branch.trim())
                    .filter(|branch| !branch.is_empty())
                    .map(str::to_string)
            })
    }

    pub(super) fn forge_stack_workspace_candidates(&self) -> Vec<StackWorkspaceCandidate> {
        let Some(selected_id) = self.selected_workspace_id.as_deref() else {
            return Vec::new();
        };
        let Some(project) = self.snapshot.project_for_workspace(selected_id) else {
            return Vec::new();
        };
        let parent_by_child = self
            .snapshot
            .relations
            .iter()
            .map(|relation| {
                (
                    relation.child_workspace_id.as_str(),
                    relation.parent_workspace_id.as_str(),
                )
            })
            .collect::<BTreeMap<_, _>>();
        let mut candidates = project
            .workspaces
            .iter()
            .filter_map(|workspace| {
                let branch = workspace.branch.as_deref()?.trim();
                (!branch.is_empty() && workspace.kind != "main").then(|| StackWorkspaceCandidate {
                    id: workspace.id.clone(),
                    name: workspace.name.clone(),
                    branch: branch.to_string(),
                    depth: workspace_relation_depth(&workspace.id, &parent_by_child),
                })
            })
            .collect::<Vec<_>>();
        candidates.sort_by(|left, right| {
            left.depth
                .cmp(&right.depth)
                .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
                .then_with(|| left.id.cmp(&right.id))
        });
        candidates
    }
}

fn parse_stack_review_numbers(value: &str) -> Vec<u64> {
    value
        .split(|character: char| character == ',' || character.is_whitespace())
        .filter_map(|part| part.trim().trim_start_matches('#').parse().ok())
        .filter(|number| *number > 0)
        .fold(Vec::new(), |mut numbers, number| {
            if !numbers.contains(&number) {
                numbers.push(number);
            }
            numbers
        })
}

fn workspace_relation_depth(id: &str, parent_by_child: &BTreeMap<&str, &str>) -> usize {
    let mut current = id;
    let mut visited = BTreeSet::new();
    let mut depth = 0;
    while let Some(parent) = parent_by_child.get(current).copied() {
        if !visited.insert(current) {
            break;
        }
        depth += 1;
        current = parent;
    }
    depth
}

#[cfg(test)]
mod tests {
    use super::parse_stack_review_numbers;

    #[test]
    fn stack_review_numbers_accept_hashes_commas_and_whitespace() {
        assert_eq!(
            parse_stack_review_numbers("#12, 13\n12 #14 invalid"),
            vec![12, 13, 14]
        );
    }
}

