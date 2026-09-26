//! SSH targets: the hosts the hub knows, how to reach them and what the
//! bootstrap installed there.

use anyhow::Result;
use chrono::Utc;
use sqlx::Row as _;

use super::store::{format_timestamp, parse_timestamp};
use super::store_error::RuntimeStoreError;
use super::{RuntimeStore, SshAuthKind, SshBootstrapStatus, SshTarget, SshTargetLastStatus};

pub struct SshTargetBootstrapStateUpdate<'a> {
    pub status: SshBootstrapStatus,
    pub install_dir: Option<&'a str>,
    pub runtime_version: Option<&'a str>,
    pub runtime_platform: Option<&'a str>,
    pub runtime_arch: Option<&'a str>,
    pub last_error: Option<&'a str>,
}

impl RuntimeStore {
    pub async fn list_ssh_targets(&self) -> Result<Vec<SshTarget>> {
        let rows = sqlx::query(
            "SELECT id, alias, host, port, username, platform, arch, authKind, createdAt, updatedAt, lastStatus, \
             installDir, projectsDir, runtimeVersion, runtimePlatform, runtimeArch, bootstrapStatus, lastBootstrapAt, lastCheckedAt, lastError \
             FROM sshTargets ORDER BY alias COLLATE NOCASE ASC",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(ssh_target_from_row).collect()
    }

    pub async fn find_ssh_target(&self, target_id: &str) -> Result<Option<SshTarget>> {
        let row = sqlx::query(
            "SELECT id, alias, host, port, username, platform, arch, authKind, createdAt, updatedAt, lastStatus, \
             installDir, projectsDir, runtimeVersion, runtimePlatform, runtimeArch, bootstrapStatus, lastBootstrapAt, lastCheckedAt, lastError \
             FROM sshTargets WHERE id = ?",
        )
        .bind(target_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(ssh_target_from_row).transpose()
    }

    pub async fn upsert_ssh_target(&self, target: SshTarget) -> Result<SshTarget> {
        // Pre-check instead of relying on the unique index, so a duplicate alias
        // reports the attempted alias rather than a SQLite error.
        if sqlx::query(
            "SELECT id FROM sshTargets WHERE alias = ? COLLATE NOCASE AND id <> ? LIMIT 1",
        )
        .bind(&target.alias)
        .bind(&target.id)
        .fetch_optional(self.pool())
        .await?
        .is_some()
        {
            anyhow::bail!(RuntimeStoreError::Message(format!(
                "ssh target alias already exists: {}",
                target.alias
            )));
        }
        sqlx::query(
            "INSERT INTO sshTargets \
             (id, alias, host, port, username, platform, arch, authKind, createdAt, updatedAt, lastStatus, \
              installDir, projectsDir, runtimeVersion, runtimePlatform, runtimeArch, bootstrapStatus, lastBootstrapAt, lastCheckedAt, lastError) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             alias = excluded.alias, host = excluded.host, port = excluded.port, username = excluded.username, \
             platform = excluded.platform, arch = excluded.arch, authKind = excluded.authKind, \
             updatedAt = excluded.updatedAt, lastStatus = excluded.lastStatus, installDir = excluded.installDir, \
             projectsDir = excluded.projectsDir",
        )
        .bind(&target.id)
        .bind(&target.alias)
        .bind(&target.host)
        .bind(target.port)
        .bind(&target.username)
        .bind(&target.platform)
        .bind(&target.arch)
        .bind(target.auth_kind.as_str())
        .bind(format_timestamp(target.created_at))
        .bind(format_timestamp(target.updated_at))
        .bind(&target.last_status)
        .bind(&target.install_dir)
        .bind(&target.projects_dir)
        .bind(&target.runtime_version)
        .bind(&target.runtime_platform)
        .bind(&target.runtime_arch)
        .bind(target.bootstrap_status.as_str())
        .bind(target.last_bootstrap_at.map(format_timestamp))
        .bind(target.last_checked_at.map(format_timestamp))
        .bind(&target.last_error)
        .execute(self.pool())
        .await?;
        self.find_ssh_target(&target.id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "ssh target not found after upsert: {}",
                target.id
            )))
        })
    }

    pub async fn update_ssh_target_bootstrap_state(
        &self,
        target_id: &str,
        update: SshTargetBootstrapStateUpdate<'_>,
    ) -> Result<SshTarget> {
        let now = format_timestamp(Utc::now());
        sqlx::query(
            "UPDATE sshTargets SET \
             bootstrapStatus = ?, installDir = COALESCE(?, installDir), runtimeVersion = COALESCE(?, runtimeVersion), \
             runtimePlatform = COALESCE(?, runtimePlatform), runtimeArch = COALESCE(?, runtimeArch), \
             lastError = ?, lastBootstrapAt = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(update.status.as_str())
        .bind(update.install_dir)
        .bind(update.runtime_version)
        .bind(update.runtime_platform)
        .bind(update.runtime_arch)
        .bind(update.last_error)
        .bind(&now)
        .bind(&now)
        .bind(target_id)
        .execute(self.pool())
        .await?;
        self.find_ssh_target(target_id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "ssh target not found: {target_id}"
            )))
        })
    }

    pub async fn mark_ssh_target_checked(
        &self,
        target_id: &str,
        last_status: SshTargetLastStatus,
    ) -> Result<SshTarget> {
        let now = format_timestamp(Utc::now());
        sqlx::query(
            "UPDATE sshTargets SET lastStatus = ?, lastCheckedAt = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(last_status.as_str())
        .bind(&now)
        .bind(&now)
        .bind(target_id)
        .execute(self.pool())
        .await?;
        self.find_ssh_target(target_id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "ssh target not found: {target_id}"
            )))
        })
    }

    pub async fn remove_ssh_target(&self, target_id: &str) -> Result<()> {
        let result = sqlx::query("DELETE FROM sshTargets WHERE id = ?")
            .bind(target_id)
            .execute(self.pool())
            .await?;
        if result.rows_affected() == 0 {
            return Err(anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "ssh target not found: {target_id}"
            ))));
        }
        Ok(())
    }
}

fn ssh_target_from_row(row: sqlx::sqlite::SqliteRow) -> Result<SshTarget> {
    let last_bootstrap_at = row
        .try_get::<Option<String>, _>("lastBootstrapAt")?
        .map(|value| parse_timestamp(&value));
    let last_checked_at = row
        .try_get::<Option<String>, _>("lastCheckedAt")?
        .map(|value| parse_timestamp(&value));
    Ok(SshTarget {
        id: row.try_get("id")?,
        alias: row.try_get("alias")?,
        host: row.try_get("host")?,
        port: row.try_get("port")?,
        username: row.try_get("username")?,
        platform: row.try_get("platform")?,
        arch: row.try_get("arch")?,
        auth_kind: SshAuthKind::from_db(row.try_get::<String, _>("authKind")?.as_str()),
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
        last_status: row.try_get("lastStatus")?,
        install_dir: row.try_get("installDir")?,
        projects_dir: row.try_get("projectsDir")?,
        runtime_version: row.try_get("runtimeVersion")?,
        runtime_platform: row.try_get("runtimePlatform")?,
        runtime_arch: row.try_get("runtimeArch")?,
        bootstrap_status: SshBootstrapStatus::from_db(
            row.try_get::<String, _>("bootstrapStatus")?.as_str(),
        ),
        last_bootstrap_at,
        last_checked_at,
        last_error: row.try_get("lastError")?,
    })
}
