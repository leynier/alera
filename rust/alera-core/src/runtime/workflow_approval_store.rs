use anyhow::{bail, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::workflow_gate_evidence::approval_state;
use super::workflow_plan::{workflow_digest, workflow_text};
use super::workflow_plan_store::ensure_no_active_work;
use super::RuntimeStore;
use crate::workflow_approval::{
    VerifiedWorkflowDecision, WorkflowApprovalChallenge, WorkflowDecision,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowDecisionReceipt {
    pub decision_id: String,
    pub run_id: String,
    pub reviewed_revision: i64,
    pub current_revision: i64,
    pub scope: String,
    pub decision: WorkflowDecision,
}

impl RuntimeStore {
    pub async fn workflow_approval_challenge(
        &self,
        run_id: &str,
        revision: i64,
        scope: &str,
        audience: &str,
    ) -> Result<WorkflowApprovalChallenge> {
        workflow_text(run_id, 160)?;
        workflow_text(scope, 100)?;
        workflow_text(audience, 160)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "DELETE FROM workflowApprovalChallenges WHERE expires_at < ? AND receipt IS NULL",
        )
        .bind(Utc::now().timestamp())
        .execute(&mut *tx)
        .await?;
        let outstanding: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM workflowApprovalChallenges WHERE receipt IS NULL",
        )
        .fetch_one(&mut *tx)
        .await?;
        if outstanding >= 128 {
            bail!("too many pending workflow approval challenges");
        }
        let state = approval_state(&mut tx, run_id, revision, scope).await?;
        let challenge = WorkflowApprovalChallenge {
            version: 1,
            nonce: uuid::Uuid::new_v4().to_string(),
            audience: audience.to_owned(),
            run_id: run_id.to_owned(),
            revision,
            scope: scope.to_owned(),
            plan_digest: state.plan.digest,
            evidence_digest: state.evidence_digest,
            integration_sha: state.integration_sha,
            expires_at: Utc::now().timestamp() + 300,
        };
        sqlx::query("INSERT INTO workflowApprovalChallenges(nonce, run_id, audience, statement, expires_at) VALUES (?, ?, ?, ?, ?)")
            .bind(&challenge.nonce).bind(run_id).bind(audience)
            .bind(serde_json::to_string(&challenge)?).bind(challenge.expires_at).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(challenge)
    }

    pub async fn decide_workflow(
        &self,
        verified: VerifiedWorkflowDecision,
        audience: &str,
    ) -> Result<WorkflowDecisionReceipt> {
        let statement = verified.statement();
        let challenge = &statement.challenge;
        let digest = workflow_digest(statement)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query(
            "SELECT statement, expires_at, decision_digest, receipt
            FROM workflowApprovalChallenges WHERE nonce = ?",
        )
        .bind(&challenge.nonce)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| anyhow::anyhow!("unknown workflow approval challenge"))?;
        if row.try_get::<String, _>("statement")? != serde_json::to_string(challenge)? {
            bail!("workflow approval challenge does not match");
        }
        if let Some(receipt) = row.try_get::<Option<String>, _>("receipt")? {
            if row
                .try_get::<Option<String>, _>("decision_digest")?
                .as_deref()
                != Some(digest.as_str())
            {
                bail!("workflow approval challenge was already consumed");
            }
            return Ok(serde_json::from_str(&receipt)?);
        }
        if challenge.audience != audience {
            bail!("workflow approval belongs to another desktop connection");
        }
        if row.try_get::<i64, _>("expires_at")? <= Utc::now().timestamp() {
            bail!("workflow approval challenge expired; review the current evidence");
        }
        let state = approval_state(
            &mut tx,
            &challenge.run_id,
            challenge.revision,
            &challenge.scope,
        )
        .await?;
        if state.plan.digest != challenge.plan_digest
            || state.evidence_digest != challenge.evidence_digest
            || state.integration_sha != challenge.integration_sha
        {
            bail!("workflow approval is stale; review the current plan and evidence");
        }
        let decision_id = uuid::Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT INTO workflowDecisions(id, run_id, revision, scope, decision, reason,
            plan_digest, evidence_digest, integration_sha) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&decision_id)
        .bind(&challenge.run_id)
        .bind(challenge.revision)
        .bind(&challenge.scope)
        .bind(serde_json::to_string(&statement.decision)?)
        .bind(&statement.reason)
        .bind(&challenge.plan_digest)
        .bind(&challenge.evidence_digest)
        .bind(&challenge.integration_sha)
        .execute(&mut *tx)
        .await?;
        let mut current_revision = challenge.revision;
        match statement.decision {
            WorkflowDecision::Approve if challenge.scope == "plan" => {
                super::workflow_plan_materialization::materialize(&mut tx, challenge, &state)
                    .await?;
            }
            WorkflowDecision::Approve => {
                sqlx::query(
                    "UPDATE workflowStageGates SET status = 'approved', decision_id = ?
                    WHERE run_id = ? AND revision = ? AND stage_id = ?",
                )
                .bind(&decision_id)
                .bind(&challenge.run_id)
                .bind(challenge.revision)
                .bind(challenge.scope.trim_start_matches("stage:"))
                .execute(&mut *tx)
                .await?;
            }
            WorkflowDecision::Reject | WorkflowDecision::RequestChanges => {
                ensure_no_active_work(&mut tx, &challenge.run_id).await?;
                let status = if statement.decision == WorkflowDecision::Reject {
                    "rejected"
                } else {
                    "changesRequested"
                };
                if statement.decision == WorkflowDecision::RequestChanges {
                    current_revision += 1;
                    sqlx::query("INSERT INTO workflowPlanRevisions
                        (run_id, revision, request_id, request_digest, snapshot, digest, previous_revision, change_reason)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
                        .bind(&challenge.run_id).bind(current_revision)
                        .bind(format!("decision:{decision_id}")).bind(&digest)
                        .bind(serde_json::to_string(&state.plan)?).bind(&state.plan.digest)
                        .bind(challenge.revision).bind(&statement.reason).execute(&mut *tx).await?;
                }
                sqlx::query("UPDATE workflowRuns SET status = ?, revision = ? WHERE run_id = ?")
                    .bind(status)
                    .bind(current_revision)
                    .bind(&challenge.run_id)
                    .execute(&mut *tx)
                    .await?;
                // Original completed evidence remains immutable and inspectable.
                sqlx::query("UPDATE orchestrationTasks SET status = 'cancelled', cancelled_at = datetime('now')
                    WHERE run_id = ? AND status IN ('pending','ready','blocked','failed')")
                    .bind(&challenge.run_id).execute(&mut *tx).await?;
                sqlx::query("UPDATE orchestrationCoordinatorRuns SET execution_policy_status = 'rejected' WHERE id = ?")
                    .bind(&challenge.run_id).execute(&mut *tx).await?;
            }
        }
        let receipt = WorkflowDecisionReceipt {
            decision_id,
            run_id: challenge.run_id.clone(),
            reviewed_revision: challenge.revision,
            current_revision,
            scope: challenge.scope.clone(),
            decision: statement.decision,
        };
        sqlx::query("UPDATE workflowApprovalChallenges SET decision_digest = ?, receipt = ? WHERE nonce = ?")
            .bind(&digest).bind(serde_json::to_string(&receipt)?).bind(&challenge.nonce)
            .execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(receipt)
    }
}
