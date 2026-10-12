use anyhow::Result;
use sqlx::SqliteConnection;

/// Run tables in dependency order. Later steps replace triggers an earlier
/// step installed, so the order is part of the schema.
pub(super) async fn install_run_schema(conn: &mut SqliteConnection) -> Result<()> {
    super::run_catalog_store::install_recipe_catalog_schema(conn).await?;
    super::run_plan_schema::install(conn).await?;
    super::run_workspace_schema::install(conn).await?;
    super::run_integration_schema::install(conn).await?;
    super::run_launch_schema::install(conn).await?;
    super::run_execution::install_execution_schema(conn).await?;
    super::run_cleanup::install_cleanup_schema(conn).await
}
