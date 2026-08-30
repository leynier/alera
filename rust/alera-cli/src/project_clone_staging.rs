use std::fs::{self, OpenOptions};
use std::io::Write as _;
use std::path::{Path, PathBuf};

use anyhow::{Context as _, Result, bail, ensure};
use uuid::Uuid;

const OWNER_FILE: &str = "owner";
const OWNER_VERSION: &str = "alera-project-clone-v1";

#[derive(Clone)]
pub(crate) struct ProjectCloneStaging {
    parent: PathBuf,
    root: PathBuf,
    job_id: Uuid,
}

impl ProjectCloneStaging {
    pub(crate) fn for_job(parent: &str, job_id: &str) -> Result<Self> {
        let parent = fs::canonicalize(parent).context("Clone parent is unavailable")?;
        let job_id = Uuid::parse_str(job_id).context("Invalid clone job identity")?;
        let root = parent.join(format!(".alera-clone-{job_id}"));
        Ok(Self { parent, root, job_id })
    }

    pub(crate) fn create(parent: &str, job_id: &str) -> Result<Self> {
        let staging = Self::for_job(parent, job_id)?;
        fs::create_dir(&staging.root).context("Could not reserve clone staging directory")?;
        let marker = OpenOptions::new().write(true).create_new(true).open(staging.root.join(OWNER_FILE));
        match marker {
            Ok(mut marker) => {
                marker.write_all(staging.owner().as_bytes()).context("Could not write clone ownership marker")?;
                marker.sync_all().context("Could not persist clone ownership marker")?;
            }
            Err(error) => {
                // Only an empty directory may be removed if marker creation
                // failed; do not recursively remove an unmarked path.
                let _ = fs::remove_dir(&staging.root);
                return Err(error).context("Could not create clone ownership marker");
            }
        }
        Ok(staging)
    }

    pub(crate) fn checkout_path(&self) -> PathBuf { self.root.join("repository") }

    pub(crate) fn publish(&self, destination: &Path) -> Result<()> {
        self.verify_owner()?;
        let parent = destination.parent().context("Clone destination has no parent")?;
        let name = destination.file_name().context("Clone destination has no directory name")?;
        ensure!(fs::canonicalize(parent)? == self.parent, "Unsafe clone publication parent");
        let destination = self.parent.join(name);
        ensure!(destination != self.root, "Unsafe clone publication destination");
        let source = self.checkout_path();
        let metadata = fs::symlink_metadata(&source).context("Clone checkout is missing")?;
        ensure!(metadata.is_dir() && !metadata.file_type().is_symlink(), "Clone checkout is not an owned directory");
        crate::project_clone_publish::publish_directory_without_replacing(&source, &destination)
    }

    pub(crate) fn cleanup(&self) -> Result<()> {
        match fs::symlink_metadata(&self.root) {
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(error).context("Could not inspect clone staging directory"),
            Ok(_) => {}
        }
        self.verify_owner()?;
        fs::remove_dir_all(&self.root).context("Could not remove owned clone staging directory")
    }

    fn owner(&self) -> String { format!("{OWNER_VERSION}\n{}\n", self.job_id) }

    fn verify_owner(&self) -> Result<()> {
        let metadata = fs::symlink_metadata(&self.root)?;
        ensure!(metadata.is_dir() && !metadata.file_type().is_symlink(), "Refusing cleanup of a replaced clone staging directory");
        let marker_path = self.root.join(OWNER_FILE);
        let marker = fs::symlink_metadata(&marker_path).context("Clone staging has no ownership marker")?;
        ensure!(marker.is_file() && !marker.file_type().is_symlink() && marker.len() <= 128, "Invalid clone ownership marker");
        let owner = fs::read_to_string(marker_path).context("Could not read clone ownership marker")?;
        if owner != self.owner() { bail!("Clone staging ownership does not match this job"); }
        Ok(())
    }
}

pub(crate) async fn cleanup_clone_staging(parent: &str, job_id: &str) -> Result<()> {
    let parent = parent.to_owned();
    let job_id = job_id.to_owned();
    tokio::task::spawn_blocking(move || ProjectCloneStaging::for_job(&parent, &job_id)?.cleanup()).await?
}

#[cfg(test)]
mod tests {
    use super::*;

    fn prepared(parent: &Path, marker: &str) -> ProjectCloneStaging {
        let staging = ProjectCloneStaging::create(parent.to_str().unwrap(), &Uuid::new_v4().to_string()).unwrap();
        fs::create_dir(staging.checkout_path()).unwrap();
        fs::write(staging.checkout_path().join("sentinel"), marker).unwrap();
        staging
    }

    #[test]
    fn clone_staging_competing_publish_keeps_the_winners_directory() {
        let parent = tempfile::tempdir().unwrap();
        let destination = parent.path().join("repo");
        let first = prepared(parent.path(), "first");
        let second = prepared(parent.path(), "second");
        let results = std::thread::scope(|scope| {
            let a = scope.spawn(|| first.publish(&destination));
            let b = scope.spawn(|| second.publish(&destination));
            [a.join().unwrap(), b.join().unwrap()]
        });
        assert_eq!(results.iter().filter(|result| result.is_ok()).count(), 1, "{results:?}");
        let winner = fs::read_to_string(destination.join("sentinel")).unwrap();
        first.cleanup().unwrap();
        second.cleanup().unwrap();
        assert_eq!(fs::read_to_string(destination.join("sentinel")).unwrap(), winner);
    }

    #[test]
    fn clone_staging_never_replaces_even_an_empty_existing_destination() {
        let parent = tempfile::tempdir().unwrap();
        let staging = prepared(parent.path(), "clone");
        let destination = parent.path().join("existing");
        fs::create_dir(&destination).unwrap();
        assert!(staging.publish(&destination).is_err());
        staging.cleanup().unwrap();
        assert_eq!(fs::read_dir(&destination).unwrap().count(), 0);
    }

    #[test]
    fn clone_staging_recovery_keeps_legacy_destinations_without_ownership() {
        let parent = tempfile::tempdir().unwrap();
        let destination = parent.path().join("repo");
        fs::create_dir(&destination).unwrap();
        fs::write(destination.join("keep"), "legacy or competing clone").unwrap();
        ProjectCloneStaging::for_job(parent.path().to_str().unwrap(), &Uuid::new_v4().to_string()).unwrap().cleanup().unwrap();
        assert!(destination.join("keep").exists());
    }

    #[test]
    fn clone_staging_rejects_a_replaced_or_missing_marker() {
        let parent = tempfile::tempdir().unwrap();
        let staging = prepared(parent.path(), "keep");
        fs::write(staging.root.join(OWNER_FILE), "someone else").unwrap();
        assert!(staging.cleanup().is_err());
        assert!(staging.checkout_path().join("sentinel").exists());
        assert!(ProjectCloneStaging::create(parent.path().to_str().unwrap(), &staging.job_id.to_string()).is_err());
        assert!(ProjectCloneStaging::for_job(parent.path().to_str().unwrap(), "../../escape").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn clone_staging_refuses_symlinks_instead_of_cleaning_their_targets() {
        let parent = tempfile::tempdir().unwrap();
        let victim = parent.path().join("keep");
        fs::create_dir(&victim).unwrap();
        let staging = ProjectCloneStaging::for_job(parent.path().to_str().unwrap(), &Uuid::new_v4().to_string()).unwrap();
        std::os::unix::fs::symlink(&victim, &staging.root).unwrap();
        assert!(staging.cleanup().is_err());
        assert!(victim.is_dir());
    }
}
