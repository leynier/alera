use std::fs::{File, OpenOptions};
use std::path::Path;

pub(in crate::terminal_host::server) fn create_private_exclusive(
    path: &Path,
) -> std::io::Result<File> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
    options.open(path)
}

pub(in crate::terminal_host::server) fn open_nofollow(
    path: &Path,
    write: bool,
) -> std::io::Result<File> {
    let mut options = OpenOptions::new();
    options.read(true).write(write);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.custom_flags(libc::O_NOFOLLOW);
    }
    options.open(path)
}

#[cfg(unix)]
pub(in crate::terminal_host::server) fn restrict_to_owner(path: &Path) {
    use std::os::unix::fs::PermissionsExt as _;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700));
}

#[cfg(not(unix))]
pub(in crate::terminal_host::server) fn restrict_to_owner(_path: &Path) {}
