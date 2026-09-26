use std::io::Read;
use std::path::Path;

use anyhow::{bail, Context, Result};
use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt, OpenOptionsSyncExt};
use cap_std::{ambient_authority, fs::Dir, fs::OpenOptions};

use super::orchestration_role_contract::artifact_path;
use super::WORKFLOW_DOCUMENT_MAX_BYTES;

pub(super) const CATALOG_MAX_ENTRIES: usize = 128;
const DIRECTORY_MAX_ENTRIES: usize = 2048;
const CATALOG_MAX_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug)]
pub(super) struct ProjectWorkflowDocument {
    pub path: String,
    pub source: Result<String>,
}

/// Hold directory capabilities throughout the read so replacing a parent with
/// a symlink cannot redirect a catalog request outside its workspace.
pub(super) fn read_project_workflow_documents(
    workspace: &Path,
) -> Result<Vec<ProjectWorkflowDocument>> {
    let root = Dir::open_ambient_dir(workspace, ambient_authority())?;
    let Some(alera) = optional_directory(&root, ".alera")? else {
        return Ok(Vec::new());
    };
    let Some(directory) = optional_directory(&alera, "workflows")? else {
        return Ok(Vec::new());
    };
    let mut names = Vec::new();
    for (index, entry) in directory.entries()?.enumerate() {
        if index >= DIRECTORY_MAX_ENTRIES {
            bail!("workflow directory exceeds the entry limit");
        }
        let name = entry?.file_name();
        if Path::new(&name).extension().is_none_or(|ext| ext != "yaml") {
            continue;
        }
        let name = name
            .into_string()
            .map_err(|_| anyhow::anyhow!("workflow filenames must be valid UTF-8"))?;
        names.push(name);
        if names.len() > CATALOG_MAX_ENTRIES {
            bail!("project workflow catalog allows at most {CATALOG_MAX_ENTRIES} recipes");
        }
    }
    names.sort();
    let mut total_bytes = 0;
    let mut documents = Vec::new();
    for name in names {
        let source = read_document(&directory, &name);
        if let Ok(source) = &source {
            total_bytes += source.len();
            if total_bytes > CATALOG_MAX_BYTES {
                bail!("project workflow catalog exceeds the byte limit");
            }
        }
        documents.push(ProjectWorkflowDocument {
            path: format!(".alera/workflows/{name}"),
            source,
        });
    }
    Ok(documents)
}

fn optional_directory(parent: &Dir, name: &str) -> Result<Option<Dir>> {
    match parent.symlink_metadata(name) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
        Ok(metadata) if !metadata.is_dir() || metadata.file_type().is_symlink() => {
            bail!("workflow catalog directory must not be a symlink or special file");
        }
        Ok(_) => {}
    }
    Ok(Some(parent.open_dir_nofollow(name)?))
}

fn read_document(directory: &Dir, name: &str) -> Result<String> {
    artifact_path(name)?;
    if name.contains('/') {
        bail!("workflow filename must be a single component");
    }
    let metadata = directory.symlink_metadata(name)?;
    if !metadata.is_file() || metadata.file_type().is_symlink() {
        bail!("workflow recipe must be a regular file, not a symlink");
    }
    let mut options = OpenOptions::new();
    // Nonblocking open also prevents a raced replacement with a Unix FIFO
    // from occupying a catalog worker indefinitely.
    options.read(true).follow(FollowSymlinks::No).nonblock(true);
    let file = directory.open_with(name, &options)?;
    if !file.metadata()?.is_file() {
        bail!("workflow recipe changed into a non-regular file");
    }
    let mut bytes = Vec::new();
    file.take((WORKFLOW_DOCUMENT_MAX_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > WORKFLOW_DOCUMENT_MAX_BYTES {
        bail!("workflow YAML exceeds the byte limit");
    }
    String::from_utf8(bytes).context("workflow YAML must be UTF-8")
}
