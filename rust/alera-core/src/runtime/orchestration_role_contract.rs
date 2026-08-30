use std::collections::HashSet;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

use super::orchestration_contract_schema::{
    bounded_json, compile_schema, validate_instance, CONTRACT_MAX_BYTES, INSTANCE_MAX_BYTES,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RoleContractV1 {
    pub version: u32,
    pub id: String,
    pub revision: u32,
    pub name: String,
    pub purpose: String,
    pub instructions: String,
    pub input_schema: Value,
    pub result_schema: Value,
    pub required_artifacts: Vec<String>,
    pub checklist: Vec<RoleContractChecklistItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RoleContractChecklistItem {
    pub id: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RoleContractSnapshot {
    pub version: u32,
    pub contract: RoleContractV1,
    pub inputs: Value,
    pub digest: String,
}

pub(super) fn portable_id(id: &str) -> Result<()> {
    if id.is_empty()
        || matches!(id, "." | "..")
        || id.len() > 80
        || !id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c))
    {
        bail!(
            "contract identifiers must be 1-80 ASCII letters, digits, dots, hyphens or underscores"
        );
    }
    Ok(())
}

pub(super) fn artifact_path(path: &str) -> Result<()> {
    if path.is_empty()
        || path.len() > 512
        || path
            .chars()
            .any(|c| c.is_control() || "\\:*?\"<>|".contains(c))
    {
        bail!("contract artifact must be a portable workspace-relative file path");
    }
    for part in path.split('/') {
        let stem = part
            .split('.')
            .next()
            .unwrap_or_default()
            .to_ascii_uppercase();
        if part.is_empty()
            || part.len() > 255
            || part == "."
            || part == ".."
            || part.ends_with(['.', ' '])
            || part.eq_ignore_ascii_case(".git")
            || [
                "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7",
                "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8",
                "LPT9", "COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³",
            ]
            .contains(&stem.as_str())
        {
            bail!("contract artifact path contains an unsafe component");
        }
    }
    Ok(())
}

impl RoleContractV1 {
    pub fn validate(&self) -> Result<()> {
        if self.version != 1 || self.revision == 0 {
            bail!("role contract requires version 1 and a positive revision");
        }
        portable_id(&self.id)?;
        for (label, text, max) in [
            ("name", &self.name, 160),
            ("purpose", &self.purpose, 4096),
            ("instructions", &self.instructions, 16384),
        ] {
            if text.trim().is_empty() || text.len() > max || text.contains('\0') {
                bail!("contract {label} is empty, too long or contains NUL");
            }
        }
        bounded_json(&serde_json::to_value(self)?, CONTRACT_MAX_BYTES)?;
        compile_schema(&self.input_schema)?;
        compile_schema(&self.result_schema)?;
        if self.required_artifacts.len() > 64 || self.checklist.len() > 64 {
            bail!("contract allows at most 64 required artifacts and checklist items");
        }
        let mut paths = HashSet::new();
        for path in &self.required_artifacts {
            artifact_path(path)?;
            if !paths.insert(path.to_lowercase()) {
                bail!("duplicate contract artifact path");
            }
        }
        let mut ids = HashSet::new();
        for item in &self.checklist {
            portable_id(&item.id)?;
            if item.description.trim().is_empty() || item.description.len() > 2048 {
                bail!("contract checklist description is empty or too long");
            }
            if !ids.insert(&item.id) {
                bail!("duplicate contract checklist id: {}", item.id);
            }
        }
        Ok(())
    }
}

impl RoleContractSnapshot {
    pub fn freeze(contract: RoleContractV1, inputs: Value) -> Result<Self> {
        contract.validate()?;
        validate_instance(&contract.input_schema, &inputs, "inputs")?;
        let mut snapshot = Self {
            version: 1,
            contract,
            inputs,
            digest: String::new(),
        };
        snapshot.digest = snapshot.content_digest()?;
        Ok(snapshot)
    }

    pub fn validate(&self) -> Result<()> {
        if self.version != 1 {
            bail!("unsupported role contract snapshot version");
        }
        self.contract.validate()?;
        validate_instance(&self.contract.input_schema, &self.inputs, "inputs")?;
        if self.digest != self.content_digest()? {
            bail!("role contract snapshot digest does not match its contents");
        }
        Ok(())
    }

    fn content_digest(&self) -> Result<String> {
        bounded_json(&self.inputs, INSTANCE_MAX_BYTES)?;
        let mut content = serde_json::json!([self.version, self.contract, self.inputs]);
        content.sort_all_objects();
        Ok(format!(
            "{:x}",
            Sha256::digest(serde_json::to_vec(&content)?)
        ))
    }

    pub fn worker_instructions(&self) -> Result<String> {
        self.validate()?;
        Ok(format!(
            "=== FROZEN ROLE CONTRACT ===\n{}\n\
             Follow the contract purpose and instructions using the frozen inputs. \
             A successful result must match resultSchema. List requiredArtifacts as exact \
             workspace-relative paths in artifacts. For each checklist id include one \
             validation entry with id, passed: true and non-empty evidence. \
             Report failures honestly; do not claim checks that were not performed.\n",
            serde_json::to_string_pretty(self)?
        ))
    }
}
