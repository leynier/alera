use super::ServerActor;
use crate::process_identity::{ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe};
use alera_core::runtime::{
    AutomationDefinition, AutomationProcessIdentity, AutomationRecovery, AutomationRun,
    AutomationRunStatus, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::{json, Value};

impl ServerActor {
    pub(super) async fn mark_automation_agent_waiting(&mut self, session: &str) {
        for run in self
            .runtime_store
            .list_active_automation_runs()
            .await
            .unwrap_or_default()
        {
            if run.session_id.as_deref() != Some(session)
                || run.status == AutomationRunStatus::WaitingForUser
                || run.taken_over
            {
                continue;
            }
            let actor = alera_core::runtime::AutomationActor {
                kind: alera_core::runtime::AutomationActorKind::ManagedAgent,
                id: run.actor_id.clone(),
                label: Some("Automation agent".into()),
            };
            if let Ok(waiting) = self
                .runtime_store
                .set_automation_run_waiting(&run.id, actor, true)
                .await
            {
                self.automation_run_event(&waiting);
                self.broadcast_authenticated(crate::terminal_host::protocol::event("automationAttentionRequired",json!({"automationId":run.automation_id,"runId":run.id,"reason":"Agent is waiting for input"})));
                if let Some(definition) = run.definition_snapshot.as_ref() {
                    self.queue_automation_push(
                        &waiting,
                        definition,
                        AutomationRunStatus::WaitingForUser,
                        Some("Agent is waiting for input"),
                    )
                    .await;
                }
            }
        }
    }

    async fn automation_workspace_recovery_context(&self, run: &AutomationRun) -> String {
        let Some(id) = run.workspace_id.as_deref() else {
            return "Workspace not recorded".into();
        };
        let Some(workspace) = self.runtime_store.find_workspace(id).await.ok().flatten() else {
            return "Workspace unavailable".into();
        };
        if workspace.host_id != LOCAL_HOST_ID {
            return format!(
                "SSH workspace {} on {}. Reconcile its current Git state before continuing.",
                workspace.path, workspace.host_id
            );
        }
        let path = workspace.path;
        tokio::task::spawn_blocking(move || match alera_core::source_control::git_status(path) {
            Ok(status) => {
                let mut lines = status
                    .entries
                    .iter()
                    .take(100)
                    .map(|entry| {
                        format!(
                            "{:?} {:?} {} (+{}, -{})",
                            entry.area,
                            entry.status,
                            entry.path,
                            entry.added.unwrap_or(0),
                            entry.removed.unwrap_or(0)
                        )
                    })
                    .collect::<Vec<_>>();
                lines.push(format!(
                    "{} changed paths in total; file contents excluded",
                    status.entries.len()
                ));
                alera_core::runtime::redact_known_patterns(&lines.join("\n"))
            }
            Err(_) => "No Git state available; inspect preserved files before continuing".into(),
        })
        .await
        .unwrap_or_else(|_| "Git state inspection was interrupted".into())
    }

    pub(super) async fn record_automation_process(&mut self, run: &AutomationRun) {
        let Some(session_id) = run.session_id.as_deref() else {
            return;
        };
        let Some(session) = self.sessions.get(session_id) else {
            return;
        };
        let Some(pid) = session
            .agent_process_group()
            .or_else(|| session.shell().map(|shell| shell.pid))
        else {
            return;
        };
        let observed = tokio::task::spawn_blocking(move || {
            let boot_id = crate::relocation_setup_process::current_boot_id()
                .ok()
                .flatten();
            match SystemProcessIdentityProbe.lookup(pid) {
                ProcessLookup::Live(identity) => Some(AutomationProcessIdentity {
                    pid,
                    start_marker: identity.start_marker,
                    boot_id,
                }),
                _ => None,
            }
        })
        .await
        .ok()
        .flatten();
        if let Ok(Some(mut current)) = self.runtime_store.find_automation_run(&run.id).await {
            if current.attempt_id == run.attempt_id && !current.status.is_final() {
                current.owner_process = observed;
                let _ = self.runtime_store.save_automation_run(&current).await;
            }
        }
    }

    pub(super) async fn observe_automation_agent(
        &mut self,
        session_id: &str,
        native_id: Option<String>,
        working: bool,
    ) {
        let runs = self
            .runtime_store
            .list_active_automation_runs()
            .await
            .unwrap_or_default();
        for mut run in runs
            .into_iter()
            .filter(|run| run.session_id.as_deref() == Some(session_id))
        {
            if let Some(id) = &native_id {
                run.native_conversation_id = Some(id.clone());
            }
            if working {
                run.last_activity_at = Some(Utc::now());
                if run.status == AutomationRunStatus::WaitingForUser {
                    run.status = AutomationRunStatus::Dispatched;
                }
            }
            let _ = self.runtime_store.save_automation_run(&run).await;
            self.record_automation_process(&run).await;
            self.automation_run_event(&run);
        }
    }

    pub(super) fn automation_run_event(&self, run: &AutomationRun) {
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "automationRunChanged",
            json!({"automationId":run.automation_id,"runId":run.id}),
        ));
    }

    pub(super) async fn resume_interrupted_automation_run(
        &mut self,
        definition: &AutomationDefinition,
        mut run: AutomationRun,
    ) {
        if run.taken_over || run.owner_reserved || run.cancel_requested_at.is_some() {
            return;
        }
        let Some(mut tab) = self.automation_recovery_tab(&run).await else {
            // Never reconstruct a changed legacy target or allocate another worktree.
            self.block_run(&run, "The interrupted run's terminal is missing; choose Run Again to continue its preserved work").await;
            return;
        };
        if let Some(session_id) = run.session_id.as_deref() {
            if self
                .sessions
                .get(session_id)
                .is_some_and(|session| session.running())
            {
                return;
            }
        }
        run.workspace_id = Some(tab.workspace_id.clone());
        run.tab_id = Some(tab.id.clone());
        run.session_id = Some(
            super::requests::terminal_session_id_from_tab(&tab).unwrap_or_else(|| tab.id.clone()),
        );
        let _ = self.runtime_store.save_automation_run(&run).await;
        let mut started = match self
            .runtime_store
            .begin_automation_attempt(&run.id, definition.retry_max_attempts)
            .await
        {
            Ok(started) => started,
            Err(error) => {
                self.fail_run(&run, error.to_string()).await;
                return;
            }
        };
        let native = tab.payload["agentNativeSessionId"]
            .as_str()
            .map(str::to_string)
            .or(run.native_conversation_id.clone());
        let tried_resume = self
            .runtime_store
            .automation_attempts(&run.id)
            .await
            .unwrap_or_default()
            .iter()
            .any(|attempt| attempt.launch_kind.as_deref() == Some("resume"));
        let resuming = native.is_some() && !tried_resume;
        let context = self.automation_workspace_recovery_context(&started).await;
        let prompt = format!(
            "{}\n\nPrevious attempt workspace state:\n{context}",
            automation_recovery_prompt(&started, definition)
        );
        if resuming {
            tab.payload["agentNativeSessionId"] = json!(native);
            let agent = super::terminal_startup_commands::tab_agent_type(&tab)
                .unwrap_or("")
                .to_string();
            tab.payload["pendingAgentPrompt"] = json!({"agent":agent,"prompt":prompt});
        } else {
            tab.payload["agentNativeSessionId"] = Value::Null;
            tab.payload["initialPrompt"] = json!(prompt);
            tab.payload["initialPromptOnce"] = json!(false);
            let agent = super::terminal_startup_commands::tab_agent_type(&tab)
                .unwrap_or("")
                .to_string();
            if super::terminal_startup_commands::initial_delivery_mechanism(&tab).ok().flatten().is_some_and(|m| matches!(m, crate::terminal_host::orchestration::agent_profile_launch_snapshot::AgentInitialDeliveryMechanismV1::TerminalAfterReady)) {
                tab.payload["pendingAgentPrompt"] = json!({"agent":agent,"prompt":prompt});
            }
        }
        tab.id = uuid::Uuid::new_v4().to_string();
        tab.created_at = Utc::now();
        tab.updated_at = tab.created_at;
        tab.payload["terminalSessionId"] = json!(tab.id);
        tab.payload["conversationId"] = json!(uuid::Uuid::new_v4().to_string());
        started.tab_id = Some(tab.id.clone());
        started.session_id = Some(tab.id.clone());
        started.owned_tab = true;
        if let Some(identity) = started.target_identity.as_mut() {
            identity.tab_id = Some(tab.id.clone());
            identity.session_id = Some(tab.id.clone());
            identity.terminal_handle = Some(tab.id.clone());
            identity.conversation_id = tab.payload["conversationId"].as_str().map(str::to_string);
        }
        let _ = self
            .runtime_store
            .bind_automation_attempt(&started, if resuming { "resume" } else { "contextRetry" })
            .await;
        tab.payload["spawnOnCreate"] = json!(true);
        tab.payload["automationOwned"] = json!(true);
        tab.payload["automationRunId"] = json!(run.id);
        tab.payload["automationAttemptId"] = json!(started.attempt_id);
        started.recovery = Some(AutomationRecovery {
            status: if resuming {
                "resuming"
            } else {
                "retryingWithContext"
            }
            .into(),
            attempt: started.attempt_count,
            max_attempts: definition.retry_max_attempts,
            interrupted_at: run.recovery.as_ref().and_then(|r| r.interrupted_at),
            code: Some("runtimeRestart".into()),
        });
        let _ = self.runtime_store.save_automation_run(&started).await;
        if let Err(error) = self.runtime_store.upsert_workspace_tab(tab.clone()).await {
            self.fail_run(&started, error.to_string()).await;
            return;
        }

        match self.ensure_spawn_on_create_terminal(&tab).await {
            Ok(_) => {
                started.status = AutomationRunStatus::Dispatched;
                started.updated_at = Utc::now();
                let _ = self.runtime_store.save_automation_run(&started).await;
                self.record_automation_process(&started).await;
                self.automation_run_event(&started);
            }
            Err(error) => {
                self.fail_run(&started, error.wire_message()).await;
            }
        }
        run = started;
        self.automation_run_event(&run);
    }

    pub(super) async fn automation_recovery_tab(
        &self,
        run: &AutomationRun,
    ) -> Option<alera_core::runtime::WorkspaceTabRecord> {
        if let Some(id) = run.tab_id.as_deref() {
            return self
                .runtime_store
                .find_workspace_tab(id)
                .await
                .ok()
                .flatten();
        }
        for workspace in self.runtime_store.list_all_workspaces().await.ok()? {
            for tab in self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .ok()?
            {
                if tab.payload["automationRunId"].as_str() == Some(run.id.as_str()) {
                    return Some(tab);
                }
            }
        }
        None
    }
}

pub(super) fn automation_recovery_prompt(
    run: &AutomationRun,
    definition: &AutomationDefinition,
) -> String {
    let original = run
        .rendered_prompt
        .as_deref()
        .unwrap_or(&definition.prompt_template);
    let context = format!("{original}\n\nContinue automation run {} after attempt {}. Preserve existing changes in this workspace and inspect current files before repeating actions. Previous summary: {}. Previous error: {}. Continue the existing task instead of starting it again.", run.id,run.attempt_count,run.summary.as_deref().unwrap_or("No summary recorded"),run.error.as_deref().unwrap_or("Runtime interrupted"));
    automation_attempt_prompt(
        super::automation_dispatch::automation_prompt(
            &context,
            &run.id,
            definition.heartbeat_interval_seconds,
        ),
        run,
    )
}

pub(super) fn automation_attempt_prompt(prompt: String, run: &AutomationRun) -> String {
    match run.attempt_id.as_deref() {
        Some(id) => prompt.replace(
            &format!("--run {}", run.id),
            &format!("--run {} --attempt-id {id}", run.id),
        ),
        None => prompt,
    }
}
