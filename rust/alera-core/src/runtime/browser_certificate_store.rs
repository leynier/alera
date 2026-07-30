use anyhow::Result;
use chrono::Utc;
use sqlx::Row;

use super::{
    format_timestamp, parse_timestamp, BrowserTrustedCertificate, RuntimeStore, RuntimeStoreError,
};

const TRUSTED_CERTIFICATE_COLUMNS: &str = "profileId, host, fingerprintSha256, subject, issuer, \
    validFrom, validTo, createdAt, lastUsedAt";

impl RuntimeStore {
    pub async fn list_browser_trusted_certificates(
        &self,
        profile_id: Option<&str>,
    ) -> Result<Vec<BrowserTrustedCertificate>> {
        let profile_id = profile_id.map(str::trim).filter(|value| !value.is_empty());
        let rows = if let Some(profile_id) = profile_id {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "SELECT {TRUSTED_CERTIFICATE_COLUMNS} FROM browserTrustedCertificates \
                 WHERE profileId = ? ORDER BY host COLLATE NOCASE, createdAt"
            )))
            .bind(profile_id)
            .fetch_all(self.pool())
            .await?
        } else {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "SELECT {TRUSTED_CERTIFICATE_COLUMNS} FROM browserTrustedCertificates \
                 ORDER BY profileId, host COLLATE NOCASE, createdAt"
            )))
            .fetch_all(self.pool())
            .await?
        };
        rows.into_iter().map(certificate_from_row).collect()
    }

    pub async fn trust_browser_certificate(
        &self,
        certificate: BrowserTrustedCertificate,
    ) -> Result<BrowserTrustedCertificate> {
        let certificate = normalize_certificate(certificate)?;
        let profile = self
            .find_browser_profile(&certificate.profile_id)
            .await?
            .ok_or_else(|| {
                anyhow::anyhow!(RuntimeStoreError::Message(format!(
                    "browser profile not found: {}",
                    certificate.profile_id
                )))
            })?;
        if !profile.persistent {
            anyhow::bail!(RuntimeStoreError::Message(
                "ephemeral browser profiles cannot persist trusted certificates".to_string()
            ));
        }
        let now = Utc::now();
        sqlx::query(
            "INSERT INTO browserTrustedCertificates \
             (profileId, host, fingerprintSha256, subject, issuer, validFrom, validTo, createdAt, lastUsedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(profileId, host, fingerprintSha256) DO UPDATE SET \
             subject = excluded.subject, issuer = excluded.issuer, \
             validFrom = excluded.validFrom, validTo = excluded.validTo, \
             lastUsedAt = excluded.lastUsedAt",
        )
        .bind(&certificate.profile_id)
        .bind(&certificate.host)
        .bind(&certificate.fingerprint_sha256)
        .bind(certificate.subject.as_deref())
        .bind(certificate.issuer.as_deref())
        .bind(certificate.valid_from.map(format_timestamp))
        .bind(certificate.valid_to.map(format_timestamp))
        .bind(format_timestamp(certificate.created_at))
        .bind(format_timestamp(now))
        .execute(self.pool())
        .await?;
        self.list_browser_trusted_certificates(Some(&certificate.profile_id))
            .await?
            .into_iter()
            .find(|stored| {
                stored.host == certificate.host
                    && stored.fingerprint_sha256 == certificate.fingerprint_sha256
            })
            .ok_or_else(|| {
                anyhow::anyhow!(RuntimeStoreError::Message(
                    "browser trusted certificate not found after upsert".to_string()
                ))
            })
    }

    pub async fn remove_browser_trusted_certificate(
        &self,
        profile_id: &str,
        host: &str,
        fingerprint_sha256: &str,
    ) -> Result<bool> {
        let profile_id = required(profile_id, "browser profile id")?;
        let host = normalize_host(host)?;
        let fingerprint_sha256 = normalize_fingerprint(fingerprint_sha256)?;
        let result = sqlx::query(
            "DELETE FROM browserTrustedCertificates \
             WHERE profileId = ? AND host = ? AND fingerprintSha256 = ?",
        )
        .bind(profile_id)
        .bind(host)
        .bind(fingerprint_sha256)
        .execute(self.pool())
        .await?;
        Ok(result.rows_affected() > 0)
    }
}

fn normalize_certificate(
    mut certificate: BrowserTrustedCertificate,
) -> Result<BrowserTrustedCertificate> {
    certificate.profile_id = required(&certificate.profile_id, "browser profile id")?;
    certificate.host = normalize_host(&certificate.host)?;
    certificate.fingerprint_sha256 = normalize_fingerprint(&certificate.fingerprint_sha256)?;
    certificate.subject = optional_trimmed(certificate.subject);
    certificate.issuer = optional_trimmed(certificate.issuer);
    Ok(certificate)
}

fn normalize_host(value: &str) -> Result<String> {
    let value = value
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .trim_end_matches('.')
        .to_ascii_lowercase();
    if value.is_empty()
        || value.len() > 253
        || value
            .chars()
            .any(|character| character.is_whitespace() || "/\\@?#".contains(character))
    {
        anyhow::bail!(RuntimeStoreError::Message(
            "browser certificate host is invalid".to_string()
        ));
    }
    Ok(value)
}

fn normalize_fingerprint(value: &str) -> Result<String> {
    let value = value.trim().to_ascii_lowercase();
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        anyhow::bail!(RuntimeStoreError::Message(
            "browser certificate fingerprint must be 64 hexadecimal characters".to_string()
        ));
    }
    Ok(value)
}

fn required(value: &str, label: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        anyhow::bail!(RuntimeStoreError::Message(format!("{label} is required")));
    }
    Ok(value.to_string())
}

fn optional_trimmed(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn certificate_from_row(row: sqlx::sqlite::SqliteRow) -> Result<BrowserTrustedCertificate> {
    Ok(BrowserTrustedCertificate {
        profile_id: row.try_get("profileId")?,
        host: row.try_get("host")?,
        fingerprint_sha256: row.try_get("fingerprintSha256")?,
        subject: row.try_get("subject")?,
        issuer: row.try_get("issuer")?,
        valid_from: row
            .try_get::<Option<String>, _>("validFrom")?
            .map(|value| parse_timestamp(&value)),
        valid_to: row
            .try_get::<Option<String>, _>("validTo")?
            .map(|value| parse_timestamp(&value)),
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        last_used_at: parse_timestamp(row.try_get::<String, _>("lastUsedAt")?.as_str()),
    })
}
