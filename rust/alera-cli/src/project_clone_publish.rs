use std::path::Path;

use anyhow::{Context as _, Result};

pub(crate) fn publish_directory_without_replacing(source: &Path, destination: &Path) -> Result<()> {
    publish(source, destination).with_context(|| {
        format!("Could not publish clone without replacing destination: {}", destination.display())
    })
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn publish(source: &Path, destination: &Path) -> Result<()> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt as _;
    let source = CString::new(source.as_os_str().as_bytes())?;
    let destination = CString::new(destination.as_os_str().as_bytes())?;
    // A check followed by ordinary rename can replace an empty directory
    // created by another client. Require the filesystem's exclusive move.
    #[cfg(target_os = "macos")]
    let result = unsafe {
        libc::renamex_np(source.as_ptr(), destination.as_ptr(), libc::RENAME_EXCL)
    };
    #[cfg(target_os = "linux")]
    let result = unsafe {
        libc::renameat2(libc::AT_FDCWD, source.as_ptr(), libc::AT_FDCWD, destination.as_ptr(), libc::RENAME_NOREPLACE)
    };
    if result == 0 { Ok(()) } else { Err(std::io::Error::last_os_error().into()) }
}

#[cfg(target_os = "windows")]
fn publish(source: &Path, destination: &Path) -> Result<()> {
    use std::os::windows::ffi::OsStrExt as _;
    use windows::{core::PCWSTR, Win32::Storage::FileSystem::{MoveFileExW, MOVE_FILE_FLAGS}};
    let source = source.as_os_str().encode_wide().collect::<Vec<_>>();
    let destination = destination.as_os_str().encode_wide().collect::<Vec<_>>();
    anyhow::ensure!(!source.contains(&0) && !destination.contains(&0), "Clone path contains NUL");
    let source = source.into_iter().chain([0]).collect::<Vec<_>>();
    let destination = destination.into_iter().chain([0]).collect::<Vec<_>>();
    // Without REPLACE_EXISTING or COPY_ALLOWED, this is a same-volume move
    // that fails instead of overwriting a competing destination.
    unsafe { MoveFileExW(PCWSTR(source.as_ptr()), PCWSTR(destination.as_ptr()), MOVE_FILE_FLAGS(0))?; }
    Ok(())
}

#[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
fn publish(_: &Path, _: &Path) -> Result<()> {
    anyhow::bail!("Exclusive clone publication is unsupported on this platform")
}
