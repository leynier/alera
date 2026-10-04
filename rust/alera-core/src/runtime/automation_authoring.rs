use anyhow::{anyhow, Result};
use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use uuid::Uuid;

use super::{AutomationActor, AutomationDefinition, AutomationState, RuntimeStore};

pub fn automation_from_input(
    input: &Value,
    actor: AutomationActor,
) -> Result<AutomationDefinition> {
    let object = input
        .as_object()
        .ok_or_else(|| anyhow!("automation must be an object"))?;
    let id = Uuid::new_v4().to_string();
    let name = object
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("Automation");
    let base: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect();
    let base = base.trim_matches('-');
    let slug = format!(
        "{}-{}",
        if base.is_empty() { "automation" } else { base },
        &id[..8]
    );
    let now = Utc::now();
    let mut value = json!({"id":id,"slug":slug,"name":name,"state":"active","revision":0,
        "createdBy":actor,"modifiedBy":actor,"createdAt":now,"updatedAt":now});
    for (key, field) in object {
        if !matches!(
            key.as_str(),
            "revision"
                | "approvedRevision"
                | "createdBy"
                | "modifiedBy"
                | "createdAt"
                | "updatedAt"
        ) {
            value[key] = field.clone();
        }
    }
    let definition: AutomationDefinition = serde_json::from_value(value)?;
    RuntimeStore::validate_automation_definition(&definition)?;
    Ok(definition)
}

impl RuntimeStore {
    pub async fn automation_by_request_key(
        &self,
        key: &str,
    ) -> Result<Option<AutomationDefinition>> {
        use sqlx::Row;
        let row = sqlx::query("SELECT id FROM automations WHERE json_extract(dataJson, '$.creationRequestKey') = ? LIMIT 1")
            .bind(key).fetch_optional(self.pool()).await?;
        match row {
            Some(row) => self.find_automation(&row.try_get::<String, _>("id")?).await,
            None => Ok(None),
        }
    }

    pub async fn retired_gate_reactivation_candidates(&self) -> Result<Vec<AutomationDefinition>> {
        use sqlx::Row;
        let mut candidates = Vec::new();
        for definition in self.list_automations(false).await? {
            if !matches!(
                definition.state,
                AutomationState::Draft | AutomationState::Blocked
            ) {
                continue;
            }
            let rows = sqlx::query("SELECT action, detailsJson FROM automationAuditEvents WHERE automationId = ? ORDER BY createdAt, rowid")
                .bind(&definition.id).fetch_all(self.pool()).await?;
            let mut was_active = false;
            let mut retired_gate_only = false;
            for row in rows {
                let action: String = row.try_get("action")?;
                let details: Value =
                    serde_json::from_str(&row.try_get::<String, _>("detailsJson")?)?;
                match action.as_str() {
                    "active" | "approve" => {
                        was_active = true;
                        retired_gate_only = false;
                    }
                    "paused" | "trashed" | "archived" | "draft" | "retiredGatesMigrated" => {
                        was_active = false;
                        retired_gate_only = false;
                    }
                    "edit" if details["material"] == true => {
                        retired_gate_only = was_active;
                    }
                    "blocked" => {
                        let reason = details["reason"].as_str().unwrap_or("");
                        retired_gate_only = was_active
                            && (reason.contains("not opted in to automation execution")
                                || reason.contains("does not allow managed agents")
                                || reason.contains("requires local approval")
                                || reason.contains("has no automation declaration"));
                        if !retired_gate_only {
                            was_active = false;
                        }
                    }
                    _ => {}
                }
            }
            if retired_gate_only {
                candidates.push(definition);
            }
        }
        Ok(candidates)
    }

    pub async fn clear_automation_origin(&self, workspace_id: &str) -> Result<()> {
        for mut definition in self.list_automations(true).await? {
            if definition.origin_workspace_id.as_deref() != Some(workspace_id) {
                continue;
            }
            definition.origin_workspace_id = None;
            sqlx::query("UPDATE automations SET dataJson = ? WHERE id = ?")
                .bind(serde_json::to_string(&definition)?)
                .bind(&definition.id)
                .execute(self.pool())
                .await?;
            self.insert_automation_audit_event(
                Some(&definition.id),
                None,
                "originRemoved",
                definition.modified_by.clone(),
                Some(definition.revision),
                json!({"workspaceId":workspace_id}),
            )
            .await?;
        }
        Ok(())
    }
}

pub fn automation_cursor(
    definition: &AutomationDefinition,
    latest: Option<DateTime<Utc>>,
) -> DateTime<Utc> {
    let start = match &definition.schedule {
        super::AutomationSchedule::Recurring { start_at, .. } => {
            start_at.unwrap_or(definition.created_at)
        }
        super::AutomationSchedule::OneTime { .. } => DateTime::<Utc>::UNIX_EPOCH,
    };
    let cursor = latest.unwrap_or(start).max(start);
    if matches!(
        definition.schedule,
        super::AutomationSchedule::OneTime { .. }
    ) {
        cursor
    } else {
        cursor.max(definition.schedule_cursor_at.unwrap_or(start))
    }
}

#[cfg(test)]
#[path = "automation_authoring_tests.rs"]
mod tests;
