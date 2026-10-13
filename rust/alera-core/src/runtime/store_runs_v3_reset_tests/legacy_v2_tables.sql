-- Legacy v2 table definitions from 62e90b2d3 (before the runs-v3 reset).
-- Includes every orchestration/workflow table and its original foreign keys.

-- orchestration_message_store.rs
CREATE TABLE IF NOT EXISTS orchestrationAuditEvents (
        id TEXT PRIMARY KEY,
        actor_handle TEXT,
        action TEXT NOT NULL,
        target_id TEXT,
        reason TEXT NOT NULL,
        payload TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

-- orchestration_board_schema.rs
CREATE TABLE IF NOT EXISTS orchestrationBoardRevision (
        id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL
    );

-- orchestration_message_store.rs
CREATE TABLE IF NOT EXISTS orchestrationCoordinatorRuns (
        id TEXT PRIMARY KEY,
        spec TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'idle'
            CHECK(status IN ('idle','running','completed','failed','stopping','stopped')),
        coordinator_handle TEXT,
        poll_interval_ms INTEGER NOT NULL DEFAULT 2000,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        completed_at TEXT,
        workspace_id TEXT NOT NULL,
        max_concurrent INTEGER NOT NULL DEFAULT 4,
        last_activity_at TEXT NOT NULL DEFAULT (datetime('now')),
        stop_reason TEXT,
        execution_policy TEXT,
        execution_policy_status TEXT NOT NULL DEFAULT 'none',
        execution_policy_updated_at TEXT
    );

-- orchestration_message_store.rs
CREATE TABLE IF NOT EXISTS orchestrationDecisionGates (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        question TEXT NOT NULL,
        options TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','resolved','timeout')),
        resolution TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        resolved_at TEXT
    );

-- orchestration_message_store.rs
CREATE TABLE IF NOT EXISTS orchestrationDispatchContexts (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        assignee_handle TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','dispatched','completed','failed','circuit_broken','awaiting_acceptance','startup_failed','stalled','cancelled','superseded')),
        failure_count INTEGER NOT NULL DEFAULT 0,
        last_failure TEXT,
        dispatched_at TEXT,
        completed_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        last_heartbeat_at TEXT,
        run_id TEXT,
        workspace_id TEXT NOT NULL,
        coordinator_handle TEXT NOT NULL,
        accepted_at TEXT,
        last_activity_at TEXT,
        context_token_hash TEXT,
        completion_policy TEXT NOT NULL DEFAULT 'return-immediately',
        terminal_policy TEXT NOT NULL DEFAULT 'keep-open',
        startup_error TEXT,
        completion_sha TEXT,
        agent_profile TEXT,
        agent_quota_group TEXT
    );

-- orchestration_message_store.rs
CREATE TABLE IF NOT EXISTS orchestrationMessages (
        id TEXT NOT NULL,
        from_handle TEXT NOT NULL,
        to_handle TEXT NOT NULL,
        subject TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'status'
            CHECK(type IN ('status','dispatch','worker_done','merge_ready',
                           'escalation','handoff','decision_gate','heartbeat')),
        priority TEXT NOT NULL DEFAULT 'normal'
            CHECK(priority IN ('normal','high','urgent')),
        thread_id TEXT,
        payload TEXT,
        read INTEGER NOT NULL DEFAULT 0,
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        delivered_at TEXT,
        run_id TEXT,
        workspace_id TEXT,
        task_id TEXT,
        dispatch_id TEXT,
        state TEXT NOT NULL DEFAULT 'queued'
            CHECK(state IN ('queued','delivered','read','expired','obsolete')),
        expires_at TEXT,
        obsolete_at TEXT
    );

-- orchestration_message_store.rs
CREATE TABLE IF NOT EXISTS orchestrationTasks (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        created_by_terminal_handle TEXT,
        task_title TEXT,
        display_name TEXT,
        spec TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','ready','dispatched','completed','failed','blocked','stalled','cancelled')),
        deps TEXT NOT NULL DEFAULT '[]',
        result TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        completed_at TEXT,
        run_id TEXT,
        workspace_id TEXT NOT NULL,
        coordinator_handle TEXT NOT NULL,
        result_schema TEXT,
        startup_failure_count INTEGER NOT NULL DEFAULT 0,
        cancelled_at TEXT,
        stalled_at TEXT,
        stage_id TEXT
    );

-- workflow_catalog_store.rs
CREATE TABLE IF NOT EXISTS personalWorkflowRecipes (
            id TEXT PRIMARY KEY NOT NULL,
            revision INTEGER NOT NULL CHECK(revision > 0),
            document TEXT NOT NULL CHECK(length(CAST(document AS BLOB)) <= 262144)
        );

-- workflow_plan_schema.rs
CREATE TABLE IF NOT EXISTS workflowApprovalChallenges (
        nonce TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        audience TEXT NOT NULL, statement TEXT NOT NULL, expires_at INTEGER NOT NULL,
        decision_digest TEXT, receipt TEXT
    );

-- workflow_cancellation.rs
CREATE TABLE IF NOT EXISTS workflowCancellationTargets (
        id TEXT PRIMARY KEY,
        launch_id TEXT UNIQUE REFERENCES workflowLaunches(id),
        proposal_id TEXT UNIQUE REFERENCES workflowCoordinators(proposal_id),
        run_id TEXT NOT NULL REFERENCES workflowRuns(run_id),
        state TEXT NOT NULL CHECK(state IN ('pending','settled','attention')),
        error TEXT, CHECK((launch_id IS NULL) <> (proposal_id IS NULL)));

-- workflow_cleanup.rs
CREATE TABLE IF NOT EXISTS workflowCleanup (
            id TEXT PRIMARY KEY,run_id TEXT NOT NULL,digest TEXT NOT NULL,document TEXT NOT NULL,
            expires_at INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('preview','applying','retired','attention')),
            error TEXT);

-- workflow_cleanup.rs
CREATE TABLE IF NOT EXISTS workflowCleanupResources (
            workspace_id TEXT PRIMARY KEY REFERENCES workflowWorkspaces(id),
            cleanup_id TEXT NOT NULL REFERENCES workflowCleanup(id),retired INTEGER NOT NULL DEFAULT 0);

-- workflow_coordinator.rs
CREATE TABLE IF NOT EXISTS workflowCoordinators (
            proposal_id TEXT PRIMARY KEY REFERENCES workflowProposalDrafts(id),
            tab_id TEXT NOT NULL UNIQUE, workspace_id TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('reserved','started','attention')),
            error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

-- workflow_plan_schema.rs
CREATE TABLE IF NOT EXISTS workflowDecisions (
        id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, scope TEXT NOT NULL, decision TEXT NOT NULL,
        reason TEXT NOT NULL, plan_digest TEXT NOT NULL, evidence_digest TEXT NOT NULL,
        integration_sha TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

-- workflow_execution.rs
CREATE TABLE IF NOT EXISTS workflowExecution (
                run_id TEXT PRIMARY KEY REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
                revision INTEGER NOT NULL, sequence INTEGER NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('running','paused'))
            );

-- workflow_execution.rs
CREATE TABLE IF NOT EXISTS workflowExecutionCommands (
                request_id TEXT PRIMARY KEY, request_digest TEXT NOT NULL,
                run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
                receipt TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

-- workflow_execution.rs
CREATE TABLE IF NOT EXISTS workflowExecutionIssues (
            run_id TEXT PRIMARY KEY REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
            revision INTEGER NOT NULL, sequence INTEGER NOT NULL, reason TEXT NOT NULL);

-- workflow_integration_schema.rs
CREATE TABLE IF NOT EXISTS workflowIntegrations (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL,
        run_id TEXT NOT NULL, revision INTEGER NOT NULL, task_id TEXT NOT NULL,
        workspace_id TEXT NOT NULL REFERENCES workflowWorkspaces(id), request TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('pending','prepared','integrated','conflict','attention')),
        receipt TEXT, conflict_paths TEXT NOT NULL DEFAULT '[]', conflicts_truncated INTEGER NOT NULL DEFAULT 0,
        error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

-- workflow_launch_schema.rs
CREATE TABLE IF NOT EXISTS workflowLaunches (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL, request TEXT NOT NULL,
        run_id TEXT NOT NULL, revision INTEGER NOT NULL, task_id TEXT NOT NULL,
        workspace_id TEXT NOT NULL UNIQUE REFERENCES workflowWorkspaces(id),
        terminal_handle TEXT NOT NULL UNIQUE, dispatch_id TEXT NOT NULL UNIQUE,
        base_sha TEXT NOT NULL, profile_id TEXT NOT NULL, profile_revision INTEGER NOT NULL,
        inputs TEXT NOT NULL, context_hash TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('reserved','starting','started','attention')),
        error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

-- workflow_plan_schema.rs
CREATE TABLE IF NOT EXISTS workflowPlanRevisions (
        run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, request_id TEXT NOT NULL UNIQUE, request_digest TEXT NOT NULL,
        snapshot TEXT NOT NULL, digest TEXT NOT NULL, previous_revision INTEGER, change_reason TEXT,
        PRIMARY KEY(run_id, revision)
    );

-- workflow_plan_schema.rs
CREATE TABLE IF NOT EXISTS workflowPlanTasks (
        task_id TEXT PRIMARY KEY REFERENCES orchestrationTasks(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, logical_id TEXT NOT NULL, frozen_task TEXT NOT NULL,
        UNIQUE(run_id, revision, logical_id)
    );

-- workflow_coordinator.rs
CREATE TABLE IF NOT EXISTS workflowProposalCancellations (
            proposal_id TEXT PRIMARY KEY REFERENCES workflowProposalDrafts(id),
            tab_id TEXT, workspace_id TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('pending','settled','attention')),
            error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')));

-- workflow_proposal.rs
CREATE TABLE IF NOT EXISTS workflowProposalDrafts (
            id TEXT PRIMARY KEY, request_digest TEXT NOT NULL, document TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

-- workflow_plan_schema.rs
CREATE TABLE IF NOT EXISTS workflowRuns (
        run_id TEXT PRIMARY KEY REFERENCES orchestrationCoordinatorRuns(id) ON DELETE CASCADE,
        workspace_id TEXT NOT NULL, revision INTEGER NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('prepared','approved','rejected','changesRequested','completed','cancelled')),
        integration_sha TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

-- workflow_plan_schema.rs
CREATE TABLE IF NOT EXISTS workflowStageGates (
        run_id TEXT NOT NULL REFERENCES workflowRuns(run_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, stage_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
        decision_id TEXT REFERENCES workflowDecisions(id), PRIMARY KEY(run_id, revision, stage_id)
    );

-- workflow_plan_schema.rs
CREATE TABLE IF NOT EXISTS workflowTaskEvidence (
        task_id TEXT PRIMARY KEY REFERENCES workflowPlanTasks(task_id) ON DELETE CASCADE,
        result_digest TEXT NOT NULL, artifact_digest TEXT NOT NULL, integration_sha TEXT NOT NULL
    );

-- workflow_cancellation.rs
CREATE TABLE IF NOT EXISTS workflowTerminalShutdowns (
        tab_id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('started','verified')));

-- workflow_workspace_schema.rs
CREATE TABLE IF NOT EXISTS workflowWorkspaceRequests (
        request_id TEXT PRIMARY KEY, digest TEXT NOT NULL, workspace_id TEXT NOT NULL REFERENCES workflowWorkspaces(id)
    );

-- workflow_workspace_schema.rs
CREATE TABLE IF NOT EXISTS workflowWorkspaces (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        run_id TEXT NOT NULL, revision INTEGER NOT NULL, task_id TEXT,
        attempt INTEGER NOT NULL, path TEXT NOT NULL UNIQUE, identity TEXT NOT NULL,
        phase TEXT NOT NULL CHECK(phase IN ('reserved','creating','created','setupRunning','ready','attention')),
        setup_report TEXT, error TEXT, dispatch_id TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

ALTER TABLE orchestrationMessages ADD COLUMN external_meta TEXT;

ALTER TABLE orchestrationMessages ADD COLUMN reply_to_id TEXT;

ALTER TABLE orchestrationTasks ADD COLUMN role_contract TEXT;

ALTER TABLE workflowCleanup ADD COLUMN abandoned INTEGER NOT NULL DEFAULT 0;

ALTER TABLE workflowIntegrations ADD COLUMN cancelled INTEGER NOT NULL DEFAULT 0;

ALTER TABLE workflowProposalCancellations ADD COLUMN sequence INTEGER NOT NULL DEFAULT 0;
