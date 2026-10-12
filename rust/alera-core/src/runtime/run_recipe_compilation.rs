use std::collections::{HashMap, HashSet};

use anyhow::{bail, Result};

use super::orchestration_contract_schema::bounded_json;
use super::orchestration_role_contract::portable_id;
use super::{WorkflowHumanGate, WorkflowRecipeV1, WORKFLOW_DOCUMENT_MAX_BYTES};

impl WorkflowRecipeV1 {
    pub fn validate(&self) -> Result<()> {
        if self.version != 1 || self.revision == 0 {
            bail!("workflow recipe requires version 1 and a positive revision");
        }
        portable_id(&self.id)?;
        text(&self.name, 160, "name")?;
        text(&self.description, 4096, "description")?;
        text(
            &self.coordinator_instructions,
            16384,
            "coordinator instructions",
        )?;
        bounded_json(&serde_json::to_value(self)?, WORKFLOW_DOCUMENT_MAX_BYTES)?;
        for (label, length) in [
            ("roles", self.roles.len()),
            ("contracts", self.contracts.len()),
            ("stages", self.stages.len()),
        ] {
            if length == 0 || length > 16 {
                bail!("workflow recipe requires 1-16 {label}");
            }
        }
        let mut contracts = HashMap::new();
        for contract in &self.contracts {
            contract.validate()?;
            if contracts.insert(&contract.id, contract).is_some() {
                bail!("duplicate workflow contract id");
            }
        }
        let mut roles = HashSet::new();
        let mut used_contracts = HashSet::new();
        for role in &self.roles {
            portable_id(&role.id)?;
            text(&role.name, 160, "role name")?;
            if !roles.insert(&role.id) {
                bail!("duplicate workflow role id");
            }
            if contracts
                .get(&role.contract_id)
                .is_none_or(|contract| contract.revision != role.contract_revision)
            {
                bail!("workflow role references a missing contract revision");
            }
            used_contracts.insert(&role.contract_id);
        }
        if used_contracts.len() != contracts.len() {
            bail!("workflow recipe contains an unused contract");
        }
        let mut stages = HashMap::new();
        let mut used_roles = HashSet::new();
        for stage in &self.stages {
            portable_id(&stage.id)?;
            text(&stage.name, 160, "stage name")?;
            text(&stage.purpose, 4096, "stage purpose")?;
            if stages.insert(&stage.id, stage).is_some() {
                bail!("duplicate workflow stage id");
            }
            if stage.roles.is_empty() || stage.roles.len() > 16 || stage.depends_on.len() > 16 {
                bail!("workflow stage has invalid role or dependency counts");
            }
            unique(&stage.roles, "stage roles")?;
            unique(&stage.depends_on, "stage dependencies")?;
            for role in &stage.roles {
                if !roles.contains(role) {
                    bail!("workflow stage references a missing role");
                }
                used_roles.insert(role);
            }
        }
        if used_roles.len() != roles.len() {
            bail!("workflow recipe contains an unused role");
        }
        for stage in &self.stages {
            if stage
                .depends_on
                .iter()
                .any(|dependency| dependency == &stage.id || !stages.contains_key(dependency))
            {
                bail!("workflow stage has a missing or self dependency");
            }
        }
        self.stage_order()?;
        let foundation = self
            .stages
            .iter()
            .filter(|stage| stage.gate == Some(WorkflowHumanGate::Foundation))
            .collect::<Vec<_>>();
        let product = self
            .stages
            .iter()
            .filter(|stage| stage.gate == Some(WorkflowHumanGate::Product))
            .collect::<Vec<_>>();
        if foundation.len() > 1 || product.len() > 1 {
            bail!("workflow recipes allow at most one Foundation and one Product gate");
        }
        if let Some(product) = product.first() {
            let mut ancestors = HashSet::new();
            let mut pending = product.depends_on.clone();
            while let Some(id) = pending.pop() {
                if ancestors.insert(id.clone()) {
                    pending.extend(stages[&id].depends_on.iter().cloned());
                }
            }
            if ancestors.len() + 1 != stages.len() {
                bail!("Product gate must follow every other stage");
            }
        }
        Ok(())
    }

    pub fn stage_order(&self) -> Result<Vec<String>> {
        let mut ordered = Vec::new();
        let mut visited = HashSet::new();
        while ordered.len() < self.stages.len() {
            let prior = ordered.len();
            for stage in &self.stages {
                if !visited.contains(&stage.id)
                    && stage.depends_on.iter().all(|id| visited.contains(id))
                {
                    visited.insert(stage.id.clone());
                    ordered.push(stage.id.clone());
                }
            }
            if ordered.len() == prior {
                bail!("workflow stage dependencies contain a cycle or missing reference");
            }
        }
        Ok(ordered)
    }
}

fn text(value: &str, max: usize, label: &str) -> Result<()> {
    if value.trim().is_empty() || value.len() > max || value.contains('\0') {
        bail!("workflow {label} is empty, too long or contains NUL");
    }
    Ok(())
}

fn unique(values: &[String], label: &str) -> Result<()> {
    if values.iter().collect::<HashSet<_>>().len() != values.len() {
        bail!("workflow {label} contains duplicates");
    }
    Ok(())
}
