use anyhow::{anyhow, bail, Context, Result};

#[derive(Debug, clap::Args)]
pub(crate) struct CloneCheckoutArgs {
    #[arg(long)]
    pub url: String,
    /// The new directory to clone into. Without it, `--name` picks one under
    /// this host's default projects folder.
    #[arg(long)]
    pub path: Option<String>,
    /// Directory name for a clone under the default projects folder.
    #[arg(long)]
    pub name: Option<String>,
}

/// Where a project lands on a host when the user did not choose a path.
pub(crate) const DEFAULT_PROJECTS_DIR_NAME: &str = "alera-projects";

/// `<home>/alera-projects/<name>`, or the first `<name>-N` that is free, with
/// the projects folder created on demand. Only this host knows its home
/// directory, which is why the hub sends a name instead of a path.
fn default_clone_destination(name: &str) -> Result<std::path::PathBuf> {
    let name = name.trim();
    if name.is_empty() || name == "." || name == ".." || name.contains(['/', '\\', ':']) {
        bail!("A plain directory name is required for the clone");
    }
    let home = dirs::home_dir().ok_or_else(|| anyhow!("This host has no home directory"))?;
    let projects = home.join(DEFAULT_PROJECTS_DIR_NAME);
    std::fs::create_dir_all(&projects).context("The default projects folder is unavailable")?;
    Ok(first_free_destination(&projects, name))
}

fn first_free_destination(projects: &std::path::Path, name: &str) -> std::path::PathBuf {
    let mut candidate = projects.join(name);
    let mut suffix = 2;
    while candidate.symlink_metadata().is_ok() {
        candidate = projects.join(format!("{name}-{suffix}"));
        suffix += 1;
    }
    candidate
}

pub(crate) async fn clone_checkout(
    args: CloneCheckoutArgs,
) -> Result<crate::project_checkout_inspection::CheckoutInspection> {
    let environment = crate::login_shell_environment::login_shell_command_environment()
        .await
        .unwrap_or_default();
    let path = tokio::task::spawn_blocking(move || {
        if args.url.trim().is_empty() { bail!("A clone source is required"); }
        let requested_path = match (args.path.as_deref(), args.name.as_deref()) {
            (Some(path), _) if !path.trim().is_empty() => std::path::PathBuf::from(path),
            (_, Some(name)) => default_clone_destination(name)?,
            _ => bail!("A clone destination or a directory name is required"),
        };
        let requested = requested_path.as_path();
        if !requested.is_absolute() { bail!("An absolute clone destination is required"); }
        let parent = requested.parent().ok_or_else(|| anyhow!("A clone destination parent is required"))?;
        let name = requested.file_name().ok_or_else(|| anyhow!("A new clone directory name is required"))?;
        let destination = crate::windows_path_form::canonicalize(parent).context("The clone parent directory is unavailable")?.join(name);
        // Exclusive creation rejects existing directories, including empty ones and symlinks.
        std::fs::create_dir(&destination).context("The clone destination must be a new directory; no existing files were changed")?;
        alera_core::git_cli::git_in_dir_with_environment(&destination, &["clone", "--", &args.url, "."], &environment)
            .map_err(|_| anyhow!("Clone failed. The destination was retained for inspection; verify the repository URL, access and credentials before trying a new destination"))?;
        destination.to_str().map(str::to_string).ok_or_else(|| anyhow!("Clone path is not valid UTF-8"))
    }).await??;
    crate::project_checkout_inspection::inspect(
        path,
        alera_core::runtime::ProjectKind::GitRepository,
    )
    .await
}

#[cfg(test)]
#[path = "project_checkout_clone_tests.rs"]
mod tests;
