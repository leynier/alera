//! Carries out the plans of `automation_bound_target_resolution`: pasting
//! into the bound conversation, relaunching it, opening a tab in the bound
//! workspace, and parking a run while its conversation is busy.

use alera_core::runtime::{
    busy_target_decision, AutomationDefinition, AutomationOverlapDecision, AutomationRecovery,
    AutomationRun, AutomationRunReuse, AutomationRunStatus, AutomationTarget,
    AutomationTargetIdentity, Workspace, WorkspaceTabRecord, AUTOMATION_MAX_RENDERED_PROMPT_BYTES,
};
use chrono::{Duration, Utc};
use serde_json::json;
use std::future::Future;
use std::pin::Pin;

use super::automation_bound_target_resolution::BoundTargetPlan;
use super::automation_tab_relaunch::AutomationTabRelaunch;
use super::terminal_startup_commands::agent_profile_id;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) const BOUND_TARGET_BUSY_REASON: &str =
    "bound conversation stayed busy past the misfire grace window";
const PARK_RETRY_SECONDS: i64 = 5;
const MINIMUM_BUSY_GRACE_SECONDS: i64 = 60;
const PREFACE_FIELD_BYTES: usize = 512;

impl ServerActor {
    /// Keeps a run whose bound target is busy pending without spending an
    /// attempt. Past the misfire grace window the overlap policy decides:
    /// the run is skipped, or under force-parallel opens a new tab in the
    /// bound workspace without moving the binding. Returns the plan to
    /// continue with, or `None` when the run stops here.
    pub(super) async fn park_for_bound_target(
        &mut self,
        definition: &AutomationDefinition,
        run: &mut AutomationRun,
        code: &'static str,
    ) -> Option<BoundTargetPlan> {
        let grace = Duration::seconds(
            definition
                .misfire_grace_seconds
                .max(MINIMUM_BUSY_GRACE_SECONDS),
        );
        let now = Utc::now();
        if now > run.scheduled_at + grace {
            let policy = run.overlap_policy.unwrap_or(definition.overlap_policy);
            if busy_target_decision(policy) == AutomationOverlapDecision::Proceed {
                if let Some(plan) = self.bound_workspace_fallback(definition).await {
                    return Some(plan);
                }
            }
            let _ = self
                .set_automation_run_status(
                    &run.id,
                    AutomationRunStatus::OverlapSkipped,
                    Some(BOUND_TARGET_BUSY_REASON.to_string()),
                )
                .await;
            return None;
        }
        run.status = AutomationRunStatus::Pending;
        run.retry_after = Some(now + Duration::seconds(PARK_RETRY_SECONDS));
        run.started_at = None;
        run.precheck = Some(false);
        run.recovery = Some(AutomationRecovery {
            status: "waiting".into(),
            attempt: run.attempt_count,
            max_attempts: definition.retry_max_attempts,
            interrupted_at: None,
            code: Some(code.into()),
        });
        run.updated_at = now;
        match self.runtime_store.save_automation_run(run).await {
            Ok(saved) => self.broadcast_automation_run_changed(&saved),
            Err(error) => {
                tracing::warn!(run_id = %run.id, "could not park automation run: {error}");
            }
        }
        None
    }

    async fn bound_workspace_fallback(
        &self,
        definition: &AutomationDefinition,
    ) -> Option<BoundTargetPlan> {
        if !definition.reuse_policy.reuses() {
            return None;
        }
        let binding = self
            .runtime_store
            .find_automation(&definition.id)
            .await
            .ok()
            .flatten()?
            .bound_target?;
        let workspace = self
            .runtime_store
            .find_workspace(&binding.workspace_id)
            .await
            .ok()
            .flatten()?;
        let profile_id = binding
            .agent_profile_id
            .or_else(|| definition.target.agent_profile_id().map(str::to_string))?;
        Some(BoundTargetPlan::NewTabInWorkspace {
            workspace,
            profile_id,
            rebind_tab: false,
        })
    }

    /// Writes the prompt into the bound conversation and points the tab at
    /// this run, so observation, takeover and recovery find it.
    pub(super) async fn paste_into_bound_conversation(
        &mut self,
        run: &mut AutomationRun,
        tab: &WorkspaceTabRecord,
        session_id: &str,
        prompt: &str,
    ) -> HostResult<()> {
        let mut record = tab.clone();
        record.payload["automationRunId"] = json!(run.id);
        record.payload["automationAttemptId"] = json!(run.attempt_id);
        record.updated_at = Utc::now();
        self.runtime_store
            .upsert_workspace_tab(record)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.queue_orchestration_paste(session_id, prompt, Vec::new(), true)?;
        run.workspace_id = Some(tab.workspace_id.clone());
        run.tab_id = Some(tab.id.clone());
        run.session_id = Some(session_id.to_string());
        run.owned_tab = tab.payload["automationOwned"] == true;
        run.target_identity = Some(AutomationTargetIdentity {
            workspace_id: Some(tab.workspace_id.clone()),
            tab_id: Some(tab.id.clone()),
            session_id: Some(session_id.to_string()),
            profile_id: agent_profile_id(tab).map(str::to_string),
            conversation_id: tab.payload["conversationId"].as_str().map(str::to_string),
            terminal_handle: Some(session_id.to_string()),
        });
        let _ = self
            .runtime_store
            .bind_automation_attempt(run, "reusePaste")
            .await;
        Ok(())
    }

    /// Relaunches the bound conversation in a new tab of the same workspace.
    /// An automation-owned tab is closed first; a person's tab stays.
    pub(super) async fn relaunch_bound_conversation(
        &mut self,
        run: &mut AutomationRun,
        tab: &WorkspaceTabRecord,
        native_session_id: Option<String>,
        prompt: &str,
    ) -> HostResult<()> {
        if tab.payload["automationOwned"] == true {
            self.terminate_sessions_for_tab(&tab.id).await;
            self.runtime_store
                .remove_workspace_tab(&tab.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            self.broadcast_workspace_tabs_changed(Some(&tab.workspace_id));
        }
        self.relaunch_automation_tab(
            tab,
            run,
            AutomationTabRelaunch {
                prompt,
                native_session_id,
                launch_kind: "reuseRelaunch",
            },
        )
        .await?;
        Ok(())
    }

    /// Prepends what a reused target needs to know about the previous run.
    /// Only a finished previous run is described, and the preface is dropped
    /// rather than pushing the prompt past its size limit.
    pub(super) async fn reuse_prompt_preface(
        &self,
        definition: &AutomationDefinition,
        run: &AutomationRun,
        plan: &BoundTargetPlan,
        rendered: String,
    ) -> String {
        let place = match plan {
            BoundTargetPlan::PasteIntoConversation { .. }
            | BoundTargetPlan::RelaunchConversation { .. } => "the conversation",
            BoundTargetPlan::NewTabInWorkspace { .. } => "the workspace",
            _ => return rendered,
        };
        if !definition.reuse_policy.reuses() {
            return rendered;
        }
        let previous_id = self
            .runtime_store
            .find_automation(&definition.id)
            .await
            .ok()
            .flatten()
            .and_then(|current| current.bound_target)
            .and_then(|binding| binding.last_run_id);
        let Some(previous) = previous_id else {
            return rendered;
        };
        let Some(previous) = self
            .runtime_store
            .find_automation_run(&previous)
            .await
            .ok()
            .flatten()
            .filter(|previous| previous.status.is_final() && previous.id != run.id)
        else {
            return rendered;
        };
        let summary = bounded(previous.summary.as_deref().unwrap_or("No summary recorded"));
        let error = bounded(previous.error.as_deref().unwrap_or("None"));
        let preface = format!(
            "This is run #{} of automation \"{}\", delivered to {place} it used before. Previous run summary: {summary}. Previous error: {error}. Continue in this workspace and inspect its current state before repeating actions.",
            run.number, definition.name,
        );
        if preface.len() + 2 + rendered.len() > AUTOMATION_MAX_RENDERED_PROMPT_BYTES {
            return rendered;
        }
        format!("{preface}\n\n{rendered}")
    }
}

// Each `*_task` builds its future inside a plain function and returns it
// boxed. The dispatch chain is deep, and an unoptimized build keeps every
// future it constructs in the caller's poll frame, so building them here
// keeps the actor's stack within the default thread size.
impl ServerActor {
    pub(super) fn plan_bound_target_task<'a>(
        &'a self,
        definition: &'a AutomationDefinition,
        run: &'a AutomationRun,
    ) -> Pin<Box<impl Future<Output = HostResult<BoundTargetPlan>> + 'a>> {
        Box::pin(self.plan_bound_target(definition, run))
    }

    pub(super) fn park_task<'a>(
        &'a mut self,
        definition: &'a AutomationDefinition,
        run: &'a mut AutomationRun,
        code: &'static str,
    ) -> Pin<Box<impl Future<Output = Option<BoundTargetPlan>> + 'a>> {
        Box::pin(self.park_for_bound_target(definition, run, code))
    }

    pub(super) fn reuse_preface_task<'a>(
        &'a self,
        definition: &'a AutomationDefinition,
        run: &'a AutomationRun,
        plan: &'a BoundTargetPlan,
        rendered: String,
    ) -> Pin<Box<impl Future<Output = String> + 'a>> {
        Box::pin(self.reuse_prompt_preface(definition, run, plan, rendered))
    }

    pub(super) fn record_bound_target_task<'a>(
        &'a mut self,
        definition: &'a AutomationDefinition,
        run: &'a AutomationRun,
        plan: &'a BoundTargetPlan,
    ) -> Pin<Box<impl Future<Output = ()> + 'a>> {
        Box::pin(self.record_bound_target(definition, run, plan))
    }

    pub(super) fn dispatch_plan_task<'a>(
        &'a mut self,
        definition: &'a AutomationDefinition,
        run: &'a mut AutomationRun,
        plan: &'a BoundTargetPlan,
        source_workspace: &'a Workspace,
        prompt: &'a str,
    ) -> Pin<Box<impl Future<Output = HostResult<()>> + 'a>> {
        Box::pin(self.dispatch_bound_plan(definition, run, plan, source_workspace, prompt))
    }

    async fn dispatch_bound_plan(
        &mut self,
        definition: &AutomationDefinition,
        run: &mut AutomationRun,
        plan: &BoundTargetPlan,
        source_workspace: &Workspace,
        prompt: &str,
    ) -> HostResult<()> {
        match plan {
            BoundTargetPlan::PasteIntoConversation {
                tab, session_id, ..
            } => Box::pin(self.paste_into_bound_conversation(run, tab, session_id, prompt)).await,
            BoundTargetPlan::RelaunchConversation {
                tab,
                native_session_id,
                ..
            } => {
                Box::pin(self.relaunch_bound_conversation(
                    run,
                    tab,
                    native_session_id.clone(),
                    prompt,
                ))
                .await
            }
            BoundTargetPlan::NewTabInWorkspace {
                workspace,
                profile_id,
                ..
            } => {
                Box::pin(self.dispatch_fresh_tab(run, &workspace.id, profile_id, prompt, false))
                    .await
            }
            BoundTargetPlan::Busy { .. } => {
                Err(HostError::state("automation bound target is busy"))
            }
            BoundTargetPlan::CreateNew | BoundTargetPlan::Recreate { .. } => {
                // The target's own workspace, or the one prepared for it.
                let (workspace_id, profile_id, owned_workspace) = match &definition.target {
                    AutomationTarget::FreshTab {
                        workspace_id,
                        agent_profile_id,
                    } => (workspace_id.as_str(), agent_profile_id, false),
                    AutomationTarget::ProjectCheckout {
                        agent_profile_id, ..
                    }
                    | AutomationTarget::Worktree {
                        agent_profile_id, ..
                    } => (source_workspace.id.as_str(), agent_profile_id, true),
                    AutomationTarget::ExistingTab { .. } => {
                        return Err(HostError::state("automation existing tab is missing"));
                    }
                };
                Box::pin(self.dispatch_fresh_tab(
                    run,
                    workspace_id,
                    profile_id,
                    prompt,
                    owned_workspace,
                ))
                .await
            }
        }
    }
}

/// How a run under `plan` reaches its target, when the definition reuses.
pub(super) fn run_reuse(
    definition: &AutomationDefinition,
    plan: &BoundTargetPlan,
) -> Option<AutomationRunReuse> {
    if !definition.reuse_policy.reuses() {
        return None;
    }
    Some(match plan {
        BoundTargetPlan::PasteIntoConversation { .. } => AutomationRunReuse::Conversation,
        BoundTargetPlan::RelaunchConversation { .. } => AutomationRunReuse::ResumedConversation,
        BoundTargetPlan::NewTabInWorkspace { .. } => AutomationRunReuse::Workspace,
        BoundTargetPlan::CreateNew
        | BoundTargetPlan::Recreate { .. }
        | BoundTargetPlan::Busy { .. } => AutomationRunReuse::Bound,
    })
}

fn bounded(text: &str) -> String {
    if text.len() <= PREFACE_FIELD_BYTES {
        return text.to_string();
    }
    let mut end = PREFACE_FIELD_BYTES - "...".len();
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}...", &text[..end])
}
