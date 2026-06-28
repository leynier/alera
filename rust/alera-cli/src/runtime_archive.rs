use std::{
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{anyhow, bail, Context, Result};
use base64::prelude::*;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;

const DEFAULT_STABLE_RUNTIME_ARCHIVE_URL: &str =
    "https://github.com/leynier/alera/releases/latest/download/runtime-archive.json";
static ARTIFACT_TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone)]
pub(crate) struct RuntimeArtifactRequest {
    pub channel: RuntimeArchiveChannel,
    pub version: Option<String>,
    pub platform: String,
    pub arch: String,
    pub archive_url: Option<String>,
    pub archive_path: Option<PathBuf>,
    pub artifact_path: Option<PathBuf>,
    pub manifest_public_key: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RuntimeArchiveChannel {
    Stable,
    Rc,
}

impl RuntimeArchiveChannel {
    pub fn as_str(self) -> &'static str {
        match self {
            RuntimeArchiveChannel::Stable => "stable",
            RuntimeArchiveChannel::Rc => "rc",
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ResolvedRuntimeArtifact {
    pub path: PathBuf,
    pub file_name: String,
    pub version: String,
    pub platform: String,
    pub arch: String,
    pub sha256: String,
    pub size: u64,
    pub trust: RuntimeArtifactTrust,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum RuntimeArtifactTrust {
    SignedArchive,
    LocalOverride,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeArchive {
    schema_version: u64,
    channel: String,
    version: String,
    items: Vec<RuntimeArchiveItem>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeArchiveItem {
    version: String,
    platform: String,
    arch: String,
    artifact_name: String,
    url: String,
    sha256: String,
    size: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeArchiveSignature {
    algorithm: String,
    public_key_id: String,
    signature: String,
}

pub(crate) fn default_runtime_archive_url(channel: RuntimeArchiveChannel) -> Option<String> {
    match channel {
        RuntimeArchiveChannel::Stable => Some(DEFAULT_STABLE_RUNTIME_ARCHIVE_URL.to_string()),
        RuntimeArchiveChannel::Rc => None,
    }
}

pub(crate) async fn resolve_runtime_artifact(
    request: RuntimeArtifactRequest,
    cache_dir: &Path,
) -> Result<ResolvedRuntimeArtifact> {
    if let Some(path) = request.artifact_path {
        let metadata = tokio::fs::metadata(&path).await.with_context(|| {
            format!(
                "runtime artifact override does not exist: {}",
                path.display()
            )
        })?;
        if !metadata.is_file() {
            bail!(
                "runtime artifact override is not a file: {}",
                path.display()
            );
        }
        let sha256 = file_sha256(&path).await?;
        return Ok(ResolvedRuntimeArtifact {
            file_name: path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("alera-runtime-local.tar.gz")
                .to_string(),
            version: request.version.unwrap_or_else(|| "local".to_string()),
            platform: request.platform,
            arch: request.arch,
            size: metadata.len(),
            sha256,
            trust: RuntimeArtifactTrust::LocalOverride,
            path,
        });
    }

    let archive_json = if let Some(path) = request.archive_path {
        tokio::fs::read_to_string(&path)
            .await
            .with_context(|| format!("failed reading runtime archive {}", path.display()))?
    } else {
        let archive_url = request
            .archive_url
            .or_else(|| default_runtime_archive_url(request.channel))
            .ok_or_else(|| {
                anyhow!(
                    "runtime archive URL is required for the rc channel; pass --archive-url or --archive-path"
                )
            })?;
        http_get_text(&archive_url).await?
    };

    let public_key = request
        .manifest_public_key
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| {
            anyhow!("ALERA_RUNTIME_ARCHIVE_PUBLIC_KEY or --manifest-public-key is required.")
        })?;
    verify_runtime_archive_signature(&archive_json, public_key)?;
    let archive: RuntimeArchive = serde_json::from_str(&archive_json)?;
    if archive.schema_version != 1 {
        bail!(
            "unsupported runtime archive schemaVersion: {}",
            archive.schema_version
        );
    }
    if archive.channel != request.channel.as_str() {
        bail!(
            "runtime archive channel mismatch: expected {}, got {}",
            request.channel.as_str(),
            archive.channel
        );
    }
    if let Some(version) = request.version.as_ref() {
        if archive.version != *version {
            bail!(
                "runtime archive version mismatch: expected {}, got {}",
                version,
                archive.version
            );
        }
    }
    let selected = archive
        .items
        .iter()
        .find(|item| {
            item.platform == request.platform
                && item.arch == request.arch
                && request
                    .version
                    .as_ref()
                    .is_none_or(|version| &item.version == version)
        })
        .cloned()
        .ok_or_else(|| {
            anyhow!(
                "runtime archive has no artifact for {} {}{}",
                request.platform,
                request.arch,
                request
                    .version
                    .as_ref()
                    .map(|version| format!(" version {version}"))
                    .unwrap_or_default()
            )
        })?;

    tokio::fs::create_dir_all(cache_dir).await?;
    let output = cache_dir.join(cache_artifact_file_name(&selected));
    if let Some(sha256) = matching_artifact_sha256(&output, &selected).await? {
        return Ok(ResolvedRuntimeArtifact {
            path: output,
            file_name: selected.artifact_name,
            version: selected.version,
            platform: selected.platform,
            arch: selected.arch,
            sha256,
            size: selected.size,
            trust: RuntimeArtifactTrust::SignedArchive,
        });
    }

    let temp_output = unique_artifact_temp_path(&output);
    http_download_to_file(&selected.url, &temp_output).await?;
    let sha256 = match verify_artifact_file(&temp_output, &selected).await {
        Ok(sha256) => sha256,
        Err(error) => {
            let _ = tokio::fs::remove_file(&temp_output).await;
            return Err(error);
        }
    };
    if let Some(sha256) =
        remove_bad_cached_artifact_before_rename(&temp_output, &output, &selected).await?
    {
        return Ok(ResolvedRuntimeArtifact {
            path: output,
            file_name: selected.artifact_name,
            version: selected.version,
            platform: selected.platform,
            arch: selected.arch,
            sha256,
            size: selected.size,
            trust: RuntimeArtifactTrust::SignedArchive,
        });
    }
    if let Err(error) = tokio::fs::rename(&temp_output, &output).await {
        if let Some(sha256) = matching_artifact_sha256(&output, &selected).await? {
            let _ = tokio::fs::remove_file(&temp_output).await;
            return Ok(ResolvedRuntimeArtifact {
                path: output,
                file_name: selected.artifact_name,
                version: selected.version,
                platform: selected.platform,
                arch: selected.arch,
                sha256,
                size: selected.size,
                trust: RuntimeArtifactTrust::SignedArchive,
            });
        }
        let _ = tokio::fs::remove_file(&temp_output).await;
        return Err(error).with_context(|| {
            format!(
                "failed moving verified runtime artifact into {}",
                output.display()
            )
        });
    }
    Ok(ResolvedRuntimeArtifact {
        path: output,
        file_name: selected.artifact_name,
        version: selected.version,
        platform: selected.platform,
        arch: selected.arch,
        sha256,
        size: selected.size,
        trust: RuntimeArtifactTrust::SignedArchive,
    })
}

fn cache_artifact_file_name(item: &RuntimeArchiveItem) -> String {
    let hash_prefix = item.sha256.get(..12).unwrap_or(&item.sha256);
    format!("{}-{hash_prefix}-{}", item.version, item.artifact_name)
}

fn unique_artifact_temp_path(output: &Path) -> PathBuf {
    let name = output
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("alera-runtime-artifact");
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or_default();
    let counter = ARTIFACT_TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    output.with_file_name(format!(
        ".{name}.{}.{}.{}.download",
        std::process::id(),
        millis,
        counter
    ))
}

async fn matching_artifact_sha256(
    path: &Path,
    selected: &RuntimeArchiveItem,
) -> Result<Option<String>> {
    let metadata = match tokio::fs::metadata(path).await {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error).with_context(|| format!("failed reading {}", path.display()))
        }
    };
    if !metadata.is_file() || metadata.len() != selected.size {
        return Ok(None);
    }
    let sha256 = file_sha256(path).await?;
    if sha256 == selected.sha256 {
        Ok(Some(sha256))
    } else {
        Ok(None)
    }
}

async fn remove_bad_cached_artifact_before_rename(
    temp_output: &Path,
    output: &Path,
    selected: &RuntimeArchiveItem,
) -> Result<Option<String>> {
    if let Some(sha256) = matching_artifact_sha256(output, selected).await? {
        let _ = tokio::fs::remove_file(temp_output).await;
        return Ok(Some(sha256));
    }
    match tokio::fs::remove_file(output).await {
        Ok(()) => Ok(None),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => {
            let _ = tokio::fs::remove_file(temp_output).await;
            Err(error).with_context(|| {
                format!(
                    "failed removing stale runtime artifact cache at {}",
                    output.display()
                )
            })
        }
    }
}

async fn verify_artifact_file(path: &Path, selected: &RuntimeArchiveItem) -> Result<String> {
    let metadata = tokio::fs::metadata(path).await?;
    if metadata.len() != selected.size {
        bail!(
            "runtime artifact size mismatch for {}: expected {}, got {}",
            selected.artifact_name,
            selected.size,
            metadata.len()
        );
    }
    let sha256 = file_sha256(path).await?;
    if sha256 != selected.sha256 {
        bail!(
            "runtime artifact sha256 mismatch for {}: expected {}, got {}",
            selected.artifact_name,
            selected.sha256,
            sha256
        );
    }
    Ok(sha256)
}

fn verify_runtime_archive_signature(manifest_json: &str, public_key_base64: &str) -> Result<()> {
    let decoded: Value = serde_json::from_str(manifest_json)?;
    let Value::Object(mut manifest) = decoded else {
        bail!("runtime archive must be a JSON object.");
    };
    let signature_value = manifest
        .remove("signature")
        .ok_or_else(|| anyhow!("runtime archive is missing signature metadata."))?;
    let signature: RuntimeArchiveSignature = serde_json::from_value(signature_value)?;
    if signature.algorithm != "ed25519" {
        bail!(
            "unsupported runtime archive signature algorithm: {}",
            signature.algorithm
        );
    }
    if signature.public_key_id.trim().is_empty() {
        bail!("runtime archive signature publicKeyId must be non-empty.");
    }
    let public_key_bytes = BASE64_STANDARD.decode(public_key_base64.trim())?;
    let public_key_array: [u8; 32] = public_key_bytes
        .try_into()
        .map_err(|_| anyhow!("runtime archive public key must be 32 bytes."))?;
    let verifying_key = VerifyingKey::from_bytes(&public_key_array)?;
    let signature_bytes = BASE64_STANDARD.decode(signature.signature)?;
    let signature = Signature::from_slice(&signature_bytes)?;
    let payload = serde_json::to_vec(&canonical_value(Value::Object(manifest)))?;
    verifying_key
        .verify(&payload, &signature)
        .context("runtime archive signature is invalid")
}

fn canonical_value(value: Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut entries: Vec<(String, Value)> = map.into_iter().collect();
            entries.sort_by(|left, right| left.0.cmp(&right.0));
            let mut sorted = Map::new();
            for (key, value) in entries {
                sorted.insert(key, canonical_value(value));
            }
            Value::Object(sorted)
        }
        Value::Array(items) => Value::Array(items.into_iter().map(canonical_value).collect()),
        other => other,
    }
}

async fn file_sha256(path: &Path) -> Result<String> {
    let bytes = tokio::fs::read(path).await?;
    Ok(hex::encode(Sha256::digest(bytes)))
}

async fn http_get_text(url: &str) -> Result<String> {
    let response = reqwest::get(url)
        .await
        .with_context(|| format!("failed requesting {url}"))?;
    let status = response.status();
    if !status.is_success() {
        bail!("request failed for {url}: HTTP {status}");
    }
    response
        .text()
        .await
        .with_context(|| format!("failed reading response from {url}"))
}

async fn http_download_to_file(url: &str, path: &Path) -> Result<()> {
    let mut response = reqwest::get(url)
        .await
        .with_context(|| format!("failed downloading {url}"))?;
    let status = response.status();
    if !status.is_success() {
        bail!("download failed for {url}: HTTP {status}");
    }
    let mut file = tokio::fs::File::create(path).await?;
    while let Some(chunk) = response.chunk().await? {
        file.write_all(&chunk).await?;
    }
    file.flush().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_archive_url_is_stable_only() {
        assert_eq!(
            default_runtime_archive_url(RuntimeArchiveChannel::Stable).as_deref(),
            Some(DEFAULT_STABLE_RUNTIME_ARCHIVE_URL)
        );
        assert!(default_runtime_archive_url(RuntimeArchiveChannel::Rc).is_none());
    }

    #[test]
    fn cache_artifact_name_includes_version_and_hash() {
        let item = RuntimeArchiveItem {
            version: "1.2.3".to_string(),
            platform: "linux".to_string(),
            arch: "x64".to_string(),
            artifact_name: "alera-runtime-linux-x64.tar.gz".to_string(),
            url: "https://example.com/alera-runtime-linux-x64.tar.gz".to_string(),
            sha256: "abcdef0123456789".to_string(),
            size: 42,
        };

        assert_eq!(
            cache_artifact_file_name(&item),
            "1.2.3-abcdef012345-alera-runtime-linux-x64.tar.gz"
        );
    }

    #[tokio::test]
    async fn removes_bad_cached_artifact_before_rename() {
        let dir = tempfile::tempdir().unwrap();
        let output = dir.path().join("cached-runtime.tar.gz");
        let temp_output = dir.path().join("download.tmp");
        let bytes = b"verified runtime";
        tokio::fs::write(&output, b"corrupt runtime").await.unwrap();
        tokio::fs::write(&temp_output, bytes).await.unwrap();
        let selected = RuntimeArchiveItem {
            version: "1.2.3".to_string(),
            platform: "linux".to_string(),
            arch: "x64".to_string(),
            artifact_name: "alera-runtime-linux-x64.tar.gz".to_string(),
            url: "https://example.com/alera-runtime-linux-x64.tar.gz".to_string(),
            sha256: hex::encode(Sha256::digest(bytes)),
            size: bytes.len() as u64,
        };

        let existing = remove_bad_cached_artifact_before_rename(&temp_output, &output, &selected)
            .await
            .unwrap();
        tokio::fs::rename(&temp_output, &output).await.unwrap();

        assert_eq!(existing, None);
        assert_eq!(tokio::fs::read(&output).await.unwrap(), bytes);
    }
}
