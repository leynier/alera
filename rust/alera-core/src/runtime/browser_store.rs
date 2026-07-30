use anyhow::Result;
use chrono::Utc;
use sqlx::Row;

use super::browser_privacy::canonical_browser_origin;
use super::{
    format_timestamp, parse_timestamp, BrowserPermission, BrowserPermissionDecision,
    BrowserProfile, BrowserProfileSource, BrowserProfileSourceFamily, BrowserSettings,
    RuntimeStore, RuntimeStoreError, DEFAULT_BROWSER_PROFILE_ID,
};

const PROFILE_COLUMNS: &str = "id, name, persistent, isDefault, sourceFamily, \
    sourceProfileName, sourceImportedAt, createdAt, updatedAt";
const PERMISSION_COLUMNS: &str = "profileId, origin, permission, decision, updatedAt";
const BROWSER_SETTINGS_KEY: &str = "browser.settings.v1";

impl RuntimeStore {
    pub async fn browser_settings(&self) -> Result<BrowserSettings> {
        let Some(encoded) = self.get_metadata(BROWSER_SETTINGS_KEY).await? else {
            return Ok(BrowserSettings::default());
        };
        Ok(serde_json::from_str(&encoded).unwrap_or_default())
    }

    pub async fn set_browser_settings(&self, settings: BrowserSettings) -> Result<BrowserSettings> {
        self.set_metadata(BROWSER_SETTINGS_KEY, &serde_json::to_string(&settings)?)
            .await?;
        Ok(settings)
    }

    pub async fn ensure_default_browser_profile(&self) -> Result<BrowserProfile> {
        if let Some(profile) = self
            .find_browser_profile(DEFAULT_BROWSER_PROFILE_ID)
            .await?
        {
            if profile.persistent && profile.is_default {
                return Ok(profile);
            }
        }
        let now = Utc::now();
        self.upsert_browser_profile(BrowserProfile {
            id: DEFAULT_BROWSER_PROFILE_ID.to_string(),
            name: "Default".to_string(),
            persistent: true,
            is_default: true,
            source: None,
            created_at: now,
            updated_at: now,
        })
        .await
    }

    pub async fn list_browser_profiles(&self) -> Result<Vec<BrowserProfile>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {PROFILE_COLUMNS} FROM browserProfiles \
             ORDER BY isDefault DESC, name COLLATE NOCASE ASC"
        )))
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(browser_profile_from_row).collect()
    }

    pub async fn find_browser_profile(&self, profile_id: &str) -> Result<Option<BrowserProfile>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {PROFILE_COLUMNS} FROM browserProfiles WHERE id = ?"
        )))
        .bind(profile_id.trim())
        .fetch_optional(self.pool())
        .await?;
        row.map(browser_profile_from_row).transpose()
    }

    pub async fn browser_profile_by_name(&self, name: &str) -> Result<Option<BrowserProfile>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {PROFILE_COLUMNS} FROM browserProfiles \
             WHERE name = ? COLLATE NOCASE"
        )))
        .bind(name.trim())
        .fetch_optional(self.pool())
        .await?;
        row.map(browser_profile_from_row).transpose()
    }

    pub async fn upsert_browser_profile(&self, profile: BrowserProfile) -> Result<BrowserProfile> {
        let profile = normalize_profile(profile)?;
        let conflict = sqlx::query(
            "SELECT id FROM browserProfiles \
             WHERE name = ? COLLATE NOCASE AND id <> ? LIMIT 1",
        )
        .bind(&profile.name)
        .bind(&profile.id)
        .fetch_optional(self.pool())
        .await?;
        if conflict.is_some() {
            anyhow::bail!(RuntimeStoreError::Message(format!(
                "browser profile name already exists: {}",
                profile.name
            )));
        }
        let now = format_timestamp(Utc::now());
        sqlx::query(
            "INSERT INTO browserProfiles \
             (id, name, persistent, isDefault, sourceFamily, sourceProfileName, \
              sourceImportedAt, createdAt, updatedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET name = excluded.name, \
             persistent = excluded.persistent, isDefault = excluded.isDefault, \
             sourceFamily = excluded.sourceFamily, \
             sourceProfileName = excluded.sourceProfileName, \
             sourceImportedAt = excluded.sourceImportedAt, \
             updatedAt = excluded.updatedAt",
        )
        .bind(&profile.id)
        .bind(&profile.name)
        .bind(i64::from(profile.persistent))
        .bind(i64::from(profile.is_default))
        .bind(profile.source.as_ref().map(|source| source.family.as_str()))
        .bind(
            profile
                .source
                .as_ref()
                .and_then(|source| source.profile_name.as_deref()),
        )
        .bind(
            profile
                .source
                .as_ref()
                .map(|source| format_timestamp(source.imported_at)),
        )
        .bind(format_timestamp(profile.created_at))
        .bind(now)
        .execute(self.pool())
        .await?;
        self.find_browser_profile(&profile.id)
            .await?
            .ok_or_else(|| {
                anyhow::anyhow!(RuntimeStoreError::Message(format!(
                    "browser profile not found after upsert: {}",
                    profile.id
                )))
            })
    }

    pub async fn remove_browser_profile(&self, profile_id: &str) -> Result<bool> {
        let profile_id = required(profile_id, "browser profile id")?;
        if profile_id == DEFAULT_BROWSER_PROFILE_ID {
            anyhow::bail!(RuntimeStoreError::Message(
                "the default browser profile cannot be removed".to_string()
            ));
        }
        let mut tx = self.pool().begin().await?;
        for table in [
            "browserPermissions",
            "browserHistory",
            "browserClosedTabs",
            "browserTrustedCertificates",
        ] {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "DELETE FROM {table} WHERE profileId = ?"
            )))
            .bind(&profile_id)
            .execute(&mut *tx)
            .await?;
        }
        let result = sqlx::query("DELETE FROM browserProfiles WHERE id = ?")
            .bind(&profile_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_browser_permissions(
        &self,
        profile_id: Option<&str>,
        origin: Option<&str>,
    ) -> Result<Vec<BrowserPermission>> {
        let profile_id = profile_id.map(str::trim).filter(|value| !value.is_empty());
        let origin = origin.map(canonical_browser_origin).transpose()?;
        let rows = match (profile_id, origin.as_deref()) {
            (Some(profile_id), Some(origin)) => {
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "SELECT {PERMISSION_COLUMNS} FROM browserPermissions \
                 WHERE profileId = ? AND origin = ? \
                 ORDER BY permission COLLATE NOCASE ASC"
                )))
                .bind(profile_id)
                .bind(origin)
                .fetch_all(self.pool())
                .await?
            }
            (Some(profile_id), None) => {
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "SELECT {PERMISSION_COLUMNS} FROM browserPermissions \
                 WHERE profileId = ? ORDER BY origin, permission COLLATE NOCASE ASC"
                )))
                .bind(profile_id)
                .fetch_all(self.pool())
                .await?
            }
            (None, Some(origin)) => {
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "SELECT {PERMISSION_COLUMNS} FROM browserPermissions \
                 WHERE origin = ? ORDER BY profileId, permission COLLATE NOCASE ASC"
                )))
                .bind(origin)
                .fetch_all(self.pool())
                .await?
            }
            (None, None) => {
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "SELECT {PERMISSION_COLUMNS} FROM browserPermissions \
                 ORDER BY profileId, origin, permission COLLATE NOCASE ASC"
                )))
                .fetch_all(self.pool())
                .await?
            }
        };
        rows.into_iter().map(browser_permission_from_row).collect()
    }

    pub async fn upsert_browser_permission(
        &self,
        permission: BrowserPermission,
    ) -> Result<BrowserPermission> {
        let permission = normalize_permission(permission)?;
        let now = Utc::now();
        sqlx::query(
            "INSERT INTO browserPermissions \
             (profileId, origin, permission, decision, updatedAt) VALUES (?, ?, ?, ?, ?) \
             ON CONFLICT(profileId, origin, permission) DO UPDATE SET \
             decision = excluded.decision, updatedAt = excluded.updatedAt",
        )
        .bind(&permission.profile_id)
        .bind(&permission.origin)
        .bind(&permission.permission)
        .bind(permission.decision.as_str())
        .bind(format_timestamp(now))
        .execute(self.pool())
        .await?;
        Ok(BrowserPermission {
            updated_at: now,
            ..permission
        })
    }

    pub async fn remove_browser_permission(
        &self,
        profile_id: &str,
        origin: &str,
        permission: &str,
    ) -> Result<bool> {
        let origin = canonical_browser_origin(origin)?;
        let result = sqlx::query(
            "DELETE FROM browserPermissions \
             WHERE profileId = ? AND origin = ? AND permission = ?",
        )
        .bind(profile_id.trim())
        .bind(origin)
        .bind(permission.trim())
        .execute(self.pool())
        .await?;
        Ok(result.rows_affected() > 0)
    }
}

fn normalize_profile(mut profile: BrowserProfile) -> Result<BrowserProfile> {
    profile.id = required(&profile.id, "browser profile id")?;
    profile.name = required(&profile.name, "browser profile name")?;
    profile.source = profile.source.map(normalize_profile_source);
    if profile.id == DEFAULT_BROWSER_PROFILE_ID {
        profile.persistent = true;
        profile.is_default = true;
    } else if profile.is_default {
        anyhow::bail!(RuntimeStoreError::Message(
            "only the default browser profile id may be marked as default".to_string()
        ));
    }
    Ok(profile)
}

fn normalize_permission(mut permission: BrowserPermission) -> Result<BrowserPermission> {
    permission.profile_id = required(&permission.profile_id, "browser profile id")?;
    permission.origin = canonical_browser_origin(&permission.origin)?;
    permission.permission = required(&permission.permission, "browser permission")?;
    Ok(permission)
}

fn required(value: &str, label: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        anyhow::bail!(RuntimeStoreError::Message(format!("{label} is required")));
    }
    Ok(value.to_string())
}

fn browser_profile_from_row(row: sqlx::sqlite::SqliteRow) -> Result<BrowserProfile> {
    let source_family: Option<String> = row.try_get("sourceFamily")?;
    let source_profile_name: Option<String> = row.try_get("sourceProfileName")?;
    let source_imported_at: Option<String> = row.try_get("sourceImportedAt")?;
    Ok(BrowserProfile {
        id: row.try_get("id")?,
        name: row.try_get("name")?,
        persistent: row.try_get::<i64, _>("persistent")? != 0,
        is_default: row.try_get::<i64, _>("isDefault")? != 0,
        source: source_family
            .zip(source_imported_at)
            .map(|(family, imported_at)| BrowserProfileSource {
                family: BrowserProfileSourceFamily::from_db(&family),
                profile_name: source_profile_name,
                imported_at: parse_timestamp(&imported_at),
            }),
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
    })
}

fn normalize_profile_source(mut source: BrowserProfileSource) -> BrowserProfileSource {
    source.profile_name = source
        .profile_name
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty());
    source
}

fn browser_permission_from_row(row: sqlx::sqlite::SqliteRow) -> Result<BrowserPermission> {
    Ok(BrowserPermission {
        profile_id: row.try_get("profileId")?,
        origin: row.try_get("origin")?,
        permission: row.try_get("permission")?,
        decision: BrowserPermissionDecision::from_db(
            row.try_get::<String, _>("decision")?.as_str(),
        ),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
    })
}
