use sea_orm::entity::prelude::*;

/// SeaORM entity mapping the pre-existing `checkpoints` table. The schema is
/// owned externally (created by either host implementation's DDL); SeaORM does
/// not manage migrations for it. Column names mirror the camelCase Dart columns.
#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "checkpoints")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_name = "sessionId")]
    pub session_id: String,
    #[sea_orm(column_name = "workspaceId")]
    pub workspace_id: String,
    #[sea_orm(column_name = "tabId")]
    pub tab_id: String,
    #[sea_orm(column_name = "workingDirectory")]
    pub working_directory: String,
    pub running: i32,
    #[sea_orm(column_name = "exitCode")]
    pub exit_code: Option<i32>,
    #[sea_orm(column_name = "endedAt")]
    pub ended_at: Option<String>,
    #[sea_orm(column_name = "updatedAt")]
    pub updated_at: String,
    pub buffer: Vec<u8>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
