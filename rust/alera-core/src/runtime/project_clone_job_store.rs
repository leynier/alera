use anyhow::Result;
use chrono::{DateTime, Utc};
use sqlx::Row;

use super::{ProjectCloneJob, ProjectCloneJobPhase, ProjectCloneJobStatus, RuntimeStore};

pub(super) const PROJECT_CLONE_JOB_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS projectCloneJobs (
        id TEXT PRIMARY KEY,
        source TEXT NOT NULL,
        parentPath TEXT NOT NULL,
        directoryName TEXT NOT NULL,
        destinationPath TEXT NOT NULL,
        projectName TEXT,
        status TEXT NOT NULL,
        phase TEXT NOT NULL,
        progressPercent INTEGER,
        message TEXT,
        error TEXT,
        projectId TEXT,
        workspaceId TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        finishedAt TEXT
    );",
    "CREATE INDEX IF NOT EXISTS projectCloneJobsCreatedAtIdx ON projectCloneJobs(createdAt DESC);",
];

impl RuntimeStore {
    pub async fn insert_project_clone_job(&self, job: ProjectCloneJob) -> Result<ProjectCloneJob> {
        sqlx::query(
            "INSERT INTO projectCloneJobs (id, source, parentPath, directoryName, destinationPath, \
             projectName, status, phase, progressPercent, message, error, projectId, workspaceId, \
             createdAt, updatedAt, finishedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&job.id)
        .bind(&job.source)
        .bind(&job.parent_path)
        .bind(&job.directory_name)
        .bind(&job.destination_path)
        .bind(&job.project_name)
        .bind(job.status.as_str())
        .bind(job.phase.as_str())
        .bind(job.progress_percent)
        .bind(&job.message)
        .bind(&job.error)
        .bind(&job.project_id)
        .bind(&job.workspace_id)
        .bind(format_timestamp(job.created_at))
        .bind(format_timestamp(job.updated_at))
        .bind(job.finished_at.map(format_timestamp))
        .execute(self.pool())
        .await?;
        Ok(job)
    }

    pub async fn list_project_clone_jobs(&self) -> Result<Vec<ProjectCloneJob>> {
        let rows = sqlx::query(
            "SELECT id, source, parentPath, directoryName, destinationPath, projectName, status, \
             phase, progressPercent, message, error, projectId, workspaceId, createdAt, updatedAt, \
             finishedAt FROM projectCloneJobs ORDER BY createdAt DESC",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(project_clone_job_from_row).collect()
    }

    pub async fn find_project_clone_job(&self, id: &str) -> Result<Option<ProjectCloneJob>> {
        let row = sqlx::query(
            "SELECT id, source, parentPath, directoryName, destinationPath, projectName, status, \
             phase, progressPercent, message, error, projectId, workspaceId, createdAt, updatedAt, \
             finishedAt FROM projectCloneJobs WHERE id = ?",
        )
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(project_clone_job_from_row).transpose()
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn update_project_clone_job(
        &self,
        id: &str,
        status: ProjectCloneJobStatus,
        phase: ProjectCloneJobPhase,
        progress_percent: Option<i64>,
        message: Option<&str>,
        error: Option<&str>,
        project_id: Option<&str>,
        workspace_id: Option<&str>,
    ) -> Result<Option<ProjectCloneJob>> {
        let now = Utc::now();
        let finished_at = status.is_terminal().then_some(now);
        sqlx::query(
            "UPDATE projectCloneJobs SET status = ?, phase = ?, progressPercent = ?, message = ?, \
             error = ?, projectId = ?, workspaceId = ?, updatedAt = ?, finishedAt = ? WHERE id = ?",
        )
        .bind(status.as_str())
        .bind(phase.as_str())
        .bind(progress_percent)
        .bind(message)
        .bind(error)
        .bind(project_id)
        .bind(workspace_id)
        .bind(format_timestamp(now))
        .bind(finished_at.map(format_timestamp))
        .bind(id)
        .execute(self.pool())
        .await?;
        self.find_project_clone_job(id).await
    }

    pub async fn list_interrupted_project_clone_jobs(&self) -> Result<Vec<ProjectCloneJob>> {
        Ok(self
            .list_project_clone_jobs()
            .await?
            .into_iter()
            .filter(|job| !job.status.is_terminal())
            .collect())
    }
}

fn project_clone_job_from_row(row: sqlx::sqlite::SqliteRow) -> Result<ProjectCloneJob> {
    Ok(ProjectCloneJob {
        id: row.try_get("id")?,
        source: row.try_get("source")?,
        parent_path: row.try_get("parentPath")?,
        directory_name: row.try_get("directoryName")?,
        destination_path: row.try_get("destinationPath")?,
        project_name: row.try_get("projectName")?,
        status: ProjectCloneJobStatus::from_db(row.try_get::<String, _>("status")?.as_str()),
        phase: ProjectCloneJobPhase::from_db(row.try_get::<String, _>("phase")?.as_str()),
        progress_percent: row.try_get("progressPercent")?,
        message: row.try_get("message")?,
        error: row.try_get("error")?,
        project_id: row.try_get("projectId")?,
        workspace_id: row.try_get("workspaceId")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
        finished_at: row
            .try_get::<Option<String>, _>("finishedAt")?
            .map(|value| parse_timestamp(&value)),
    })
}

fn format_timestamp(value: DateTime<Utc>) -> String {
    value.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

fn parse_timestamp(value: &str) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(value)
        .map(|value| value.with_timezone(&Utc))
        .unwrap_or_else(|_| DateTime::<Utc>::from(std::time::UNIX_EPOCH))
}
