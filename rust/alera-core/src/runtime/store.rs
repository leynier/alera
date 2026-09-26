#[path = "store_legacy_orchestration.rs"]
mod legacy_orchestration;

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::path::Path;
use std::time::Duration;

use anyhow::Result;
use chrono::{DateTime, SecondsFormat, TimeZone, Utc};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

use super::runtime_schema::RUNTIME_SCHEMA;
use super::store_error::RuntimeStoreError;
use super::{harden_sqlite_files, open_private_runtime_file, prepare_private_runtime_directory};
use super::{
    CascadePreview, LinkedReview, MobileAccessSettings, MobileDevice, MobileDevicePermission,
    MobilePairingOffer, Project, ProjectConfig, ProjectConfigMap, ProjectConfigRecord, ProjectKind,
    RuntimeSettings, WorkbenchLayoutRecord, Workspace, WorkspaceKind, WorkspaceRelation,
    WorkspaceStatus, WorkspaceTabRecord, WorkspaceTag,
};

pub const RUNTIME_DATABASE_FILE_NAME: &str = "runtime.sqlite";
pub const LOCAL_HOST_ID: &str = "local";
const RUNTIME_STORE_MAX_CONNECTIONS: u32 = 4;

#[derive(Clone)]
pub struct RuntimeStore {
    pool: SqlitePool,
    pub(super) board_notification_revision: std::sync::Arc<std::sync::atomic::AtomicI64>,
}

impl RuntimeStore {
    /// Inspect an existing owner without creating state or applying migrations.
    pub async fn open_read_only(runtime_dir: &Path) -> Result<Self> {
        let options = SqliteConnectOptions::new()
            .filename(runtime_dir.join(RUNTIME_DATABASE_FILE_NAME))
            .create_if_missing(false)
            .read_only(true);
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect_with(options)
            .await?;
        Ok(Self {
            pool,
            board_notification_revision: Default::default(),
        })
    }

    pub async fn open(runtime_dir: &Path) -> Result<Self> {
        prepare_private_runtime_directory(runtime_dir)?;
        let path = runtime_dir.join(RUNTIME_DATABASE_FILE_NAME);
        open_private_runtime_file(&path)?;
        let options = SqliteConnectOptions::new()
            .filename(&path)
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Normal)
            .busy_timeout(Duration::from_secs(5));
        // SQLite gives every pooled connection its own worker thread. The
        // runtime actor serializes ordinary mutations, while a few background
        // jobs can read concurrently, so the default of ten only leaves idle
        // threads and connection-local caches behind after a burst. A busy
        // timeout lets those writers wait on WAL instead of returning SQLITE_BUSY.
        let pool = SqlitePoolOptions::new()
            .max_connections(RUNTIME_STORE_MAX_CONNECTIONS)
            .connect_with(options)
            .await?;
        let store = RuntimeStore {
            pool,
            board_notification_revision: Default::default(),
        };
        store.migrate().await?;
        store.migrate_orchestration_board().await?;
        harden_sqlite_files(&path)?;
        Ok(store)
    }

    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }

    async fn migrate(&self) -> Result<()> {
        for statement in RUNTIME_SCHEMA {
            sqlx::query(*statement).execute(&self.pool).await?;
        }
        for statement in super::workspace_section_store::SECTION_SCHEMA {
            sqlx::query(*statement).execute(&self.pool).await?;
        }
        for statement in super::project_clone_job_store::PROJECT_CLONE_JOB_SCHEMA {
            sqlx::query(*statement).execute(&self.pool).await?;
        }
        self.migrate_legacy_orchestration_schema().await?;
        for statement in super::orchestration_message_store::ORCHESTRATION_SCHEMA {
            sqlx::query(*statement).execute(&self.pool).await?;
        }
        self.set_metadata(
            "orchestration.schemaVersion",
            super::orchestration_message_store::ORCHESTRATION_SCHEMA_VERSION,
        )
        .await?;
        self.ensure_column("sshTargets", "projectsDir", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "installDir", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "runtimeVersion", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "runtimePlatform", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "runtimeArch", "TEXT")
            .await?;
        self.ensure_column(
            "sshTargets",
            "bootstrapStatus",
            "TEXT NOT NULL DEFAULT 'notInstalled'",
        )
        .await?;
        self.ensure_column("sshTargets", "lastBootstrapAt", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "lastCheckedAt", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "lastError", "TEXT")
            .await?;
        self.ensure_column("workspaces", "isPinned", "INTEGER NOT NULL DEFAULT 0")
            .await?;
        self.ensure_column("workspaces", "isArchived", "INTEGER NOT NULL DEFAULT 0")
            .await?;
        self.ensure_column(
            "mobileAccessSettings",
            "endpointMode",
            "TEXT NOT NULL DEFAULT 'loopback'",
        )
        .await?;
        self.ensure_column(
            "mobileAccessSettings",
            "remoteAccessEnabled",
            "INTEGER NOT NULL DEFAULT 0",
        )
        .await?;
        self.ensure_column(
            "mobileAccessSettings",
            "netbirdEndpoint",
            "TEXT NOT NULL DEFAULT 'ip'",
        )
        .await?;
        self.ensure_column(
            "agentProfiles",
            "launchMode",
            "TEXT NOT NULL DEFAULT 'command'",
        )
        .await?;
        self.ensure_column("agentProfiles", "managedConfig", "TEXT")
            .await?;
        self.ensure_column("agentProfiles", "sortOrder", "INTEGER NOT NULL DEFAULT 0")
            .await?;
        self.ensure_column("agentProfiles", "customPrompt", "TEXT NOT NULL DEFAULT ''")
            .await?;
        self.ensure_column("agentProfiles", "revision", "INTEGER NOT NULL DEFAULT 0")
            .await?;
        self.ensure_agent_profile_new_tab_menu_column().await?;
        // Orchestration tables are created idempotently above, but CREATE TABLE
        // IF NOT EXISTS is a no-op on an existing database, so every column
        // added after the v2 rebuild must also be backfilled here.
        self.ensure_column("orchestrationCoordinatorRuns", "execution_policy", "TEXT")
            .await?;
        self.ensure_column(
            "orchestrationCoordinatorRuns",
            "execution_policy_status",
            "TEXT NOT NULL DEFAULT 'none'",
        )
        .await?;
        self.ensure_column(
            "orchestrationCoordinatorRuns",
            "execution_policy_updated_at",
            "TEXT",
        )
        .await?;
        self.ensure_column("orchestrationTasks", "stage_id", "TEXT")
            .await?;
        self.ensure_column("orchestrationDispatchContexts", "agent_profile", "TEXT")
            .await?;
        self.ensure_column("orchestrationDispatchContexts", "agent_quota_group", "TEXT")
            .await?;
        for statement in super::runtime_schema::AGENT_PROFILE_REFERENCE_TRIGGERS {
            sqlx::query(*statement).execute(&self.pool).await?;
        }
        self.migrate_workspace_checkouts().await?;
        self.migrate_workspace_retirements().await?;
        self.migrate_terminal_lifecycle_operations().await?;
        self.migrate_workspace_terminal_launches().await?;
        self.migrate_workspace_process_jobs().await?;
        self.migrate_automation_shared_workspace_allocations()
            .await?;
        self.migrate_project_automation_dependencies().await?;
        self.migrate_automation_cleanup_attempts().await?;
        self.migrate_automation_precheck_processes().await?;
        self.migrate_owner_automation_prechecks().await?;
        self.migrate_workspace_relocations().await?;
        self.migrate_remote_workspace_relocation_intents().await?;
        self.migrate_remote_relocation_checkout_reservations()
            .await?;
        self.migrate_checkout_relocation_reservations().await?;
        self.migrate_setup_recovery_evidence().await?;
        self.migrate_relocation_setup_receipts().await?;
        self.migrate_relocation_setup_processes().await?;
        self.migrate_relocation_setup_cancellations().await?;
        self.migrate_setup_descendants().await?;
        Ok(())
    }

    pub async fn get_metadata(&self, key: &str) -> Result<Option<String>> {
        let row = sqlx::query("SELECT value FROM runtimeMetadata WHERE key = ?")
            .bind(key)
            .fetch_optional(&self.pool)
            .await?;
        row.map(|row| row.try_get("value"))
            .transpose()
            .map_err(Into::into)
    }

    pub async fn set_metadata(&self, key: &str, value: &str) -> Result<()> {
        sqlx::query(
            "INSERT INTO runtimeMetadata (key, value, updatedAt) VALUES (?, ?, ?) \
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
        )
        .bind(key)
        .bind(value)
        .bind(format_timestamp(Utc::now()))
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn get_workspace_directory(&self) -> Result<Option<String>> {
        self.get_metadata("settings.general.workspaceDirectory")
            .await
    }

    pub async fn set_workspace_directory(&self, path: Option<&str>) -> Result<RuntimeSettings> {
        match path.map(str::trim).filter(|value| !value.is_empty()) {
            Some(value) => {
                self.set_metadata("settings.general.workspaceDirectory", value)
                    .await?;
            }
            None => {
                sqlx::query("DELETE FROM runtimeMetadata WHERE key = ?")
                    .bind("settings.general.workspaceDirectory")
                    .execute(&self.pool)
                    .await?;
            }
        }
        self.runtime_settings().await
    }

    pub async fn rename_workspace(&self, workspace_id: &str, name: &str) -> Result<Workspace> {
        let name = name.trim();
        if name.is_empty() {
            anyhow::bail!(RuntimeStoreError::Message(
                "Workspace name cannot be empty.".to_string(),
            ));
        }
        sqlx::query("UPDATE workspaces SET name = ?, updatedAt = ? WHERE id = ?")
            .bind(name)
            .bind(format_timestamp(Utc::now()))
            .bind(workspace_id)
            .execute(&self.pool)
            .await?;
        self.find_workspace(workspace_id).await?.ok_or_else(|| {
            RuntimeStoreError::Message(format!("Workspace not found: {workspace_id}")).into()
        })
    }

    pub async fn mobile_access_settings(&self) -> Result<MobileAccessSettings> {
        let row = sqlx::query(
            "SELECT enabled, remoteAccessEnabled, bindHost, port, endpointMode, netbirdEndpoint, \
             serverPublicKeyB64, updatedAt \
             FROM mobileAccessSettings WHERE id = 1",
        )
        .fetch_optional(&self.pool)
        .await?;
        match row {
            Some(row) => {
                Ok(super::mobile_access_settings_row::mobile_access_settings_from_row(row)?)
            }
            None => Ok(MobileAccessSettings::default()),
        }
    }

    pub async fn set_mobile_access_settings(
        &self,
        mut settings: MobileAccessSettings,
    ) -> Result<MobileAccessSettings> {
        if settings.bind_host.trim().is_empty() {
            settings.bind_host = MobileAccessSettings::default().bind_host;
        }
        if settings.port <= 0 {
            settings.port = MobileAccessSettings::default().port;
        }
        settings.updated_at = Utc::now();
        sqlx::query(
            "INSERT INTO mobileAccessSettings \
             (id, enabled, remoteAccessEnabled, bindHost, port, endpointMode, netbirdEndpoint, \
             serverPublicKeyB64, updatedAt) \
             VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             enabled = excluded.enabled, remoteAccessEnabled = excluded.remoteAccessEnabled, bindHost = excluded.bindHost, port = excluded.port, \
             endpointMode = excluded.endpointMode, \
             netbirdEndpoint = excluded.netbirdEndpoint, \
             serverPublicKeyB64 = excluded.serverPublicKeyB64, updatedAt = excluded.updatedAt",
        )
        .bind(if settings.enabled { 1_i64 } else { 0_i64 })
        .bind(if settings.remote_access_enabled { 1_i64 } else { 0_i64 })
        .bind(&settings.bind_host)
        .bind(settings.port)
        .bind(settings.endpoint_mode.as_str())
        .bind(settings.netbird_endpoint.as_str())
        .bind(&settings.server_public_key_b64)
        .bind(format_timestamp(settings.updated_at))
        .execute(&self.pool)
        .await?;
        self.mobile_access_settings().await
    }

    pub async fn list_mobile_pairing_offers(&self) -> Result<Vec<MobilePairingOffer>> {
        let rows = sqlx::query(
            "SELECT id, endpoint, secretHash, expectedDeviceName, serverPublicKeyB64, \
             createdAt, expiresAt, claimedDeviceId FROM mobilePairingOffers \
             WHERE claimedDeviceId IS NULL AND expiresAt > ? ORDER BY createdAt DESC",
        )
        .bind(format_timestamp(Utc::now()))
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(mobile_pairing_offer_from_row)
            .collect()
    }

    pub async fn find_mobile_pairing_offer(
        &self,
        offer_id: &str,
    ) -> Result<Option<MobilePairingOffer>> {
        let row = sqlx::query(
            "SELECT id, endpoint, secretHash, expectedDeviceName, serverPublicKeyB64, \
             createdAt, expiresAt, claimedDeviceId FROM mobilePairingOffers WHERE id = ?",
        )
        .bind(offer_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(mobile_pairing_offer_from_row).transpose()
    }

    pub async fn delete_mobile_pairing_offer(&self, offer_id: &str) -> Result<bool> {
        // Claimed offers stay in place as the audit trail of a completed pairing.
        let result =
            sqlx::query("DELETE FROM mobilePairingOffers WHERE id = ? AND claimedDeviceId IS NULL")
                .bind(offer_id)
                .execute(&self.pool)
                .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn upsert_mobile_pairing_offer(
        &self,
        offer: MobilePairingOffer,
    ) -> Result<MobilePairingOffer> {
        sqlx::query(
            "INSERT INTO mobilePairingOffers \
             (id, endpoint, secretHash, expectedDeviceName, serverPublicKeyB64, createdAt, expiresAt, claimedDeviceId) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             endpoint = excluded.endpoint, secretHash = excluded.secretHash, \
             expectedDeviceName = excluded.expectedDeviceName, serverPublicKeyB64 = excluded.serverPublicKeyB64, \
             expiresAt = excluded.expiresAt, claimedDeviceId = excluded.claimedDeviceId",
        )
        .bind(&offer.id)
        .bind(&offer.endpoint)
        .bind(&offer.secret_hash)
        .bind(&offer.expected_device_name)
        .bind(&offer.server_public_key_b64)
        .bind(format_timestamp(offer.created_at))
        .bind(format_timestamp(offer.expires_at))
        .bind(&offer.claimed_device_id)
        .execute(&self.pool)
        .await?;
        Ok(offer)
    }

    pub async fn claim_mobile_pairing_offer(
        &self,
        offer_id: &str,
        secret_hash: &str,
        device: MobileDevice,
    ) -> Result<MobileDevice> {
        let mut tx = self.pool.begin().await?;
        let row = sqlx::query(
            "SELECT id, endpoint, secretHash, expectedDeviceName, serverPublicKeyB64, \
             createdAt, expiresAt, claimedDeviceId FROM mobilePairingOffers WHERE id = ?",
        )
        .bind(offer_id)
        .fetch_optional(&mut *tx)
        .await?;
        let offer = row
            .map(mobile_pairing_offer_from_row)
            .transpose()?
            .ok_or_else(|| RuntimeStoreError::Message("pairing offer not found".to_string()))?;
        if offer.claimed_device_id.is_some() {
            return Err(
                RuntimeStoreError::Message("pairing offer already claimed".to_string()).into(),
            );
        }
        if Utc::now() > offer.expires_at {
            return Err(RuntimeStoreError::Message("pairing offer expired".to_string()).into());
        }
        if offer.secret_hash != secret_hash {
            return Err(RuntimeStoreError::Message("pairing secret is invalid".to_string()).into());
        }
        let result = sqlx::query(
            "UPDATE mobilePairingOffers SET claimedDeviceId = ? \
             WHERE id = ? AND claimedDeviceId IS NULL",
        )
        .bind(&device.id)
        .bind(&offer.id)
        .execute(&mut *tx)
        .await?;
        if result.rows_affected() != 1 {
            return Err(
                RuntimeStoreError::Message("pairing offer already claimed".to_string()).into(),
            );
        }
        sqlx::query(
            "INSERT INTO mobileDevices \
             (id, displayName, tokenHash, publicKeyB64, permission, pairedAt, lastSeenAt, revokedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&device.id)
        .bind(&device.display_name)
        .bind(&device.token_hash)
        .bind(&device.public_key_b64)
        .bind(device.permission.as_str())
        .bind(format_timestamp(device.paired_at))
        .bind(device.last_seen_at.map(format_timestamp))
        .bind(device.revoked_at.map(format_timestamp))
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(device)
    }

    pub async fn list_mobile_devices(&self, include_revoked: bool) -> Result<Vec<MobileDevice>> {
        let rows = if include_revoked {
            sqlx::query(
                "SELECT id, displayName, tokenHash, publicKeyB64, permission, pairedAt, lastSeenAt, revokedAt \
                 FROM mobileDevices ORDER BY pairedAt DESC",
            )
            .fetch_all(&self.pool)
            .await?
        } else {
            sqlx::query(
                "SELECT id, displayName, tokenHash, publicKeyB64, permission, pairedAt, lastSeenAt, revokedAt \
                 FROM mobileDevices WHERE revokedAt IS NULL ORDER BY pairedAt DESC",
            )
            .fetch_all(&self.pool)
            .await?
        };
        rows.into_iter().map(mobile_device_from_row).collect()
    }

    pub async fn find_mobile_device(&self, device_id: &str) -> Result<Option<MobileDevice>> {
        let row = sqlx::query(
            "SELECT id, displayName, tokenHash, publicKeyB64, permission, pairedAt, lastSeenAt, revokedAt \
             FROM mobileDevices WHERE id = ?",
        )
        .bind(device_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(mobile_device_from_row).transpose()
    }

    pub async fn upsert_mobile_device(&self, device: MobileDevice) -> Result<MobileDevice> {
        sqlx::query(
            "INSERT INTO mobileDevices \
             (id, displayName, tokenHash, publicKeyB64, permission, pairedAt, lastSeenAt, revokedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             displayName = excluded.displayName, tokenHash = excluded.tokenHash, publicKeyB64 = excluded.publicKeyB64, \
             permission = excluded.permission, lastSeenAt = excluded.lastSeenAt, \
             revokedAt = COALESCE(mobileDevices.revokedAt, excluded.revokedAt)",
        )
        .bind(&device.id)
        .bind(&device.display_name)
        .bind(&device.token_hash)
        .bind(&device.public_key_b64)
        .bind(device.permission.as_str())
        .bind(format_timestamp(device.paired_at))
        .bind(device.last_seen_at.map(format_timestamp))
        .bind(device.revoked_at.map(format_timestamp))
        .execute(&self.pool)
        .await?;
        Ok(device)
    }

    pub async fn mark_mobile_device_seen_if_active(
        &self,
        device_id: &str,
        seen_at: DateTime<Utc>,
    ) -> Result<Option<MobileDevice>> {
        let mut tx = self.pool.begin().await?;
        let result = sqlx::query(
            "UPDATE mobileDevices SET lastSeenAt = ? WHERE id = ? AND revokedAt IS NULL",
        )
        .bind(format_timestamp(seen_at))
        .bind(device_id)
        .execute(&mut *tx)
        .await?;
        if result.rows_affected() != 1 {
            tx.commit().await?;
            return Ok(None);
        }
        let row = sqlx::query(
            "SELECT id, displayName, tokenHash, publicKeyB64, permission, pairedAt, lastSeenAt, revokedAt \
             FROM mobileDevices WHERE id = ?",
        )
        .bind(device_id)
        .fetch_optional(&mut *tx)
        .await?;
        tx.commit().await?;
        row.map(mobile_device_from_row).transpose()
    }

    pub async fn revoke_mobile_device(&self, device_id: &str) -> Result<()> {
        let now = format_timestamp(Utc::now());
        sqlx::query("UPDATE mobileDevices SET revokedAt = ? WHERE id = ?")
            .bind(now)
            .bind(device_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Permanently remove a revoked device record. Active devices must be
    /// revoked first so accidental hard-deletes do not bypass the soft revoke.
    pub async fn delete_mobile_device(&self, device_id: &str) -> Result<bool> {
        let result =
            sqlx::query("DELETE FROM mobileDevices WHERE id = ? AND revokedAt IS NOT NULL")
                .bind(device_id)
                .execute(&self.pool)
                .await?;
        Ok(result.rows_affected() == 1)
    }

    pub async fn rename_mobile_device(
        &self,
        device_id: &str,
        display_name: &str,
    ) -> Result<Option<MobileDevice>> {
        let result = sqlx::query(
            "UPDATE mobileDevices SET displayName = ? WHERE id = ? AND revokedAt IS NULL",
        )
        .bind(display_name)
        .bind(device_id)
        .execute(&self.pool)
        .await?;
        if result.rows_affected() == 0 {
            return Ok(None);
        }
        self.find_mobile_device(device_id).await
    }

    pub async fn list_projects(&self) -> Result<Vec<Project>> {
        let rows = sqlx::query(
            "SELECT id, name, repoPath, createdAt, updatedAt, kind \
             FROM projects ORDER BY updatedAt DESC, name COLLATE NOCASE ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(project_from_row).collect()
    }

    pub async fn find_project(&self, project_id: &str) -> Result<Option<Project>> {
        let row = sqlx::query(
            "SELECT id, name, repoPath, createdAt, updatedAt, kind FROM projects WHERE id = ?",
        )
        .bind(project_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(project_from_row).transpose()
    }

    pub async fn upsert_project(&self, project: Project) -> Result<Project> {
        sqlx::query(
            "INSERT INTO projects (id, name, repoPath, createdAt, updatedAt, kind) \
             VALUES (?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             name = excluded.name, repoPath = excluded.repoPath, \
             updatedAt = excluded.updatedAt, kind = excluded.kind",
        )
        .bind(&project.id)
        .bind(&project.name)
        .bind(&project.repo_path)
        .bind(format_timestamp(project.created_at))
        .bind(format_timestamp(project.updated_at))
        .bind(project.kind.as_str())
        .execute(&self.pool)
        .await?;
        Ok(project)
    }

    pub async fn register_project_identity(&self, project: Project) -> Result<Project> {
        if project.id.trim().is_empty() || project.repo_path.trim().is_empty() {
            anyhow::bail!("Project identity and checkout path are required");
        }
        sqlx::query("INSERT INTO projects (id, name, repoPath, createdAt, updatedAt, kind) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING")
            .bind(&project.id).bind(&project.name).bind(&project.repo_path)
            .bind(format_timestamp(project.created_at)).bind(format_timestamp(project.updated_at))
            .bind(project.kind.as_str()).execute(&self.pool).await?;
        let stored = self
            .find_project(&project.id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Project disappeared during registration"))?;
        if stored.repo_path != project.repo_path || stored.kind != project.kind {
            anyhow::bail!("Project identity already belongs to another checkout");
        }
        Ok(stored)
    }

    pub async fn remove_project(&self, project_id: &str) -> Result<()> {
        let mut tx = self.pool.begin().await?;
        super::project_automation_dependencies::require_project_automation_idle_in_transaction(
            &mut tx, project_id,
        )
        .await?;
        let workspace_ids: Vec<String> =
            sqlx::query("SELECT id FROM workspaces WHERE projectId = ?")
                .bind(project_id)
                .fetch_all(&mut *tx)
                .await?
                .into_iter()
                .map(|row| row.try_get("id"))
                .collect::<Result<Vec<String>, _>>()?;
        for workspace_id in workspace_ids {
            sqlx::query("DELETE FROM workspaceTabs WHERE workspaceId = ?")
                .bind(&workspace_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("DELETE FROM workbenchLayouts WHERE workspaceId = ?")
                .bind(&workspace_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("DELETE FROM workspaceTagAssignments WHERE workspaceId = ?")
                .bind(&workspace_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("DELETE FROM linkedReviews WHERE workspaceId = ?")
                .bind(&workspace_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query(
                "DELETE FROM workspaceRelations \
                 WHERE parentWorkspaceId = ? OR childWorkspaceId = ?",
            )
            .bind(&workspace_id)
            .bind(&workspace_id)
            .execute(&mut *tx)
            .await?;
        }
        sqlx::query("DELETE FROM workspaces WHERE projectId = ?")
            .bind(project_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM projects WHERE id = ?")
            .bind(project_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM projectConfigs WHERE projectId = ?")
            .bind(project_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM projectCloneJobs WHERE projectId = ?")
            .bind(project_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn find_project_config(&self, project_id: &str) -> Result<Option<ProjectConfig>> {
        let row = sqlx::query("SELECT dataJson FROM projectConfigs WHERE projectId = ?")
            .bind(project_id)
            .fetch_optional(&self.pool)
            .await?;
        row.map(project_config_from_row).transpose()
    }

    pub async fn list_project_configs(&self) -> Result<ProjectConfigMap> {
        let rows = sqlx::query("SELECT projectId, dataJson FROM projectConfigs")
            .fetch_all(&self.pool)
            .await?;
        let mut configs = ProjectConfigMap::new();
        for row in rows {
            let project_id: String = row.try_get("projectId")?;
            configs.insert(project_id, project_config_from_row(row)?);
        }
        Ok(configs)
    }

    pub async fn upsert_project_config(
        &self,
        project_id: &str,
        config: ProjectConfig,
        updated_at: DateTime<Utc>,
    ) -> Result<ProjectConfigRecord> {
        sqlx::query(
            "INSERT INTO projectConfigs (projectId, dataJson, updatedAt) VALUES (?, ?, ?) \
             ON CONFLICT(projectId) DO UPDATE SET dataJson = excluded.dataJson, updatedAt = excluded.updatedAt",
        )
        .bind(project_id)
        .bind(serde_json::to_string(&config)?)
        .bind(format_timestamp(updated_at))
        .execute(&self.pool)
        .await?;
        Ok(ProjectConfigRecord {
            project_id: project_id.to_string(),
            config,
            updated_at,
        })
    }

    pub async fn remove_project_config(&self, project_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM projectConfigs WHERE projectId = ?")
            .bind(project_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn list_workspaces(&self, project_id: &str) -> Result<Vec<Workspace>> {
        let rows = sqlx::query(
            "SELECT id, instanceId, hostId, projectId, name, branch, path, createdAt, updatedAt, \
             kind, status, sourceBranch, reusesExistingBranch, isPinned, isArchived \
             FROM workspaces WHERE projectId = ? AND status = 'active' \
             ORDER BY createdAt ASC, name COLLATE NOCASE ASC",
        )
        .bind(project_id)
        .fetch_all(&self.pool)
        .await?;
        self.workspace_rows(rows).await
    }

    pub async fn list_all_workspaces(&self) -> Result<Vec<Workspace>> {
        let rows = sqlx::query(
            "SELECT id, instanceId, hostId, projectId, name, branch, path, createdAt, updatedAt, \
             kind, status, sourceBranch, reusesExistingBranch, isPinned, isArchived \
             FROM workspaces WHERE status = 'active' \
             ORDER BY projectId ASC, createdAt ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        self.workspace_rows(rows).await
    }

    pub async fn find_workspace(&self, workspace_id: &str) -> Result<Option<Workspace>> {
        let row = sqlx::query(
            "SELECT id, instanceId, hostId, projectId, name, branch, path, createdAt, updatedAt, \
             kind, status, sourceBranch, reusesExistingBranch, isPinned, isArchived FROM workspaces WHERE id = ?",
        )
        .bind(workspace_id)
        .fetch_optional(&self.pool)
        .await?;
        match row {
            Some(row) => Ok(Some(self.workspace_from_row(row).await?)),
            None => Ok(None),
        }
    }

    pub async fn upsert_workspace(&self, workspace: Workspace) -> Result<Workspace> {
        self.write_workspace(workspace, true, None).await
    }

    pub async fn insert_workspace(&self, workspace: Workspace) -> Result<Workspace> {
        self.write_workspace(workspace, false, None).await
    }

    pub async fn insert_workspace_with_repository(
        &self,
        workspace: Workspace,
        repository_path: &str,
    ) -> Result<Workspace> {
        if workspace.kind != WorkspaceKind::Linked || repository_path.trim().is_empty() {
            anyhow::bail!("A linked workspace and its repository path are required");
        }
        self.write_workspace(workspace, false, Some(repository_path))
            .await
    }

    async fn write_workspace(
        &self,
        mut workspace: Workspace,
        allow_update: bool,
        repository_path: Option<&str>,
    ) -> Result<Workspace> {
        if workspace.instance_id.trim().is_empty() {
            workspace.instance_id = Uuid::new_v4().to_string();
        }
        if workspace.host_id.trim().is_empty() {
            workspace.host_id = LOCAL_HOST_ID.to_string();
        }
        let checkout_path = self.checkout_path_for_write(&workspace).await?;
        let mut tx = self.pool.begin().await?;
        super::checkout_store::bind_workspace_checkout(&mut tx, &workspace, &checkout_path).await?;
        if let Some(repository_path) = repository_path {
            let result = sqlx::query("UPDATE repositoryCheckouts SET repositoryPath = ? WHERE id = (SELECT checkoutId FROM workspaceCheckoutBindings WHERE workspaceId = ?) AND (repositoryPath IS NULL OR repositoryPath = ?)")
                .bind(repository_path).bind(&workspace.id).bind(repository_path).execute(&mut *tx).await?;
            if result.rows_affected() != 1 {
                anyhow::bail!("The linked checkout already belongs to a different repository");
            }
        }
        super::workspace_record_write::write_workspace_record(&mut tx, &workspace, allow_update)
            .await?;
        tx.commit().await?;
        self.find_workspace(&workspace.id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "workspace not found after upsert: {}",
                workspace.id
            )))
        })
    }

    pub async fn remove_workspace(&self, workspace_id: &str, cascade_tabs: bool) -> Result<()> {
        self.remove_workspace_with_receipt(workspace_id, cascade_tabs, None, None, None)
            .await
    }

    pub(super) async fn remove_workspace_with_receipt(
        &self,
        workspace_id: &str,
        cascade_tabs: bool,
        receipt: Option<&Workspace>,
        automation_run: Option<&super::AutomationRun>,
        remote_automation: Option<&super::RemoteAutomationCleanup>,
    ) -> Result<()> {
        let mut tx = self.pool.begin().await?;
        if let Some(workspace) = receipt {
            if let Some(scope) = remote_automation {
                super::remote_automation_cleanup::validate(&mut tx, scope, workspace).await?;
            }
            if let Some(run) = automation_run {
                super::automation_shared_workspace_cleanup::validate_cleanup(
                    &mut tx, run, workspace,
                )
                .await?;
            }
            let inserted = sqlx::query("INSERT INTO workspaceRetirements (workspaceId, instanceId, workspaceJson) SELECT id, instanceId, ? FROM workspaces WHERE id = ? AND instanceId = ? AND projectId = ? AND hostId = ? AND path = ?")
                .bind(serde_json::to_string(workspace)?).bind(workspace_id).bind(&workspace.instance_id)
                .bind(&workspace.project_id).bind(&workspace.host_id).bind(&workspace.path)
                .execute(&mut *tx).await?;
            if inserted.rows_affected() != 1 {
                anyhow::bail!("Workspace identity or location changed before retirement");
            }
        }
        if cascade_tabs {
            sqlx::query("DELETE FROM workspaceTabs WHERE workspaceId = ?")
                .bind(workspace_id)
                .execute(&mut *tx)
                .await?;
        }
        sqlx::query("DELETE FROM linkedReviews WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM workbenchLayouts WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM workspaceTagAssignments WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "DELETE FROM workspaceRelations WHERE parentWorkspaceId = ? OR childWorkspaceId = ?",
        )
        .bind(workspace_id)
        .bind(workspace_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM workspaces WHERE id = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn remove_workspaces_for_project(&self, project_id: &str) -> Result<()> {
        let workspaces = self.list_workspaces(project_id).await?;
        for workspace in workspaces {
            self.remove_workspace(&workspace.id, true).await?;
        }
        Ok(())
    }

    pub async fn list_workspace_tabs(&self, workspace_id: &str) -> Result<Vec<WorkspaceTabRecord>> {
        let rows = sqlx::query(
            "SELECT id, workspaceId, kind, title, createdAt, updatedAt, payloadJson \
             FROM workspaceTabs WHERE workspaceId = ? ORDER BY createdAt ASC",
        )
        .bind(workspace_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(tab_from_row).collect()
    }

    pub async fn terminal_tab_counts_by_workspace(&self) -> Result<BTreeMap<String, i64>> {
        let rows = sqlx::query(
            "SELECT workspaceId, COUNT(*) AS terminalCount FROM workspaceTabs \
             WHERE kind = 'terminal' GROUP BY workspaceId",
        )
        .fetch_all(&self.pool)
        .await?;
        let mut counts = BTreeMap::new();
        for row in rows {
            counts.insert(
                row.try_get::<String, _>("workspaceId")?,
                row.try_get::<i64, _>("terminalCount")?,
            );
        }
        Ok(counts)
    }

    pub async fn workspace_tab_titles(&self) -> Result<BTreeMap<String, String>> {
        let rows = sqlx::query("SELECT id, title FROM workspaceTabs")
            .fetch_all(&self.pool)
            .await?;
        let mut titles = BTreeMap::new();
        for row in rows {
            titles.insert(
                row.try_get::<String, _>("id")?,
                row.try_get::<String, _>("title")?,
            );
        }
        Ok(titles)
    }

    pub async fn find_workspace_tab(&self, tab_id: &str) -> Result<Option<WorkspaceTabRecord>> {
        let row = sqlx::query(
            "SELECT id, workspaceId, kind, title, createdAt, updatedAt, payloadJson \
             FROM workspaceTabs WHERE id = ?",
        )
        .bind(tab_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(tab_from_row).transpose()
    }

    pub async fn upsert_workspace_tab(
        &self,
        tab: WorkspaceTabRecord,
    ) -> Result<WorkspaceTabRecord> {
        self.write_workspace_tab(tab, true).await
    }

    pub async fn insert_workspace_tab(
        &self,
        tab: WorkspaceTabRecord,
    ) -> Result<WorkspaceTabRecord> {
        self.write_workspace_tab(tab, false).await
    }

    async fn write_workspace_tab(
        &self,
        mut tab: WorkspaceTabRecord,
        allow_update: bool,
    ) -> Result<WorkspaceTabRecord> {
        if tab.payload.is_null() {
            tab.payload = serde_json::json!({});
        }
        let result = sqlx::query(
            "INSERT INTO workspaceTabs (id, workspaceId, kind, title, createdAt, updatedAt, payloadJson) \
             VALUES (?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             workspaceId = excluded.workspaceId, kind = excluded.kind, title = excluded.title, \
             updatedAt = excluded.updatedAt, payloadJson = excluded.payloadJson WHERE ?",
        )
        .bind(&tab.id)
        .bind(&tab.workspace_id)
        .bind(&tab.kind)
        .bind(&tab.title)
        .bind(format_timestamp(tab.created_at))
        .bind(format_timestamp(tab.updated_at))
        .bind(serde_json::to_string(&tab.payload)?)
        .bind(allow_update)
        .execute(&self.pool)
        .await?;
        if result.rows_affected() == 0 {
            anyhow::bail!("Tab identity already exists; no state was replaced");
        }
        Ok(tab)
    }

    pub async fn rename_workspace_tab(
        &self,
        tab_id: &str,
        title: &str,
    ) -> Result<WorkspaceTabRecord> {
        let title = title.trim();
        if title.is_empty() {
            anyhow::bail!(RuntimeStoreError::Message(
                "Tab title cannot be empty.".to_string(),
            ));
        }
        let mut tab = self.find_workspace_tab(tab_id).await?.ok_or_else(|| {
            RuntimeStoreError::Message(format!("Workspace tab not found: {tab_id}"))
        })?;
        tab.title = title.to_string();
        if !tab.payload.is_object() {
            tab.payload = serde_json::json!({});
        }
        tab.payload["agentTitleSource"] = serde_json::json!("manual");
        tab.payload["agentTitleRevision"] = serde_json::json!(uuid::Uuid::new_v4().to_string());
        tab.payload["agentTitleStatus"] = serde_json::json!("idle");
        tab.updated_at = Utc::now();
        if !tab.payload.is_object() {
            tab.payload = serde_json::json!({});
        }
        tab.payload
            .as_object_mut()
            .expect("tab payload was normalized to an object")
            .insert("manualTitle".to_string(), serde_json::json!(true));
        self.upsert_workspace_tab(tab).await
    }

    pub async fn find_linked_review(&self, workspace_id: &str) -> Result<Option<LinkedReview>> {
        let row = sqlx::query(
            "SELECT workspaceId, dismissed, provider, number, url, linkedAt \
             FROM linkedReviews WHERE workspaceId = ?",
        )
        .bind(workspace_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(linked_review_from_row).transpose()
    }

    pub async fn upsert_linked_review(&self, review: LinkedReview) -> Result<LinkedReview> {
        sqlx::query(
            "INSERT INTO linkedReviews (workspaceId, dismissed, provider, number, url, linkedAt) \
             VALUES (?, ?, ?, ?, ?, ?) \
             ON CONFLICT(workspaceId) DO UPDATE SET \
             dismissed = excluded.dismissed, provider = excluded.provider, \
             number = excluded.number, url = excluded.url, linkedAt = excluded.linkedAt",
        )
        .bind(&review.workspace_id)
        .bind(i64::from(review.dismissed))
        .bind(&review.provider)
        .bind(review.number)
        .bind(&review.url)
        .bind(format_timestamp(review.linked_at))
        .execute(&self.pool)
        .await?;
        Ok(review)
    }

    pub async fn remove_linked_review(&self, workspace_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM linkedReviews WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn remove_workspace_tabs_for_workspace(&self, workspace_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM workspaceTabs WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Removes every tab and the layout for a workspace while keeping the
    /// workspace, branch, and files. Used by explicit tab-clear flows
    /// (`tab.removeForWorkspace`); sleep and archive terminate sessions but
    /// preserve tab records so agent sessions can resume on reopen.
    pub async fn remove_workspace_tabs(&self, workspace_id: &str) -> Result<()> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("DELETE FROM workspaceTabs WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM workbenchLayouts WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn find_workbench_layout(
        &self,
        workspace_id: &str,
    ) -> Result<Option<WorkbenchLayoutRecord>> {
        let row =
            sqlx::query("SELECT workspaceId, dataJson FROM workbenchLayouts WHERE workspaceId = ?")
                .bind(workspace_id)
                .fetch_optional(&self.pool)
                .await?;
        row.map(layout_from_row).transpose()
    }

    pub async fn upsert_workbench_layout(
        &self,
        layout: WorkbenchLayoutRecord,
    ) -> Result<WorkbenchLayoutRecord> {
        sqlx::query(
            "INSERT INTO workbenchLayouts (workspaceId, dataJson) VALUES (?, ?) \
             ON CONFLICT(workspaceId) DO UPDATE SET dataJson = excluded.dataJson",
        )
        .bind(&layout.workspace_id)
        .bind(serde_json::to_string(&layout.data)?)
        .execute(&self.pool)
        .await?;
        Ok(layout)
    }

    pub async fn remove_workbench_layout(&self, workspace_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM workbenchLayouts WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn list_tags(&self) -> Result<Vec<WorkspaceTag>> {
        let rows = sqlx::query(
            "SELECT id, name, color, createdAt, updatedAt FROM workspaceTags \
             ORDER BY name COLLATE NOCASE ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(tag_from_row).collect()
    }

    pub async fn upsert_tag(&self, tag: WorkspaceTag) -> Result<WorkspaceTag> {
        // Tag names are unique (COLLATE NOCASE). Callers mint a fresh id per
        // create, so a duplicate name must reuse the existing row instead of
        // tripping the unique name index.
        if let Some(row) = sqlx::query(
            "SELECT id, name, color, createdAt, updatedAt FROM workspaceTags \
             WHERE name = ? COLLATE NOCASE AND id != ?",
        )
        .bind(&tag.name)
        .bind(&tag.id)
        .fetch_optional(&self.pool)
        .await?
        {
            return tag_from_row(row);
        }
        sqlx::query(
            "INSERT INTO workspaceTags (id, name, color, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET name = excluded.name, color = excluded.color, updatedAt = excluded.updatedAt",
        )
        .bind(&tag.id)
        .bind(&tag.name)
        .bind(&tag.color)
        .bind(format_timestamp(tag.created_at))
        .bind(format_timestamp(tag.updated_at))
        .execute(&self.pool)
        .await?;
        Ok(tag)
    }

    pub async fn remove_tag(&self, tag_id: &str) -> Result<()> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("DELETE FROM workspaceTagAssignments WHERE tagId = ?")
            .bind(tag_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM workspaceTags WHERE id = ?")
            .bind(tag_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn assign_tag(&self, workspace_id: &str, tag_id: &str) -> Result<()> {
        sqlx::query(
            "INSERT OR IGNORE INTO workspaceTagAssignments (workspaceId, tagId) VALUES (?, ?)",
        )
        .bind(workspace_id)
        .bind(tag_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn unassign_tag(&self, workspace_id: &str, tag_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM workspaceTagAssignments WHERE workspaceId = ? AND tagId = ?")
            .bind(workspace_id)
            .bind(tag_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn set_workspace_tags(
        &self,
        workspace_id: &str,
        tag_ids: &[String],
    ) -> Result<Workspace> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("DELETE FROM workspaceTagAssignments WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        for tag_id in tag_ids {
            sqlx::query(
                "INSERT OR IGNORE INTO workspaceTagAssignments (workspaceId, tagId) VALUES (?, ?)",
            )
            .bind(workspace_id)
            .bind(tag_id)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        self.find_workspace(workspace_id).await?.ok_or_else(|| {
            RuntimeStoreError::Message(format!("Workspace not found: {workspace_id}")).into()
        })
    }

    pub async fn list_relations(&self) -> Result<Vec<WorkspaceRelation>> {
        let rows = sqlx::query(
            "SELECT id, parentWorkspaceId, parentInstanceId, childWorkspaceId, childInstanceId, createdAt \
             FROM workspaceRelations ORDER BY createdAt ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(relation_from_row).collect()
    }

    pub async fn link_workspaces(
        &self,
        parent_workspace_id: &str,
        child_workspace_id: &str,
    ) -> Result<WorkspaceRelation> {
        if parent_workspace_id == child_workspace_id {
            return Err(RuntimeStoreError::Message(
                "Workspace cannot be related to itself".to_string(),
            )
            .into());
        }
        let parent = self
            .find_workspace(parent_workspace_id)
            .await?
            .ok_or_else(|| RuntimeStoreError::Message("Parent workspace not found".to_string()))?;
        let child = self
            .find_workspace(child_workspace_id)
            .await?
            .ok_or_else(|| RuntimeStoreError::Message("Child workspace not found".to_string()))?;
        if self
            .descendant_ids(child_workspace_id)
            .await?
            .contains(parent_workspace_id)
        {
            return Err(RuntimeStoreError::Message(
                "Workspace relation would create a cycle".to_string(),
            )
            .into());
        }
        let existing_parent: Option<String> = sqlx::query(
            "SELECT parentWorkspaceId FROM workspaceRelations WHERE childWorkspaceId = ?",
        )
        .bind(child_workspace_id)
        .fetch_optional(&self.pool)
        .await?
        .map(|row| row.try_get("parentWorkspaceId"))
        .transpose()?;
        if existing_parent
            .as_deref()
            .is_some_and(|existing| existing != parent_workspace_id)
        {
            return Err(RuntimeStoreError::Message(
                "Child workspace already has a parent".to_string(),
            )
            .into());
        }
        let now = Utc::now();
        let relation = WorkspaceRelation {
            id: existing_relation_id(&self.pool, parent_workspace_id, child_workspace_id)
                .await?
                .unwrap_or_else(|| Uuid::new_v4().to_string()),
            parent_workspace_id: parent.id,
            parent_instance_id: parent.instance_id,
            child_workspace_id: child.id,
            child_instance_id: child.instance_id,
            created_at: now,
        };
        sqlx::query(
            "INSERT OR IGNORE INTO workspaceRelations \
             (id, parentWorkspaceId, parentInstanceId, childWorkspaceId, childInstanceId, createdAt) \
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(&relation.id)
        .bind(&relation.parent_workspace_id)
        .bind(&relation.parent_instance_id)
        .bind(&relation.child_workspace_id)
        .bind(&relation.child_instance_id)
        .bind(format_timestamp(relation.created_at))
        .execute(&self.pool)
        .await?;
        Ok(relation)
    }

    pub async fn unlink_workspaces(
        &self,
        parent_workspace_id: &str,
        child_workspace_id: &str,
    ) -> Result<()> {
        sqlx::query(
            "DELETE FROM workspaceRelations WHERE parentWorkspaceId = ? AND childWorkspaceId = ?",
        )
        .bind(parent_workspace_id)
        .bind(child_workspace_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn cascade_preview(
        &self,
        root_workspace_ids: &[String],
        tag_ids: &[String],
        include_descendants: bool,
        include_tags: bool,
    ) -> Result<CascadePreview> {
        let mut ids = BTreeSet::<String>::new();
        for id in root_workspace_ids {
            ids.insert(id.clone());
            if include_descendants {
                ids.extend(self.descendant_ids(id).await?);
            }
        }
        if include_tags {
            for tag_id in tag_ids {
                let rows =
                    sqlx::query("SELECT workspaceId FROM workspaceTagAssignments WHERE tagId = ?")
                        .bind(tag_id)
                        .fetch_all(&self.pool)
                        .await?;
                for row in rows {
                    ids.insert(row.try_get("workspaceId")?);
                }
            }
        }
        Ok(CascadePreview {
            workspace_ids: ids.into_iter().collect(),
        })
    }

    async fn workspace_rows(&self, rows: Vec<sqlx::sqlite::SqliteRow>) -> Result<Vec<Workspace>> {
        let mut workspaces = Vec::with_capacity(rows.len());
        for row in rows {
            workspaces.push(self.workspace_from_row(row).await?);
        }
        Ok(workspaces)
    }

    async fn workspace_from_row(&self, row: sqlx::sqlite::SqliteRow) -> Result<Workspace> {
        let id: String = row.try_get("id")?;
        let tag_ids = self.tag_ids_for_workspace(&id).await?;
        let tag_names = self.tag_names_for_workspace(&id).await?;
        let parent_workspace_id = sqlx::query(
            "SELECT parentWorkspaceId FROM workspaceRelations WHERE childWorkspaceId = ?",
        )
        .bind(&id)
        .fetch_optional(&self.pool)
        .await?
        .map(|row| row.try_get("parentWorkspaceId"))
        .transpose()?;
        let child_count: i64 = sqlx::query(
            "SELECT COUNT(*) AS childCount FROM workspaceRelations WHERE parentWorkspaceId = ?",
        )
        .bind(&id)
        .fetch_one(&self.pool)
        .await?
        .try_get("childCount")?;
        Ok(Workspace {
            id: id.clone(),
            instance_id: row.try_get("instanceId")?,
            host_id: row.try_get("hostId")?,
            project_id: row.try_get("projectId")?,
            name: row.try_get("name")?,
            branch: empty_to_none(row.try_get("branch")?),
            path: row.try_get("path")?,
            created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
            updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
            kind: WorkspaceKind::from_db(row.try_get::<String, _>("kind")?.as_str()),
            status: WorkspaceStatus::from_db(row.try_get::<String, _>("status")?.as_str()),
            source_branch: empty_to_none(row.try_get("sourceBranch")?),
            reuses_existing_branch: row.try_get::<i64, _>("reusesExistingBranch")? == 1,
            is_pinned: row.try_get::<i64, _>("isPinned")? == 1,
            is_archived: row.try_get::<i64, _>("isArchived").unwrap_or(0) == 1,
            tag_ids,
            tag_names,
            parent_workspace_id,
            section_id: self.workspace_section_id(&id).await?,
            child_count,
        })
    }

    async fn tag_ids_for_workspace(&self, workspace_id: &str) -> Result<Vec<String>> {
        let rows = sqlx::query(
            "SELECT tagId FROM workspaceTagAssignments WHERE workspaceId = ? ORDER BY tagId ASC",
        )
        .bind(workspace_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| row.try_get("tagId"))
            .collect::<Result<Vec<String>, _>>()
            .map_err(Into::into)
    }

    async fn tag_names_for_workspace(&self, workspace_id: &str) -> Result<Vec<String>> {
        let rows = sqlx::query(
            "SELECT tags.name AS tagName \
             FROM workspaceTagAssignments assignments \
             JOIN workspaceTags tags ON tags.id = assignments.tagId \
             WHERE assignments.workspaceId = ? \
             ORDER BY tags.name COLLATE NOCASE ASC",
        )
        .bind(workspace_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| row.try_get("tagName"))
            .collect::<Result<Vec<String>, _>>()
            .map_err(Into::into)
    }

    async fn descendant_ids(&self, workspace_id: &str) -> Result<BTreeSet<String>> {
        let mut seen = BTreeSet::<String>::new();
        let mut queue = VecDeque::<String>::from([workspace_id.to_string()]);
        while let Some(parent) = queue.pop_front() {
            let rows = sqlx::query(
                "SELECT childWorkspaceId FROM workspaceRelations WHERE parentWorkspaceId = ?",
            )
            .bind(parent)
            .fetch_all(&self.pool)
            .await?;
            for row in rows {
                let child: String = row.try_get("childWorkspaceId")?;
                if seen.insert(child.clone()) {
                    queue.push_back(child);
                }
            }
        }
        Ok(seen)
    }
}

fn project_from_row(row: sqlx::sqlite::SqliteRow) -> Result<Project> {
    Ok(Project {
        id: row.try_get("id")?,
        name: row.try_get("name")?,
        repo_path: row.try_get("repoPath")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
        kind: ProjectKind::from_db(row.try_get::<String, _>("kind")?.as_str()),
    })
}

pub(crate) fn tab_from_row(row: sqlx::sqlite::SqliteRow) -> Result<WorkspaceTabRecord> {
    let payload_json: String = row.try_get("payloadJson")?;
    Ok(WorkspaceTabRecord {
        id: row.try_get("id")?,
        workspace_id: row.try_get("workspaceId")?,
        kind: row.try_get("kind")?,
        title: row.try_get("title")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
        payload: serde_json::from_str(&payload_json).unwrap_or_else(|_| serde_json::json!({})),
    })
}

fn linked_review_from_row(row: sqlx::sqlite::SqliteRow) -> Result<LinkedReview> {
    let dismissed: i64 = row.try_get("dismissed")?;
    Ok(LinkedReview {
        workspace_id: row.try_get("workspaceId")?,
        dismissed: dismissed != 0,
        provider: row.try_get("provider")?,
        number: row.try_get("number")?,
        url: row.try_get("url")?,
        linked_at: parse_timestamp(row.try_get::<String, _>("linkedAt")?.as_str()),
    })
}

fn layout_from_row(row: sqlx::sqlite::SqliteRow) -> Result<WorkbenchLayoutRecord> {
    let data_json: String = row.try_get("dataJson")?;
    Ok(WorkbenchLayoutRecord {
        workspace_id: row.try_get("workspaceId")?,
        data: serde_json::from_str(&data_json).unwrap_or_else(|_| serde_json::json!({})),
    })
}

fn project_config_from_row(row: sqlx::sqlite::SqliteRow) -> Result<ProjectConfig> {
    let data_json: String = row.try_get("dataJson")?;
    Ok(serde_json::from_str(&data_json).unwrap_or_default())
}

fn tag_from_row(row: sqlx::sqlite::SqliteRow) -> Result<WorkspaceTag> {
    Ok(WorkspaceTag {
        id: row.try_get("id")?,
        name: row.try_get("name")?,
        color: row.try_get("color")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
    })
}

fn relation_from_row(row: sqlx::sqlite::SqliteRow) -> Result<WorkspaceRelation> {
    Ok(WorkspaceRelation {
        id: row.try_get("id")?,
        parent_workspace_id: row.try_get("parentWorkspaceId")?,
        parent_instance_id: row.try_get("parentInstanceId")?,
        child_workspace_id: row.try_get("childWorkspaceId")?,
        child_instance_id: row.try_get("childInstanceId")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
    })
}

fn mobile_device_from_row(row: sqlx::sqlite::SqliteRow) -> Result<MobileDevice> {
    let last_seen_at = row
        .try_get::<Option<String>, _>("lastSeenAt")?
        .map(|value| parse_timestamp(&value));
    let revoked_at = row
        .try_get::<Option<String>, _>("revokedAt")?
        .map(|value| parse_timestamp(&value));
    Ok(MobileDevice {
        id: row.try_get("id")?,
        display_name: row.try_get("displayName")?,
        token_hash: row.try_get("tokenHash")?,
        public_key_b64: row.try_get("publicKeyB64")?,
        permission: MobileDevicePermission::from_db(
            row.try_get::<String, _>("permission")?.as_str(),
        ),
        paired_at: parse_timestamp(row.try_get::<String, _>("pairedAt")?.as_str()),
        last_seen_at,
        revoked_at,
    })
}

fn mobile_pairing_offer_from_row(row: sqlx::sqlite::SqliteRow) -> Result<MobilePairingOffer> {
    Ok(MobilePairingOffer {
        id: row.try_get("id")?,
        endpoint: row.try_get("endpoint")?,
        secret_hash: row.try_get("secretHash")?,
        expected_device_name: row.try_get("expectedDeviceName")?,
        server_public_key_b64: row.try_get("serverPublicKeyB64")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        expires_at: parse_timestamp(row.try_get::<String, _>("expiresAt")?.as_str()),
        claimed_device_id: row.try_get("claimedDeviceId")?,
    })
}

async fn existing_relation_id(
    pool: &SqlitePool,
    parent_workspace_id: &str,
    child_workspace_id: &str,
) -> Result<Option<String>> {
    sqlx::query(
        "SELECT id FROM workspaceRelations WHERE parentWorkspaceId = ? AND childWorkspaceId = ?",
    )
    .bind(parent_workspace_id)
    .bind(child_workspace_id)
    .fetch_optional(pool)
    .await?
    .map(|row| row.try_get("id"))
    .transpose()
    .map_err(Into::into)
}

pub fn format_timestamp(value: DateTime<Utc>) -> String {
    value.to_rfc3339_opts(SecondsFormat::Millis, true)
}

pub fn parse_timestamp(value: &str) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(value)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc.timestamp_opt(0, 0).single().expect("epoch is valid"))
}

fn empty_to_none(value: Option<String>) -> Option<String> {
    value.filter(|v| !v.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::super::{
        SshAuthKind, SshBootstrapStatus, SshTarget, SshTargetBootstrapStateUpdate,
        SshTargetLastStatus,
    };
    use super::*;

    #[tokio::test]
    async fn connection_pool_is_bounded_for_sqlite_worker_threads() {
        let (_dir, store) = store().await;

        assert_eq!(
            store.pool.options().get_max_connections(),
            RUNTIME_STORE_MAX_CONNECTIONS
        );
    }

    async fn store() -> (tempfile::TempDir, RuntimeStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        (dir, store)
    }

    fn project(id: &str) -> Project {
        let now = Utc::now();
        Project {
            id: id.to_string(),
            name: id.to_string(),
            repo_path: format!("/tmp/{id}"),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        }
    }

    fn workspace(id: &str, project_id: &str) -> Workspace {
        let now = Utc::now();
        Workspace {
            id: id.to_string(),
            instance_id: format!("inst-{id}"),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: project_id.to_string(),
            name: id.to_string(),
            branch: Some("main".to_string()),
            path: format!("/tmp/{project_id}/{id}"),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            is_archived: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        }
    }

    fn ssh_target(id: &str) -> SshTarget {
        let now = Utc::now();
        SshTarget {
            id: id.to_string(),
            alias: id.to_string(),
            host: format!("{id}.example.test"),
            port: 22,
            username: "alera".to_string(),
            platform: None,
            arch: None,
            auth_kind: SshAuthKind::Agent,
            created_at: now,
            updated_at: now,
            last_status: None,
            install_dir: None,
            projects_dir: None,
            runtime_version: None,
            runtime_platform: None,
            runtime_arch: None,
            bootstrap_status: SshBootstrapStatus::NotInstalled,
            last_bootstrap_at: None,
            last_checked_at: None,
            last_error: None,
        }
    }

    #[tokio::test]
    async fn workspace_relations_prevent_cycles() {
        let (_dir, store) = store().await;
        store.upsert_project(project("p")).await.unwrap();
        store.upsert_workspace(workspace("a", "p")).await.unwrap();
        store.upsert_workspace(workspace("b", "p")).await.unwrap();
        store.link_workspaces("a", "b").await.unwrap();
        let error = store.link_workspaces("b", "a").await.unwrap_err();
        assert!(error.to_string().contains("cycle"));
    }

    #[tokio::test]
    async fn cascade_preview_combines_descendants_and_tags() {
        let (_dir, store) = store().await;
        store.upsert_project(project("p")).await.unwrap();
        store.upsert_workspace(workspace("a", "p")).await.unwrap();
        store.upsert_workspace(workspace("b", "p")).await.unwrap();
        store.upsert_workspace(workspace("c", "p")).await.unwrap();
        store.link_workspaces("a", "b").await.unwrap();
        let now = Utc::now();
        store
            .upsert_tag(WorkspaceTag {
                id: "tag".to_string(),
                name: "Review".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        store.assign_tag("c", "tag").await.unwrap();
        let preview = store
            .cascade_preview(&["a".to_string()], &["tag".to_string()], true, true)
            .await
            .unwrap();
        assert_eq!(preview.workspace_ids, vec!["a", "b", "c"]);
    }

    #[tokio::test]
    async fn upsert_tag_reuses_existing_row_for_duplicate_name() {
        let (_dir, store) = store().await;
        let now = Utc::now();
        let original = store
            .upsert_tag(WorkspaceTag {
                id: "tag-1".to_string(),
                name: "Review".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        let duplicate = store
            .upsert_tag(WorkspaceTag {
                id: "tag-2".to_string(),
                name: "review".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();

        assert_eq!(duplicate.id, original.id);
        assert_eq!(duplicate.name, "Review");
        let tags = store.list_tags().await.unwrap();
        assert_eq!(tags.len(), 1);
    }

    #[tokio::test]
    async fn workspaces_include_tag_ids_and_names() {
        let (_dir, store) = store().await;
        store.upsert_project(project("p")).await.unwrap();
        store.upsert_workspace(workspace("w", "p")).await.unwrap();
        let now = Utc::now();
        store
            .upsert_tag(WorkspaceTag {
                id: "tag-review".to_string(),
                name: "Review".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        store
            .upsert_tag(WorkspaceTag {
                id: "tag-mobile".to_string(),
                name: "Mobile".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        store.assign_tag("w", "tag-review").await.unwrap();
        store.assign_tag("w", "tag-mobile").await.unwrap();

        let workspaces = store.list_workspaces("p").await.unwrap();

        assert_eq!(workspaces[0].tag_ids, vec!["tag-mobile", "tag-review"]);
        assert_eq!(workspaces[0].tag_names, vec!["Mobile", "Review"]);
    }

    #[tokio::test]
    async fn metadata_round_trips_values() {
        let (_dir, store) = store().await;
        assert_eq!(store.get_metadata("migration").await.unwrap(), None);

        store.set_metadata("migration", "done").await.unwrap();
        assert_eq!(
            store.get_metadata("migration").await.unwrap(),
            Some("done".to_string())
        );
    }

    #[tokio::test]
    async fn ssh_target_upsert_preserves_runtime_state_and_updates_install_dir() {
        let (_dir, store) = store().await;
        store.upsert_ssh_target(ssh_target("remote")).await.unwrap();
        let installed = store
            .update_ssh_target_bootstrap_state(
                "remote",
                SshTargetBootstrapStateUpdate {
                    status: SshBootstrapStatus::Installed,
                    install_dir: Some("/home/alera/.alera/runtime"),
                    runtime_version: Some("1.2.3"),
                    runtime_platform: Some("linux"),
                    runtime_arch: Some("x64"),
                    last_error: None,
                },
            )
            .await
            .unwrap();
        assert_eq!(installed.bootstrap_status, SshBootstrapStatus::Installed);

        let mut updated = ssh_target("remote");
        updated.host = "renamed.example.test".to_string();
        let cleared = store.upsert_ssh_target(updated).await.unwrap();

        assert_eq!(cleared.host, "renamed.example.test");
        assert_eq!(cleared.bootstrap_status, SshBootstrapStatus::Installed);
        assert_eq!(cleared.runtime_version.as_deref(), Some("1.2.3"));
        assert_eq!(cleared.install_dir, None);

        let mut updated = cleared;
        updated.install_dir = Some("/custom/alera/runtime".to_string());
        let updated = store.upsert_ssh_target(updated).await.unwrap();

        assert_eq!(updated.host, "renamed.example.test");
        assert_eq!(updated.bootstrap_status, SshBootstrapStatus::Installed);
        assert_eq!(updated.runtime_version.as_deref(), Some("1.2.3"));
        assert_eq!(
            updated.install_dir.as_deref(),
            Some("/custom/alera/runtime")
        );
    }

    #[tokio::test]
    async fn mark_ssh_target_checked_stamps_last_status_and_checked_at() {
        let (_dir, store) = store().await;
        store.upsert_ssh_target(ssh_target("remote")).await.unwrap();

        let checked = store
            .mark_ssh_target_checked("remote", SshTargetLastStatus::RuntimeReady)
            .await
            .unwrap();

        assert_eq!(checked.last_status.as_deref(), Some("runtimeReady"));
        assert!(checked.last_checked_at.is_some());
        assert!(checked.updated_at >= checked.created_at);

        let missing = store
            .mark_ssh_target_checked("missing", SshTargetLastStatus::Unreachable)
            .await
            .unwrap_err();
        assert!(missing
            .to_string()
            .contains("ssh target not found: missing"));
    }

    #[tokio::test]
    async fn remove_ssh_target_rejects_missing_id_and_deletes_existing() {
        let (_dir, store) = store().await;
        store.upsert_ssh_target(ssh_target("remote")).await.unwrap();

        store.remove_ssh_target("remote").await.unwrap();
        assert!(store.find_ssh_target("remote").await.unwrap().is_none());

        let missing = store.remove_ssh_target("missing").await.unwrap_err();
        assert!(missing
            .to_string()
            .contains("ssh target not found: missing"));

        let already_gone = store.remove_ssh_target("remote").await.unwrap_err();
        assert!(already_gone
            .to_string()
            .contains("ssh target not found: remote"));
    }
}
