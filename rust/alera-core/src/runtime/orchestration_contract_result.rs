use std::collections::HashSet;

use anyhow::{bail, Context, Result};
use serde_json::Value;

use super::orchestration_contract_schema::{bounded_json, validate_instance, INSTANCE_MAX_BYTES};
use super::orchestration_role_contract::artifact_path;
use super::RoleContractSnapshot;

impl RoleContractSnapshot {
    pub fn validate_success_result(&self, raw: &str) -> Result<()> {
        if raw.len() > INSTANCE_MAX_BYTES {
            bail!("contract result exceeds the size limit");
        }
        let result: Value = serde_json::from_str(raw).context("contract result must be JSON")?;
        bounded_json(&result, INSTANCE_MAX_BYTES)?;
        self.validate()?;
        validate_instance(&self.contract.result_schema, &result, "result")?;
        if result.get("completionKind").and_then(Value::as_str) != Some("success")
            || result
                .get("summary")
                .and_then(Value::as_str)
                .is_none_or(|s| s.trim().is_empty())
        {
            bail!("contract completion requires completionKind: success and a non-empty summary");
        }
        let artifacts = result
            .get("artifacts")
            .and_then(Value::as_array)
            .context("contract result requires an artifacts array")?;
        let mut paths = HashSet::new();
        for artifact in artifacts {
            let path = artifact
                .as_str()
                .context("contract artifacts must be relative path strings")?;
            artifact_path(path)?;
            if !paths.insert(path) {
                bail!("duplicate result artifact path");
            }
        }
        for path in &self.contract.required_artifacts {
            if !paths.contains(path.as_str()) {
                bail!("contract result is missing required artifact: {path}");
            }
        }
        let validation = result
            .get("validation")
            .and_then(Value::as_array)
            .context("contract result requires a validation array")?;
        let mut ids = HashSet::new();
        for entry in validation {
            let id = entry
                .get("id")
                .and_then(Value::as_str)
                .context("contract validation entries require an id")?;
            if !ids.insert(id) {
                bail!("duplicate result validation id: {id}");
            }
            if entry.get("passed") != Some(&Value::Bool(true))
                || entry
                    .get("evidence")
                    .and_then(Value::as_str)
                    .is_none_or(|s| s.trim().is_empty())
            {
                bail!("contract validation requires passing evidence: {id}");
            }
        }
        for item in &self.contract.checklist {
            if !ids.contains(item.id.as_str()) {
                bail!("contract result is missing checklist evidence: {}", item.id);
            }
        }
        if result
            .get("filesModified")
            .and_then(Value::as_array)
            .is_none_or(|files| files.iter().any(|path| !path.is_string()))
        {
            bail!("contract result requires a filesModified array of strings");
        }
        Ok(())
    }
}
