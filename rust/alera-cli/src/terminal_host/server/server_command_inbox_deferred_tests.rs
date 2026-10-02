use super::*;
use crate::terminal_host::host_error::HostError;
use alera_core::runtime::{
    AgentProfile, AgentProfileLaunchMode, AutomationActor, AutomationActorKind,
    AutomationDefinition, AutomationMisfirePolicy, AutomationOverlapPolicy, AutomationRun,
    AutomationRunStatus, AutomationRunTrigger, AutomationSchedule, AutomationSetupPolicy,
    AutomationState, AutomationTarget, FrozenWorkflowTask, LaunchWorkflowTask,
    RoleContractChecklistItem, RoleContractSnapshot, RoleContractV1, WorkflowLaunchInputs,
    WorkflowLaunchRecord, WorkflowLaunchStatus, WorkflowPlanTask, WorkflowWorkspaceIdentity,
};
use chrono::Utc;
use serde_json::json;

type WorkflowLaunchCommand = super::super::workflow_launch_requests::WorkflowLaunchCommand;
type WorkflowLaunchReply = super::super::workflow_launch_requests::WorkflowLaunchReply;
type ValidatedWorkflowLaunch = super::super::workflow_launch_requests::ValidatedWorkflowLaunch;
pub(super) fn fill_control_and_request_shutdown(inbox: &ServerInbox) {
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .expect("control admission");
    }
    inbox
        .send(ServerCommand::RequestedShutdown)
        .expect("shutdown control wake");
}
pub(super) async fn next_deferred(receiver: &mut ServerInboxReceiver) -> ServerCommand {
    loop {
        match receiver.recv().await {
            Some(ServerCommand::ClientDisconnected { .. })
            | Some(ServerCommand::RequestedShutdown) => {}
            Some(command) => return command,
            None => panic!("deferred command receiver closed"),
        }
    }
}

pub(super) fn launch_record(id: &str) -> WorkflowLaunchRecord {
    WorkflowLaunchRecord {
        id: id.to_string(),
        request: LaunchWorkflowTask {
            request_id: format!("request-{id}"),
            run_id: "run-1".to_string(),
            revision: 1,
            task_id: format!("task-{id}"),
            workspace_id: "workspace-1".to_string(),
        },
        terminal_handle: format!("terminal-{id}"),
        dispatch_id: format!("dispatch-{id}"),
        base_sha: "0123456789abcdef0123456789abcdef01234567".to_string(),
        profile_id: "profile-1".to_string(),
        profile_revision: 1,
        status: WorkflowLaunchStatus::Reserved,
        error: None,
    }
}

pub(super) fn workflow_inputs() -> WorkflowLaunchInputs {
    let now = Utc::now();
    let profile = AgentProfile {
        id: "profile-1".to_string(),
        name: "Codex".to_string(),
        sort_order: 0,
        agent_type: "codex".to_string(),
        command: "codex".to_string(),
        launch_mode: AgentProfileLaunchMode::Command,
        managed_config: None,
        custom_prompt: String::new(),
        description: String::new(),
        quota_group: None,
        show_in_new_tab_menu: false,
        revision: 1,
        created_at: now,
        updated_at: now,
    };
    let task = WorkflowPlanTask {
        id: "task-1".to_string(),
        title: "Task".to_string(),
        spec: "Do the task".to_string(),
        stage_id: "stage-1".to_string(),
        role_id: "role-1".to_string(),
        depends_on: Vec::new(),
        inputs: json!({}),
        corrects_task_id: None,
    };
    let contract = RoleContractV1 {
        version: 1,
        id: "contract-1".to_string(),
        revision: 1,
        name: "Contract".to_string(),
        purpose: "Test contract".to_string(),
        instructions: "Test instructions".to_string(),
        input_schema: json!({"type": "object"}),
        result_schema: json!({"type": "object"}),
        required_artifacts: Vec::new(),
        checklist: vec![RoleContractChecklistItem {
            id: "check-1".to_string(),
            description: "Check".to_string(),
        }],
    };
    let frozen_task = FrozenWorkflowTask {
        task,
        contract: RoleContractSnapshot {
            version: 1,
            contract: contract.clone(),
            inputs: json!({}),
            digest: "contract-digest".to_string(),
        },
        profile_id: profile.id.clone(),
    };
    WorkflowLaunchInputs {
        workspace: WorkflowWorkspaceIdentity {
            workspace: serde_json::from_value(json!({
                "id": "workspace-1",
                "instanceId": "workspace-1-instance",
                "hostId": "local",
                "projectId": "project",
                "name": "Workspace 1",
                "branch": "main",
                "path": "/tmp/workspace-1",
                "createdAt": now,
                "updatedAt": now,
                "kind": "main",
                "status": "active",
                "sourceBranch": null,
                "reusesExistingBranch": false,
                "isPinned": false,
                "isArchived": false,
                "tagIds": [],
                "tagNames": [],
                "sectionId": null,
                "parentWorkspaceId": null,
                "childCount": 0,
            }))
            .expect("workflow workspace fixture"),
            repo_path: "/tmp/project".to_string(),
            owner_workspace_id: "owner-workspace-1".to_string(),
            run_id: "run-1".to_string(),
            revision: 1,
            task_id: Some("task-1".to_string()),
            attempt: 1,
            base_sha: "0123456789abcdef0123456789abcdef01234567".to_string(),
        },
        task: frozen_task,
        profile,
        plan_digest: "plan-digest".to_string(),
    }
}

fn claimed_command(id: &str) -> ServerCommand {
    ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::Claimed {
        reply: WorkflowLaunchReply::Client(7, 300),
        record: Box::new(launch_record(id)),
        token: format!("token-{id}"),
        locks: [
            tempfile::tempfile().expect("claim lock"),
            tempfile::tempfile().expect("attempt lock"),
        ],
        result: Box::new(Err(HostError::state("claim failed"))),
    })
}

fn spawn_validated_command(id: &str) -> ServerCommand {
    ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::SpawnValidated(Box::new(
        ValidatedWorkflowLaunch::from_test(
            WorkflowLaunchReply::Client(7, 400),
            launch_record(id),
            format!("token-{id}"),
            [
                tempfile::tempfile().expect("claim lock"),
                tempfile::tempfile().expect("attempt lock"),
            ],
            workflow_inputs(),
            Err(HostError::state("spawn validation failed")),
        ),
    )))
}

#[tokio::test]
async fn workflow_launch_deferred_variants_survive_shutdown_admission_closure() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_and_request_shutdown(&inbox);
    let commands = [
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::CoordinatorPrepared {
            client_id: 7,
            request_id: 100,
            result: Err(HostError::state("coordinator failed")),
        }),
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::Prepared {
            client_id: 7,
            request_id: 200,
            result: Err(HostError::state("prepare failed")),
        }),
        claimed_command("claimed-1"),
        spawn_validated_command("validated-1"),
    ];
    for command in commands {
        inbox
            .send_wait(command)
            .await
            .expect("accepted workflow completion must be retained");
    }

    for expected in [100, 200] {
        match next_deferred(&mut receiver).await {
            ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::CoordinatorPrepared {
                client_id,
                request_id,
                ..
            }) if client_id == 7 && request_id == expected => {}
            ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::Prepared {
                client_id,
                request_id,
                ..
            }) if client_id == 7 && request_id == expected => {}
            _ => panic!("unexpected workflow completion"),
        }
    }
    match next_deferred(&mut receiver).await {
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::Claimed {
            reply: WorkflowLaunchReply::Client(client_id, request_id),
            record,
            ..
        }) => {
            assert_eq!((client_id, request_id), (7, 300));
            assert_eq!(record.id, "claimed-1");
        }
        _ => panic!("unexpected claimed completion"),
    }
    match next_deferred(&mut receiver).await {
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::SpawnValidated(validated)) => {
            let (reply, record, _token, _locks, _frozen, _result) = (*validated).into_test_parts();
            assert!(matches!(reply, WorkflowLaunchReply::Client(7, 400)));
            assert_eq!(record.id, "validated-1");
        }
        _ => panic!("unexpected spawn validation completion"),
    }
}

#[tokio::test]
async fn runtime_mutation_completion_survives_shutdown_admission_closure() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_and_request_shutdown(&inbox);
    inbox
        .send_wait(ServerCommand::RuntimeMutationFinished(
            super::super::runtime_mutations::RuntimeMutationFinished {
                client_id: 12,
                request_id: 34,
                outcome: super::super::runtime_mutations::RuntimeMutationOutcome {
                    result: Err(HostError::state("mutation failed")),
                    completion_on_error: None,
                    ended_pointer_tab_ids: Vec::new(),
                    closed_session_tab_ids: Vec::new(),
                    committed_tab_ids: Vec::new(),
                    effect_on_error: None,
                    stopped_workspace_tab_ids: Vec::new(),
                    pending_workspace_shutdown: None,
                },
            },
        ))
        .await
        .expect("runtime mutation completion must be retained");
    match next_deferred(&mut receiver).await {
        ServerCommand::RuntimeMutationFinished(finished) => {
            assert_eq!((finished.client_id, finished.request_id), (12, 34));
            assert!(finished.outcome.result.is_err());
        }
        _ => panic!("unexpected mutation completion"),
    }
}

#[tokio::test]
async fn watcher_buffer_guard_and_voice_lifecycle_controls_survive_shutdown() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_and_request_shutdown(&inbox);
    for command in [
        ServerCommand::TerminalPulseWatcherStarted {
            workspace_id: "workspace-1".to_string(),
            generation: 9,
            result: Err(HostError::state("watcher failed")),
        },
        ServerCommand::BufferGuardExpired {
            id: "guard-1".to_string(),
        },
        ServerCommand::VoiceRealtimeReconnect { generation: 5 },
        ServerCommand::VoiceGeminiTranscriptSettle {
            generation: 5,
            token: 8,
        },
        ServerCommand::VoiceRealtime {
            generation: 5,
            event: super::super::voice_realtime::VoiceRealtimeEvent::Closed {
                error: Some("voice closed".to_string()),
            },
        },
    ] {
        inbox
            .send_wait(command)
            .await
            .expect("lifecycle completion must be retained");
    }

    match next_deferred(&mut receiver).await {
        ServerCommand::TerminalPulseWatcherStarted {
            workspace_id,
            generation,
            result,
        } => {
            assert_eq!((workspace_id, generation), ("workspace-1".to_string(), 9));
            assert!(result.is_err());
        }
        _ => panic!("unexpected watcher completion"),
    }
    match next_deferred(&mut receiver).await {
        ServerCommand::BufferGuardExpired { id } => assert_eq!(id, "guard-1"),
        _ => panic!("unexpected buffer guard completion"),
    }
    assert!(matches!(
        next_deferred(&mut receiver).await,
        ServerCommand::VoiceRealtimeReconnect { generation: 5 }
    ));
    assert!(matches!(
        next_deferred(&mut receiver).await,
        ServerCommand::VoiceGeminiTranscriptSettle {
            generation: 5,
            token: 8
        }
    ));
    assert!(matches!(
        next_deferred(&mut receiver).await,
        ServerCommand::VoiceRealtime {
            generation: 5,
            event: super::super::voice_realtime::VoiceRealtimeEvent::Closed { .. }
        }
    ));
}

fn automation_definition() -> AutomationDefinition {
    let now = Utc::now();
    AutomationDefinition {
        id: "automation-1".to_string(),
        slug: "automation-1".to_string(),
        name: "Automation".to_string(),
        description: String::new(),
        project_id: Some("project".to_string()),
        tag_ids: Vec::new(),
        prompt_template: "Do it".to_string(),
        schedule: AutomationSchedule::OneTime {
            at: now,
            timezone: "UTC".to_string(),
        },
        target: AutomationTarget::ExistingTab {
            workspace_id: "workspace-1".to_string(),
            tab_id: "tab-1".to_string(),
            conversation_id: None,
        },
        setup_policy: AutomationSetupPolicy::Wait,
        cleanup_policy: None,
        overlap_policy: AutomationOverlapPolicy::Skip,
        queue_cap: 10,
        inactivity_timeout_seconds: 120,
        heartbeat_interval_seconds: 10,
        misfire_grace_seconds: 60,
        misfire_policy: AutomationMisfirePolicy::Skip,
        retry_max_attempts: 3,
        retry_backoff_seconds: 1,
        circuit_failure_threshold: 3,
        circuit_open_seconds: 60,
        precheck: None,
        notify_on_success: false,
        circuit_opened: false,
        circuit_opened_at: None,
        state: AutomationState::Active,
        revision: 1,
        approved_revision: Some(1),
        created_by: AutomationActor {
            kind: AutomationActorKind::LocalCli,
            id: None,
            label: None,
        },
        modified_by: AutomationActor {
            kind: AutomationActorKind::LocalCli,
            id: None,
            label: None,
        },
        created_at: now,
        updated_at: now,
    }
}

fn automation_run() -> AutomationRun {
    let now = Utc::now();
    AutomationRun {
        id: "run-1".to_string(),
        automation_id: "automation-1".to_string(),
        number: 1,
        occurrence_key: "occurrence-1".to_string(),
        scheduled_at: now,
        trigger: AutomationRunTrigger::Manual,
        actor_kind: Some(AutomationActorKind::LocalCli),
        actor_id: None,
        target_identity: None,
        overlap_policy: None,
        precheck: None,
        status: AutomationRunStatus::Dispatching,
        summary: None,
        error: None,
        rendered_prompt: None,
        workspace_id: Some("workspace-1".to_string()),
        tab_id: Some("tab-1".to_string()),
        setup_tab_id: None,
        workspace_branch: None,
        session_id: None,
        owned_workspace: false,
        owned_tab: false,
        taken_over: false,
        attempt_count: 1,
        started_at: Some(now),
        last_heartbeat_at: Some(now),
        absolute_deadline_at: None,
        waiting_extension_until: None,
        cancel_requested_at: None,
        retry_after: None,
        finished_at: None,
        created_at: now,
        updated_at: now,
    }
}

pub(super) fn oversized_message() -> String {
    "x".repeat(SERVER_COMMAND_COMPLETION_BYTES + 1)
}

#[tokio::test]
async fn oversized_automation_and_orchestration_completions_keep_identity() {
    let (inbox, mut receiver) = ServerInbox::channel();
    let definition = automation_definition();
    let run = automation_run();

    inbox
        .send_wait(ServerCommand::AutomationPrecheckFinished {
            definition: Box::new(definition.clone()),
            run: Box::new(run.clone()),
            host_id: "local".to_string(),
            path: "/tmp/precheck".to_string(),
            result: Err(oversized_message()),
        })
        .await
        .expect("oversized precheck completion must remain deliverable");
    inbox
        .send_wait(ServerCommand::OrchestrationCompletionFinished(
            super::super::orchestration_completion::OrchestrationCompletionFinished {
                client_id: 22,
                request_id: 23,
                dispatch_id: "dispatch-1".to_string(),
                assignee: "assignee-1".to_string(),
                result: oversized_message(),
                completion_sha: Ok("sha-1".to_string()),
            },
        ))
        .await
        .expect("oversized orchestration completion must remain deliverable");

    match receiver.recv().await {
        Some(ServerCommand::AutomationPrecheckFinished {
            definition,
            run,
            host_id,
            path,
            result,
        }) => {
            assert_eq!(
                (definition.id, run.id, host_id, path),
                (
                    "automation-1".to_string(),
                    "run-1".to_string(),
                    "local".to_string(),
                    "/tmp/precheck".to_string(),
                )
            );
            assert!(result.as_ref().unwrap_err().len() < 256);
        }
        _ => panic!("unexpected precheck completion"),
    }
    match receiver.recv().await {
        Some(ServerCommand::OrchestrationCompletionFinished(completion)) => {
            assert_eq!(
                (
                    completion.client_id,
                    completion.request_id,
                    completion.dispatch_id
                ),
                (22, 23, "dispatch-1".to_string())
            );
            assert!(completion.result.len() < 256);
        }
        _ => panic!("unexpected orchestration completion"),
    }
}
