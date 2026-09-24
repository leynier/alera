use anyhow::{anyhow, bail, Context, Result};

#[derive(Debug, clap::Args)]
pub(crate) struct CloneCheckoutArgs {
    #[arg(long)]
    pub url: String,
    #[arg(long)]
    pub path: String,
}

pub(crate) async fn clone_checkout(
    args: CloneCheckoutArgs,
) -> Result<crate::project_checkout_inspection::CheckoutInspection> {
    let environment = crate::login_shell_environment::login_shell_command_environment()
        .await
        .unwrap_or_default();
    let path = tokio::task::spawn_blocking(move || {
        if args.url.trim().is_empty() { bail!("A clone source is required"); }
        let requested = std::path::Path::new(&args.path);
        if !requested.is_absolute() { bail!("An absolute clone destination is required"); }
        let parent = requested.parent().ok_or_else(|| anyhow!("A clone destination parent is required"))?;
        let name = requested.file_name().ok_or_else(|| anyhow!("A new clone directory name is required"))?;
        let destination = std::fs::canonicalize(parent).context("The clone parent directory is unavailable")?.join(name);
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
