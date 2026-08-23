//! DDL for the runtime tables. Kept beside the store rather than inside it so
//! the schema stays readable as it grows.
//!
//! Every statement is idempotent, so `migrate` can replay the whole list. A
//! column added to an existing table here still needs an `ensure_column` call,
//! because `CREATE TABLE IF NOT EXISTS` is a no-op on an existing database.

pub(super) const RUNTIME_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS runtimeMetadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        repoPath TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        kind TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS projectConfigs (
        projectId TEXT PRIMARY KEY,
        dataJson TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS workspaces (
        id TEXT PRIMARY KEY,
        instanceId TEXT NOT NULL,
        hostId TEXT NOT NULL,
        projectId TEXT NOT NULL,
        name TEXT NOT NULL,
        branch TEXT,
        path TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        sourceBranch TEXT,
        reusesExistingBranch INTEGER NOT NULL DEFAULT 0,
        isPinned INTEGER NOT NULL DEFAULT 0
    );",
    "CREATE INDEX IF NOT EXISTS workspacesProjectStatusIdx ON workspaces(projectId, status, kind, createdAt);",
    "CREATE UNIQUE INDEX IF NOT EXISTS workspacesInstanceIdx ON workspaces(instanceId);",
    "CREATE TABLE IF NOT EXISTS workspaceTabs (
        id TEXT PRIMARY KEY,
        workspaceId TEXT NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        payloadJson TEXT NOT NULL DEFAULT '{}'
    );",
    "CREATE INDEX IF NOT EXISTS workspaceTabsWorkspaceIdx ON workspaceTabs(workspaceId, createdAt);",
    "CREATE TABLE IF NOT EXISTS linkedReviews (
        workspaceId TEXT PRIMARY KEY,
        dismissed INTEGER NOT NULL DEFAULT 0,
        provider TEXT,
        number INTEGER,
        url TEXT,
        linkedAt TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS workbenchLayouts (
        workspaceId TEXT PRIMARY KEY,
        dataJson TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS workspaceTags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS workspaceTagsNameIdx ON workspaceTags(name COLLATE NOCASE);",
    "CREATE TABLE IF NOT EXISTS workspaceTagAssignments (
        workspaceId TEXT NOT NULL,
        tagId TEXT NOT NULL,
        PRIMARY KEY(workspaceId, tagId)
    );",
    "CREATE INDEX IF NOT EXISTS workspaceTagAssignmentsTagIdx ON workspaceTagAssignments(tagId, workspaceId);",
    "CREATE TABLE IF NOT EXISTS workspaceRelations (
        id TEXT PRIMARY KEY,
        parentWorkspaceId TEXT NOT NULL,
        parentInstanceId TEXT NOT NULL,
        childWorkspaceId TEXT NOT NULL,
        childInstanceId TEXT NOT NULL,
        createdAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS workspaceRelationsPairIdx ON workspaceRelations(parentWorkspaceId, childWorkspaceId);",
    "CREATE UNIQUE INDEX IF NOT EXISTS workspaceRelationsChildIdx ON workspaceRelations(childWorkspaceId);",
    "CREATE INDEX IF NOT EXISTS workspaceRelationsParentIdx ON workspaceRelations(parentWorkspaceId);",
    "CREATE TABLE IF NOT EXISTS sshTargets (
        id TEXT PRIMARY KEY,
        alias TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL,
        platform TEXT,
        arch TEXT,
        authKind TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        lastStatus TEXT,
        installDir TEXT,
        runtimeVersion TEXT,
        runtimePlatform TEXT,
        runtimeArch TEXT,
        bootstrapStatus TEXT NOT NULL DEFAULT 'notInstalled',
        lastBootstrapAt TEXT,
        lastCheckedAt TEXT,
        lastError TEXT
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS sshTargetsAliasIdx ON sshTargets(alias COLLATE NOCASE);",
    "CREATE TABLE IF NOT EXISTS agentProfiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        agentType TEXT NOT NULL,
        command TEXT NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        launchMode TEXT NOT NULL DEFAULT 'command',
        managedConfig TEXT,
        customPrompt TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        quotaGroup TEXT,
        revision INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS agentProfilesNameIdx ON agentProfiles(name COLLATE NOCASE);",
    "CREATE TABLE IF NOT EXISTS agentProfileLaunchReceipts (
        callerScope TEXT NOT NULL,
        workspaceId TEXT NOT NULL,
        clientMutationId TEXT NOT NULL,
        payloadDigest TEXT NOT NULL,
        tabId TEXT NOT NULL,
        resultJson TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        PRIMARY KEY(callerScope, workspaceId, clientMutationId)
    );",
    "CREATE INDEX IF NOT EXISTS agentProfileLaunchReceiptsRetentionIdx ON agentProfileLaunchReceipts(createdAt);",
    "CREATE INDEX IF NOT EXISTS agentProfileLaunchReceiptsScopeIdx ON agentProfileLaunchReceipts(callerScope, workspaceId, createdAt DESC);",
    "CREATE TABLE IF NOT EXISTS browserProfiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        persistent INTEGER NOT NULL DEFAULT 1,
        isDefault INTEGER NOT NULL DEFAULT 0,
        sourceFamily TEXT,
        sourceProfileName TEXT,
        sourceImportedAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS browserProfilesNameIdx ON browserProfiles(name COLLATE NOCASE);",
    "CREATE UNIQUE INDEX IF NOT EXISTS browserProfilesDefaultIdx ON browserProfiles(isDefault) WHERE isDefault = 1;",
    "CREATE TABLE IF NOT EXISTS browserHistory (
        id TEXT PRIMARY KEY,
        profileId TEXT NOT NULL,
        workspaceId TEXT,
        tabId TEXT,
        url TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        visitCount INTEGER NOT NULL DEFAULT 1,
        visitedAt TEXT NOT NULL
    );",
    "CREATE INDEX IF NOT EXISTS browserHistoryProfileVisitedIdx ON browserHistory(profileId, visitedAt DESC);",
    "CREATE TABLE IF NOT EXISTS browserClosedTabs (
        id TEXT PRIMARY KEY,
        profileId TEXT NOT NULL,
        workspaceId TEXT NOT NULL,
        url TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        payloadJson TEXT NOT NULL DEFAULT '{}',
        closedAt TEXT NOT NULL
    );",
    "CREATE INDEX IF NOT EXISTS browserClosedTabsProfileClosedIdx ON browserClosedTabs(profileId, closedAt DESC);",
    "CREATE TABLE IF NOT EXISTS browserPermissions (
        profileId TEXT NOT NULL,
        origin TEXT NOT NULL,
        permission TEXT NOT NULL,
        decision TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        PRIMARY KEY(profileId, origin, permission)
    );",
    "CREATE INDEX IF NOT EXISTS browserPermissionsOriginIdx ON browserPermissions(origin, permission);",
    "CREATE TABLE IF NOT EXISTS browserTrustedCertificates (
        profileId TEXT NOT NULL,
        host TEXT NOT NULL,
        fingerprintSha256 TEXT NOT NULL,
        subject TEXT,
        issuer TEXT,
        validFrom TEXT,
        validTo TEXT,
        createdAt TEXT NOT NULL,
        lastUsedAt TEXT NOT NULL,
        PRIMARY KEY(profileId, host, fingerprintSha256)
    );",
    "CREATE INDEX IF NOT EXISTS browserTrustedCertificatesHostIdx ON browserTrustedCertificates(host, fingerprintSha256);",
    "CREATE TABLE IF NOT EXISTS mobileAccessSettings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        enabled INTEGER NOT NULL DEFAULT 0,
        remoteAccessEnabled INTEGER NOT NULL DEFAULT 0,
        bindHost TEXT NOT NULL,
        port INTEGER NOT NULL,
        endpointMode TEXT NOT NULL DEFAULT 'loopback',
        netbirdEndpoint TEXT NOT NULL DEFAULT 'ip',
        serverPublicKeyB64 TEXT,
        updatedAt TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS mobileDevices (
        id TEXT PRIMARY KEY,
        displayName TEXT NOT NULL,
        tokenHash TEXT NOT NULL,
        publicKeyB64 TEXT,
        permission TEXT NOT NULL,
        pairedAt TEXT NOT NULL,
        lastSeenAt TEXT,
        revokedAt TEXT
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS mobileDevicesTokenHashIdx ON mobileDevices(tokenHash);",
    "CREATE INDEX IF NOT EXISTS mobileDevicesRevokedIdx ON mobileDevices(revokedAt, pairedAt);",
    "CREATE TABLE IF NOT EXISTS mobilePairingOffers (
        id TEXT PRIMARY KEY,
        endpoint TEXT NOT NULL,
        secretHash TEXT NOT NULL,
        expectedDeviceName TEXT,
        serverPublicKeyB64 TEXT,
        createdAt TEXT NOT NULL,
        expiresAt TEXT NOT NULL,
        claimedDeviceId TEXT
    );",
    "CREATE INDEX IF NOT EXISTS mobilePairingOffersActiveIdx ON mobilePairingOffers(expiresAt, claimedDeviceId);",
    "CREATE TABLE IF NOT EXISTS aleraAccount (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        accountId TEXT NOT NULL,
        email TEXT NOT NULL,
        providersJson TEXT NOT NULL,
        runtimeId TEXT NOT NULL,
        cloudBaseUrl TEXT NOT NULL,
        signedInAt TEXT NOT NULL,
        accessTokenExpiresAt TEXT NOT NULL,
        pushSubscriptionCount INTEGER NOT NULL DEFAULT 0
    );",
    "CREATE TABLE IF NOT EXISTS codexResetCreditAttempts (
        accountId TEXT PRIMARY KEY,
        offerRevision TEXT NOT NULL,
        idempotencyKey TEXT NOT NULL,
        state TEXT NOT NULL,
        outcome TEXT,
        updatedAt INTEGER NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS automations (
        id TEXT PRIMARY KEY,
        slug TEXT NOT NULL,
        state TEXT NOT NULL,
        revision INTEGER NOT NULL,
        dataJson TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        trashedAt TEXT
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS automationsSlugIdx ON automations(slug COLLATE NOCASE);",
    "CREATE INDEX IF NOT EXISTS automationsStateIdx ON automations(state, updatedAt);",
    "CREATE TABLE IF NOT EXISTS automationOccurrences (
        automationId TEXT NOT NULL,
        occurrenceKey TEXT NOT NULL,
        scheduledAt TEXT NOT NULL,
        claimedAt TEXT NOT NULL,
        PRIMARY KEY(automationId, occurrenceKey)
    );",
    "CREATE INDEX IF NOT EXISTS automationOccurrencesScheduledIdx ON automationOccurrences(automationId, scheduledAt);",
    "CREATE TABLE IF NOT EXISTS automationRuns (
        id TEXT PRIMARY KEY,
        automationId TEXT NOT NULL,
        runNumber INTEGER NOT NULL,
        occurrenceKey TEXT NOT NULL,
        scheduledAt TEXT NOT NULL,
        trigger TEXT NOT NULL,
        status TEXT NOT NULL,
        dataJson TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        finishedAt TEXT
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS automationRunsOccurrenceIdx ON automationRuns(automationId, occurrenceKey);",
    "CREATE INDEX IF NOT EXISTS automationRunsHistoryIdx ON automationRuns(automationId, createdAt DESC);",
    "CREATE TABLE IF NOT EXISTS automationAttempts (
        id TEXT PRIMARY KEY,
        runId TEXT NOT NULL,
        attemptNumber INTEGER NOT NULL,
        status TEXT NOT NULL,
        dataJson TEXT NOT NULL,
        startedAt TEXT NOT NULL,
        finishedAt TEXT
    );",
    "CREATE INDEX IF NOT EXISTS automationAttemptsRunIdx ON automationAttempts(runId, attemptNumber);",
    "CREATE TABLE IF NOT EXISTS automationAuditEvents (
        id TEXT PRIMARY KEY,
        automationId TEXT,
        runId TEXT,
        action TEXT NOT NULL,
        actorJson TEXT NOT NULL,
        revision INTEGER,
        detailsJson TEXT NOT NULL,
        createdAt TEXT NOT NULL
    );",
    "CREATE INDEX IF NOT EXISTS automationAuditCreatedIdx ON automationAuditEvents(createdAt DESC);",
    "CREATE TABLE IF NOT EXISTS automationTemplates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        dataJson TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS automationTemplatesNameIdx ON automationTemplates(name COLLATE NOCASE);",
    "CREATE TABLE IF NOT EXISTS automationTags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS automationTagsNameIdx ON automationTags(name COLLATE NOCASE);",
    "CREATE TABLE IF NOT EXISTS automationTagAssignments (
        automationId TEXT NOT NULL,
        tagId TEXT NOT NULL,
        PRIMARY KEY(automationId, tagId)
    );",
    "CREATE TABLE IF NOT EXISTS automationAgentPolicies (
        profileId TEXT PRIMARY KEY,
        dataJson TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS automationProjectPolicies (
        projectId TEXT PRIMARY KEY,
        dataJson TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
];

/// Prevents a writer that was validated before a concurrent profile removal
/// from committing a new dangling reference after that removal. These run
/// after every owning table (including orchestration tables) has been created.
pub(super) const AGENT_PROFILE_REFERENCE_TRIGGERS: &[&str] = &[
    "CREATE TRIGGER IF NOT EXISTS workspaceTabsAgentProfileInsertGuard
     BEFORE INSERT ON workspaceTabs
     WHEN json_extract(NEW.payloadJson, '$.agentProfileId') IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM agentProfiles
         WHERE id = json_extract(NEW.payloadJson, '$.agentProfileId')
       )
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS workspaceTabsAgentProfileUpdateGuard
     BEFORE UPDATE OF payloadJson ON workspaceTabs
     WHEN json_extract(NEW.payloadJson, '$.agentProfileId') IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM agentProfiles
         WHERE id = json_extract(NEW.payloadJson, '$.agentProfileId')
       )
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS workspaceTabsAgentProfileSnapshotInsertGuard
     BEFORE INSERT ON workspaceTabs
     WHEN json_extract(NEW.payloadJson, '$.agentProfileLaunchV1.profile.id') IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM agentProfiles
         WHERE id = json_extract(NEW.payloadJson, '$.agentProfileLaunchV1.profile.id')
       )
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS workspaceTabsAgentProfileSnapshotUpdateGuard
     BEFORE UPDATE OF payloadJson ON workspaceTabs
     WHEN json_extract(NEW.payloadJson, '$.agentProfileLaunchV1.profile.id') IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM agentProfiles
         WHERE id = json_extract(NEW.payloadJson, '$.agentProfileLaunchV1.profile.id')
       )
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS automationsAgentProfileInsertGuard
     BEFORE INSERT ON automations
     WHEN COALESCE(
       json_extract(NEW.dataJson, '$.target.freshTab.agent_profile_id'),
       json_extract(NEW.dataJson, '$.target.managedWorkspace.agent_profile_id')
     ) IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM agentProfiles WHERE id = COALESCE(
           json_extract(NEW.dataJson, '$.target.freshTab.agent_profile_id'),
           json_extract(NEW.dataJson, '$.target.managedWorkspace.agent_profile_id')
         )
       )
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS automationsAgentProfileUpdateGuard
     BEFORE UPDATE OF dataJson ON automations
     WHEN COALESCE(
       json_extract(NEW.dataJson, '$.target.freshTab.agent_profile_id'),
       json_extract(NEW.dataJson, '$.target.managedWorkspace.agent_profile_id')
     ) IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM agentProfiles WHERE id = COALESCE(
           json_extract(NEW.dataJson, '$.target.freshTab.agent_profile_id'),
           json_extract(NEW.dataJson, '$.target.managedWorkspace.agent_profile_id')
         )
       )
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS automationAgentPoliciesProfileInsertGuard
     BEFORE INSERT ON automationAgentPolicies
     WHEN NOT EXISTS (SELECT 1 FROM agentProfiles WHERE id = NEW.profileId)
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS automationAgentPoliciesProfileUpdateGuard
     BEFORE UPDATE OF profileId ON automationAgentPolicies
     WHEN NOT EXISTS (SELECT 1 FROM agentProfiles WHERE id = NEW.profileId)
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS defaultAgentProfileInsertGuard
     BEFORE INSERT ON runtimeMetadata
     WHEN NEW.key = 'settings.agents.defaultAgentProfileId'
       AND trim(NEW.value) <> ''
       AND NOT EXISTS (SELECT 1 FROM agentProfiles WHERE id = trim(NEW.value))
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS defaultAgentProfileUpdateGuard
     BEFORE UPDATE OF value ON runtimeMetadata
     WHEN NEW.key = 'settings.agents.defaultAgentProfileId'
       AND trim(NEW.value) <> ''
       AND NOT EXISTS (SELECT 1 FROM agentProfiles WHERE id = trim(NEW.value))
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
    "CREATE TRIGGER IF NOT EXISTS orchestrationPolicyProfileUpdateGuard
     BEFORE UPDATE OF execution_policy, execution_policy_status, status
     ON orchestrationCoordinatorRuns
     WHEN NEW.execution_policy IS NOT NULL
       AND NEW.status NOT IN ('completed', 'failed', 'stopped')
       AND NEW.execution_policy_status IN ('draft', 'approved')
       AND EXISTS (
         SELECT 1 FROM json_each(json_extract(NEW.execution_policy, '$.stages')) AS stage
         WHERE NOT EXISTS (
           SELECT 1 FROM agentProfiles
           WHERE name = json_extract(stage.value, '$.profile') COLLATE NOCASE
         ) OR EXISTS (
           SELECT 1 FROM json_each(json_extract(stage.value, '$.fallbacks')) AS fallback
           WHERE NOT EXISTS (
             SELECT 1 FROM agentProfiles
             WHERE name = fallback.value COLLATE NOCASE
           )
         )
       )
     BEGIN SELECT RAISE(ABORT, 'agent profile reference does not exist'); END;",
];
