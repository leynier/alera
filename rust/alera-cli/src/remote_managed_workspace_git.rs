//! Local git-bundle helper for remote managed workspace create.

use std::path::Path;

use anyhow::{anyhow, Context, Result};
use uuid::Uuid;

pub(crate) struct GitBundle {
    pub(crate) path: std::path::PathBuf,
}

impl Drop for GitBundle {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

pub(crate) async fn write_git_bundle(repo_path: &str) -> Result<GitBundle> {
    let repo_path = repo_path.to_string();
    tokio::task::spawn_blocking(move || {
        let path = std::env::temp_dir().join(format!("alera-ws-{}.bundle", Uuid::new_v4()));
        let bundle_display = path
            .to_str()
            .ok_or_else(|| anyhow!("git bundle path is not valid UTF-8"))?
            .to_string();
        alera_core::git_cli::git_in_dir(
            Path::new(&repo_path),
            &["bundle", "create", &bundle_display, "--all"],
        )
        .map_err(|error| anyhow!(error.message))?;
        Ok(GitBundle { path })
    })
    .await
    .context("git bundle task failed")?
}
