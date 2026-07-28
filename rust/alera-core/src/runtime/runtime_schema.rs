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
        description TEXT NOT NULL DEFAULT '',
        quotaGroup TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS agentProfilesNameIdx ON agentProfiles(name COLLATE NOCASE);",
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
        bindHost TEXT NOT NULL,
        port INTEGER NOT NULL,
        endpointMode TEXT NOT NULL DEFAULT 'loopback',
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
];
