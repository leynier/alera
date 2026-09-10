use anyhow::{anyhow, Result};
use chrono::Utc;
use uuid::Uuid;

use super::{
    format_timestamp, AutomationActor, AutomationDefinition, AutomationState, RuntimeStore,
};

impl RuntimeStore {
    pub async fn set_automation_circuit_opened(
        &self,
        id: &str,
        opened: bool,
        actor: AutomationActor,
        reason: Option<&str>,
    ) -> Result<AutomationDefinition> {
        let mut definition = self
            .find_automation(id)
            .await?
            .ok_or_else(|| anyhow!("automation not found: {id}"))?;
        if definition.circuit_opened == opened {
            return Ok(definition);
        }
        definition.circuit_opened = opened;
        definition.circuit_opened_at = opened.then_some(Utc::now());
        definition.updated_at = Utc::now();
        definition.modified_by = actor.clone();
        sqlx::query("UPDATE automations SET dataJson = ?, updatedAt = ? WHERE id = ?")
            .bind(serde_json::to_string(&definition)?)
            .bind(format_timestamp(definition.updated_at))
            .bind(id)
            .execute(self.pool())
            .await?;
        self.insert_automation_audit_event(
            Some(id),
            None,
            if opened {
                "circuitOpened"
            } else {
                "circuitReset"
            },
            actor,
            Some(definition.revision),
            serde_json::json!({ "reason": reason }),
        )
        .await?;
        Ok(definition)
    }

    pub async fn open_automation_circuit(
        &self,
        id: &str,
        actor: AutomationActor,
        reason: Option<&str>,
    ) -> Result<AutomationDefinition> {
        let mut definition = self
            .find_automation(id)
            .await?
            .ok_or_else(|| anyhow!("automation not found: {id}"))?;
        let open_circuit = !definition.circuit_opened;
        let block_active = definition.state == AutomationState::Active;
        if !open_circuit && !block_active {
            return Ok(definition);
        }
        if open_circuit {
            definition.circuit_opened = true;
            definition.circuit_opened_at = Some(Utc::now());
        }
        if block_active {
            definition.state = AutomationState::Blocked;
        }
        definition.updated_at = Utc::now();
        definition.modified_by = actor.clone();
        let encoded = serde_json::to_string(&definition)?;
        let actor_json = serde_json::to_string(&actor)?;
        let details = serde_json::to_string(&serde_json::json!({ "reason": reason }))?;
        let mut transaction = self.pool().begin().await?;
        sqlx::query("UPDATE automations SET state = ?, dataJson = ?, updatedAt = ? WHERE id = ?")
            .bind(definition.state.as_str())
            .bind(&encoded)
            .bind(format_timestamp(definition.updated_at))
            .bind(id)
            .execute(&mut *transaction)
            .await?;
        if open_circuit {
            sqlx::query(
                "INSERT INTO automationAuditEvents (id, automationId, runId, action, actorJson, revision, detailsJson, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            )
            .bind(Uuid::new_v4().to_string())
            .bind(id)
            .bind(None::<String>)
            .bind("circuitOpened")
            .bind(&actor_json)
            .bind(definition.revision)
            .bind(&details)
            .bind(format_timestamp(definition.updated_at))
            .execute(&mut *transaction)
            .await?;
        }
        if block_active {
            sqlx::query(
                "INSERT INTO automationAuditEvents (id, automationId, runId, action, actorJson, revision, detailsJson, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            )
            .bind(Uuid::new_v4().to_string())
            .bind(id)
            .bind(None::<String>)
            .bind(AutomationState::Blocked.as_str())
            .bind(&actor_json)
            .bind(definition.revision)
            .bind(&details)
            .bind(format_timestamp(definition.updated_at))
            .execute(&mut *transaction)
            .await?;
        }
        transaction.commit().await?;
        Ok(definition)
    }

    pub async fn reset_automation_circuit(
        &self,
        id: &str,
        actor: AutomationActor,
        reason: Option<&str>,
    ) -> Result<AutomationDefinition> {
        let definition = self
            .find_automation(id)
            .await?
            .ok_or_else(|| anyhow!("automation not found: {id}"))?;
        if !definition.circuit_opened {
            return Ok(definition);
        }
        self.reset_opened_automation_circuit(
            definition,
            actor,
            reason.unwrap_or("automation circuit reset"),
        )
        .await
    }

    pub async fn reset_expired_automation_circuits(
        &self,
        now: chrono::DateTime<Utc>,
        actor: AutomationActor,
    ) -> Result<(usize, Vec<String>)> {
        let definitions = self.list_automations(false).await?;
        let mut reset = 0usize;
        let mut errors = Vec::new();
        for definition in definitions {
            if !definition.circuit_opened {
                continue;
            }
            if !definition.circuit_reset_due(now) {
                continue;
            }
            let id = definition.id.clone();
            match self
                .reset_opened_automation_circuit(
                    definition,
                    actor.clone(),
                    "automation circuit open duration elapsed",
                )
                .await
            {
                Ok(_) => reset += 1,
                Err(error) => errors.push(format!("{id}: {error}")),
            }
        }
        Ok((reset, errors))
    }

    async fn reset_opened_automation_circuit(
        &self,
        mut definition: AutomationDefinition,
        actor: AutomationActor,
        reason: &str,
    ) -> Result<AutomationDefinition> {
        let restore_active =
            definition.state == AutomationState::Blocked && definition.is_approved();
        definition.circuit_opened = false;
        definition.circuit_opened_at = None;
        if restore_active {
            definition.state = AutomationState::Active;
        }
        definition.updated_at = Utc::now();
        definition.modified_by = actor.clone();
        let encoded = serde_json::to_string(&definition)?;
        let actor_json = serde_json::to_string(&actor)?;
        let details = serde_json::to_string(&serde_json::json!({ "reason": reason }))?;
        let mut transaction = self.pool().begin().await?;
        sqlx::query("UPDATE automations SET state = ?, dataJson = ?, updatedAt = ? WHERE id = ?")
            .bind(definition.state.as_str())
            .bind(&encoded)
            .bind(format_timestamp(definition.updated_at))
            .bind(&definition.id)
            .execute(&mut *transaction)
            .await?;
        sqlx::query(
            "INSERT INTO automationAuditEvents (id, automationId, runId, action, actorJson, revision, detailsJson, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(Uuid::new_v4().to_string())
        .bind(&definition.id)
        .bind(None::<String>)
        .bind("circuitReset")
        .bind(&actor_json)
        .bind(definition.revision)
        .bind(&details)
        .bind(format_timestamp(definition.updated_at))
        .execute(&mut *transaction)
        .await?;
        if restore_active {
            sqlx::query(
                "INSERT INTO automationAuditEvents (id, automationId, runId, action, actorJson, revision, detailsJson, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            )
            .bind(Uuid::new_v4().to_string())
            .bind(&definition.id)
            .bind(None::<String>)
            .bind(AutomationState::Active.as_str())
            .bind(&actor_json)
            .bind(definition.revision)
            .bind(&details)
            .bind(format_timestamp(definition.updated_at))
            .execute(&mut *transaction)
            .await?;
        }
        transaction.commit().await?;
        Ok(definition)
    }
}
