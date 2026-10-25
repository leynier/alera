//! The Claude path scope: `claude purge <path> --yes` once for the default
//! config dir and once per CCS instance. Purge removes a whole project at
//! once, so a project that still holds a preserved session is cleaned one
//! transcript at a time instead.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use super::claude::{
    ccs_instances_dir, default_config_dir, remove_session_files, CONFIG_DIR_VARIABLE,
};
use super::cleanup_context::CleanupContext;
use super::session_id_rules::is_storage_entry_name;
use super::storage_removal::StorageRoot;
use super::{blocking, first_failure, CleanupFailure};

/// Claude's limit before it shortens a project directory name with a hash.
const PROJECT_DIR_NAME_LIMIT: usize = 200;

struct PurgeTarget {
    config_dir: PathBuf,
    env: BTreeMap<String, String>,
}

enum ProjectCleanup {
    Purge,
    /// Transcripts to remove one by one, because a preserved one sits beside them.
    Sessions(Vec<String>),
    /// A preserved session sits in a hashed directory that cannot be tied to
    /// this path, so nothing there is touched.
    Unresolved,
}

/// `None` when no Claude config dir exists on this machine.
pub(super) async fn purge_workspace(
    context: &CleanupContext,
    paths: &[String],
    preserved: &[String],
) -> Option<Result<(), CleanupFailure>> {
    let targets = {
        let context = context.clone();
        blocking(move || Ok(purge_targets(&context))).await
    };
    let targets = match targets {
        Ok(targets) if targets.is_empty() => return None,
        Ok(targets) => targets,
        Err(failure) => return Some(Err(failure)),
    };
    let mut results = Vec::new();
    for target in &targets {
        for path in paths {
            results.push(purge_project(context, target, path, preserved).await);
        }
    }
    Some(first_failure(results))
}

async fn purge_project(
    context: &CleanupContext,
    target: &PurgeTarget,
    path: &str,
    preserved: &[String],
) -> Result<(), CleanupFailure> {
    let config_dir = target.config_dir.clone();
    let (owned_path, preserved) = (path.to_string(), preserved.to_vec());
    let cleanup = blocking(move || project_cleanup(&config_dir, &owned_path, &preserved)).await?;
    match cleanup {
        ProjectCleanup::Purge => {
            context
                .run_command("claude", &["purge", path, "--yes"], &target.env)
                .await
        }
        ProjectCleanup::Sessions(ids) => {
            let config_dir = target.config_dir.clone();
            blocking(move || {
                first_failure(ids.iter().map(|id| remove_session_files(&config_dir, id)))
            })
            .await
        }
        ProjectCleanup::Unresolved => Err(CleanupFailure::new(
            "preserved_conflict",
            "kept a Claude project that may hold a preserved session",
        )),
    }
}

/// Claude's project directory name: every UTF-16 unit that is not an ASCII
/// letter or digit becomes `-`.
fn project_dir_name(path: &str) -> String {
    let mut name = String::with_capacity(path.len());
    for ch in path.chars() {
        if ch.is_ascii_alphanumeric() {
            name.push(ch);
        } else {
            name.extend(std::iter::repeat_n('-', ch.len_utf16()));
        }
    }
    name
}

fn project_cleanup(
    config_dir: &Path,
    path: &str,
    preserved: &[String],
) -> Result<ProjectCleanup, CleanupFailure> {
    if preserved.is_empty() {
        return Ok(ProjectCleanup::Purge);
    }
    let Some(projects) = StorageRoot::open(&config_dir.join("projects"))? else {
        return Ok(ProjectCleanup::Purge);
    };
    let name = project_dir_name(path);
    let holds_preserved = |directory: &Path| {
        preserved
            .iter()
            .any(|id| directory.join(format!("{id}.jsonl")).exists())
    };
    if name.len() > PROJECT_DIR_NAME_LIMIT {
        let prefix = format!("{}-", &name[..PROJECT_DIR_NAME_LIMIT]);
        let hashed = projects.entry_names(projects.path(), |entry, directory| {
            entry.starts_with(&prefix) && directory.is_dir() && holds_preserved(directory)
        })?;
        return Ok(if hashed.is_empty() {
            ProjectCleanup::Purge
        } else {
            ProjectCleanup::Unresolved
        });
    }
    let project = projects.entry(&name);
    if !holds_preserved(&project) {
        return Ok(ProjectCleanup::Purge);
    }
    let ids = projects
        .entry_names(&project, |entry, file| {
            entry.ends_with(".jsonl") && file.is_file()
        })?
        .into_iter()
        .filter_map(|entry| entry.strip_suffix(".jsonl").map(str::to_string))
        .filter(|id| is_storage_entry_name(id) && !preserved.contains(id))
        .collect();
    Ok(ProjectCleanup::Sessions(ids))
}

/// Config dirs to purge, each with the environment that selects it: the
/// default one as the login shell resolves it, then every CCS instance.
fn purge_targets(context: &CleanupContext) -> Vec<PurgeTarget> {
    let mut targets = Vec::new();
    let mut seen = Vec::<PathBuf>::new();
    let default = default_config_dir(context);
    if let Ok(canonical) = dunce::canonicalize(&default) {
        seen.push(canonical);
        targets.push(PurgeTarget {
            config_dir: default,
            env: context.storage_env(&[CONFIG_DIR_VARIABLE]),
        });
    }
    let instances = ccs_instances_dir(context);
    let mut names = std::fs::read_dir(&instances)
        .map(|entries| {
            entries
                .flatten()
                .filter_map(|entry| entry.file_name().into_string().ok())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    names.sort();
    for name in names {
        let dir = instances.join(&name);
        if !is_storage_entry_name(&name) || name.starts_with('.') || !dir.is_dir() {
            continue;
        }
        let Ok(canonical) = dunce::canonicalize(&dir) else {
            continue;
        };
        if seen.contains(&canonical) {
            continue;
        }
        seen.push(canonical);
        targets.push(PurgeTarget {
            env: BTreeMap::from([(
                CONFIG_DIR_VARIABLE.to_string(),
                dir.to_string_lossy().into_owned(),
            )]),
            config_dir: dir,
        });
    }
    targets
}

#[cfg(test)]
#[path = "claude_purge_tests.rs"]
mod tests;
