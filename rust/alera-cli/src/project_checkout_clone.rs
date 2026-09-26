use anyhow::{anyhow, bail, Context, Result};

#[derive(Debug, clap::Args)]
pub(crate) struct CloneCheckoutArgs {
    #[arg(long)]
    pub url: String,
    /// The new directory to clone into. Without it, `--name` picks one under
    /// this host's default projects folder.
    #[arg(long)]
    pub path: Option<String>,
    /// Directory name for a clone under the projects folder.
    #[arg(long)]
    pub name: Option<String>,
    /// The projects folder to use instead of `alera-projects` under the home
    /// directory. `~/...` and `%VAR%` are expanded here, on the host.
    #[arg(long)]
    pub projects_dir: Option<String>,
}

/// Where a project lands on a host when the user did not choose a path.
pub(crate) const DEFAULT_PROJECTS_DIR_NAME: &str = "alera-projects";

/// `<home>/alera-projects/<name>`, or the first `<name>-N` that is free, with
/// the projects folder created on demand. Only this host knows its home
/// directory, which is why the hub sends a name instead of a path.
fn default_clone_destination(name: &str, projects_dir: Option<&str>) -> Result<std::path::PathBuf> {
    let name = name.trim();
    if name.is_empty() || name == "." || name == ".." || name.contains(['/', '\\', ':']) {
        bail!("A plain directory name is required for the clone");
    }
    let home = dirs::home_dir().ok_or_else(|| anyhow!("This host has no home directory"))?;
    let projects = match projects_dir
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        Some(configured) => expand_projects_dir(configured, &home)?,
        None => home.join(DEFAULT_PROJECTS_DIR_NAME),
    };
    std::fs::create_dir_all(&projects)
        .with_context(|| format!("The projects folder {} is unavailable", projects.display()))?;
    Ok(first_free_destination(&projects, name))
}

/// The configured folder as an absolute path on this host. The hub stores the
/// text the user typed for a machine it is not on, so `~/`, `$HOME` and `%VAR%`
/// are resolved here, where they mean something. A relative path is taken
/// under the home directory, never under the sidecar's working directory.
fn expand_projects_dir(configured: &str, home: &std::path::Path) -> Result<std::path::PathBuf> {
    let mut expanded = String::with_capacity(configured.len());
    let mut rest = configured;
    while let Some(start) = rest.find('%') {
        let Some(length) = rest[start + 1..].find('%') else {
            break;
        };
        let name = &rest[start + 1..start + 1 + length];
        expanded.push_str(&rest[..start]);
        match std::env::var(name) {
            Ok(value) if !name.is_empty() => expanded.push_str(&value),
            _ => bail!("The projects folder names %{name}%, which is not set on this host"),
        }
        rest = &rest[start + 2 + length..];
    }
    expanded.push_str(rest);
    let expanded = if let Some(tail) = expanded
        .strip_prefix("~/")
        .or_else(|| expanded.strip_prefix("~\\"))
    {
        home.join(tail)
    } else if expanded == "~" {
        home.to_path_buf()
    } else if let Some(tail) = expanded.strip_prefix("$HOME/") {
        home.join(tail)
    } else {
        std::path::PathBuf::from(expanded)
    };
    Ok(if expanded.is_absolute() {
        expanded
    } else {
        home.join(expanded)
    })
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
            (_, Some(name)) => default_clone_destination(name, args.projects_dir.as_deref())?,
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
