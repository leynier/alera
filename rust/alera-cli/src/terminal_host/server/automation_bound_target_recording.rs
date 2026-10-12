//! Records where a reusing automation's dispatched run went: binding a new
//! target, touching the current one, following a relaunched tab, and
//! releasing a tab the automation must not paste into again.

use alera_core::runtime::{
    AutomationBoundTarget, AutomationDefinition, AutomationReusePolicy, AutomationRun,
    WorkspaceTabRecord,
};
use chrono::Utc;

use super::automation_bound_target_resolution::BoundTargetPlan;
use super::terminal_startup_commands::agent_profile_id;
use super::ServerActor;

impl ServerActor {
    /// Binds or touches the target a dispatched run reached.
    pub(super) async fn record_bound_target(
        &mut self,
        definition: &AutomationDefinition,
        run: &AutomationRun,
        plan: &BoundTargetPlan,
    ) {
        if !definition.reuse_policy.reuses() {
            return;
        }
        let reason = match plan {
            BoundTargetPlan::CreateNew => Some("created"),
            BoundTargetPlan::Recreate { reason } => Some(*reason),
            BoundTargetPlan::RelaunchConversation { .. } => Some("relaunched"),
            BoundTargetPlan::NewTabInWorkspace {
                rebind_tab: true, ..
            } => Some("rebound"),
            _ => None,
        };
        let changed = match reason {
            Some(reason) => self.bind_run_target(definition, run, reason).await,
            None => self
                .runtime_store
                .touch_automation_bound_target(&definition.id, &run.id, Utc::now())
                .await
                .unwrap_or(false),
        };
        if changed {
            self.broadcast_automation_changed(Some(&definition.id));
        }
    }

    async fn bind_run_target(
        &self,
        definition: &AutomationDefinition,
        run: &AutomationRun,
        reason: &str,
    ) -> bool {
        let Some(workspace_id) = run.workspace_id.clone() else {
            return false;
        };
        let tab = match run.tab_id.as_deref() {
            Some(id) => self
                .runtime_store
                .find_workspace_tab(id)
                .await
                .ok()
                .flatten(),
            None => None,
        };
        let conversation = definition.reuse_policy == AutomationReusePolicy::ReuseConversation;
        let now = Utc::now();
        let binding = AutomationBoundTarget {
            workspace_id,
            tab_id: tab
                .as_ref()
                .filter(|_| conversation)
                .map(|tab| tab.id.clone()),
            conversation_id: tab
                .as_ref()
                .filter(|_| conversation)
                .and_then(|tab| tab.payload["conversationId"].as_str())
                .map(str::to_string),
            agent_profile_id: tab
                .as_ref()
                .and_then(agent_profile_id)
                .map(str::to_string)
                .or_else(|| definition.target.agent_profile_id().map(str::to_string)),
            bound_run_id: run.id.clone(),
            bound_at: now,
            last_run_id: Some(run.id.clone()),
            last_verified_at: Some(now),
        };
        self.runtime_store
            .bind_automation_target(&definition.id, &binding, reason)
            .await
            .unwrap_or(false)
    }

    /// Moves a binding from a tab recovery replaced to its copy.
    pub(super) async fn rebind_relaunched_tab(
        &self,
        automation_id: &str,
        old_tab_id: &str,
        clone: &WorkspaceTabRecord,
        run_id: &str,
    ) {
        let Some(mut binding) = self
            .runtime_store
            .find_automation(automation_id)
            .await
            .ok()
            .flatten()
            .and_then(|definition| definition.bound_target)
            .filter(|binding| binding.tab_id.as_deref() == Some(old_tab_id))
        else {
            return;
        };
        binding.tab_id = Some(clone.id.clone());
        binding.conversation_id = clone.payload["conversationId"].as_str().map(str::to_string);
        binding.last_run_id = Some(run_id.to_string());
        binding.last_verified_at = Some(Utc::now());
        if self
            .runtime_store
            .bind_automation_target(automation_id, &binding, "recovered")
            .await
            .unwrap_or(false)
        {
            self.broadcast_automation_changed(Some(automation_id));
        }
    }

    /// Takeover, timeout and cancellation end a run in a conversation the
    /// automation must not paste into again, so the binding keeps only the
    /// workspace when that run's tab is the bound one.
    pub(super) async fn release_bound_tab_for_run(&self, run: &AutomationRun, reason: &str) {
        let Some(tab_id) = run.tab_id.as_deref() else {
            return;
        };
        let bound = self
            .runtime_store
            .find_automation(&run.automation_id)
            .await
            .ok()
            .flatten()
            .and_then(|definition| definition.bound_target)
            .is_some_and(|binding| binding.tab_id.as_deref() == Some(tab_id));
        if bound
            && self
                .runtime_store
                .release_automation_bound_tab(&run.automation_id, reason)
                .await
                .unwrap_or(false)
        {
            self.broadcast_automation_changed(Some(&run.automation_id));
        }
    }
}
