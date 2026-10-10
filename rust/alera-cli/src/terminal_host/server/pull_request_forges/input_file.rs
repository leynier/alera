//! A request body handed to a forge CLI as a file (`az devops invoke
//! --in-file`), so free text never reaches its command line.
//!
//! This is what `tempfile::NamedTempFile` provides, written out because
//! `tempfile` is only a dev-dependency of this crate: a fresh name opened with
//! `create_new` (`O_EXCL`, so a planted file or symlink is refused, never
//! followed), owner-only on unix, and removed when the guard drops.

use std::io::Write;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

/// The temporary body file; dropping it removes the file, including when the
/// request times out or its future is cancelled.
#[derive(Debug)]
pub(super) struct InputFile {
    path: PathBuf,
}

impl InputFile {
    pub(super) fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for InputFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

/// [body] in a new file in the per-user temp directory that only its owner
/// can read (0600 on unix; on Windows the user's temp directory already
/// carries an owner-only ACL). The handle is closed before the CLI opens it.
pub(super) fn json_input_file(body: &Value) -> HostResult<InputFile> {
    let failed =
        |error: std::io::Error| HostError::state(format!("Could not write the request: {error}"));
    let path = std::env::temp_dir().join(format!("alera-pr-{}.json", uuid::Uuid::new_v4()));
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&path).map_err(failed)?;
    // From here on the guard owns the file, so a failed write removes it.
    let guard = InputFile { path };
    file.write_all(body.to_string().as_bytes())
        .and_then(|_| file.flush())
        .map_err(failed)?;
    Ok(guard)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_body_file_is_private_and_removed_on_drop() {
        let file = json_input_file(&serde_json::json!({ "content": "secret" })).unwrap();
        let location = file.path().to_path_buf();
        assert_eq!(
            std::fs::read_to_string(&location).unwrap(),
            r#"{"content":"secret"}"#
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&location).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        drop(file);
        assert!(!location.exists());
    }
}
