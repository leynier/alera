use anyhow::{bail, Result};
use sqlx::Row;

use super::workflow_catalog::workflow_blocking;
use super::workflow_project_files::CATALOG_MAX_ENTRIES;
use super::{RuntimeStore, WorkflowCatalogRecipe, WorkflowRecipeSource, WorkflowRecipeV1};

impl RuntimeStore {
    pub(super) async fn migrate_workflow_catalog(&self) -> Result<()> {
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS personalWorkflowRecipes (
            id TEXT PRIMARY KEY NOT NULL,
            revision INTEGER NOT NULL CHECK(revision > 0),
            document TEXT NOT NULL CHECK(length(CAST(document AS BLOB)) <= 262144)
        )",
        )
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub(super) async fn personal_workflow_documents(&self) -> Result<Vec<(String, i64, String)>> {
        let rows = sqlx::query(
            "SELECT id, revision, document FROM personalWorkflowRecipes ORDER BY id LIMIT ?",
        )
        .bind((CATALOG_MAX_ENTRIES + 1) as i64)
        .fetch_all(self.pool())
        .await?;
        if rows.len() > CATALOG_MAX_ENTRIES {
            bail!("personal workflow catalog exceeds the entry limit");
        }
        rows.iter()
            .map(|row| {
                Ok((
                    row.try_get("id")?,
                    row.try_get("revision")?,
                    row.try_get("document")?,
                ))
            })
            .collect()
    }

    pub async fn save_personal_workflow_recipe(
        &self,
        document: String,
        expected_revision: Option<i64>,
    ) -> Result<WorkflowCatalogRecipe> {
        if expected_revision.is_some_and(|revision| revision < 1) {
            bail!("expected catalog revision must be positive");
        }
        let (recipe, digest, canonical) = workflow_blocking(move || {
            let recipe = WorkflowRecipeV1::from_yaml(&document)?;
            Ok((
                recipe.clone(),
                recipe.content_digest()?,
                recipe.portable_document()?,
            ))
        })
        .await?;
        let mut transaction = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let current: Option<i64> =
            sqlx::query_scalar("SELECT revision FROM personalWorkflowRecipes WHERE id = ?")
                .bind(&recipe.id)
                .fetch_optional(&mut *transaction)
                .await?;
        if current != expected_revision {
            bail!("personal workflow recipe changed; refresh before saving");
        }
        if current.is_none() {
            let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM personalWorkflowRecipes")
                .fetch_one(&mut *transaction)
                .await?;
            if count >= CATALOG_MAX_ENTRIES as i64 {
                bail!("personal workflow catalog is full");
            }
        }
        let revision = current
            .unwrap_or(0)
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("catalog revision exhausted"))?;
        sqlx::query("INSERT INTO personalWorkflowRecipes (id, revision, document) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET revision = excluded.revision, document = excluded.document")
            .bind(&recipe.id).bind(revision).bind(canonical).execute(&mut *transaction).await?;
        transaction.commit().await?;
        Ok(WorkflowCatalogRecipe {
            source: WorkflowRecipeSource::Personal {
                id: recipe.id.clone(),
            },
            catalog_revision: Some(revision),
            digest,
            recipe,
        })
    }
}
