use anyhow::{bail, Result};

use super::default_install_dir;

pub(super) fn local_home_dir() -> Option<String> {
    dirs::home_dir().map(|path| path.to_string_lossy().into_owned())
}

/// Rewrites or rejects an install dir that is not valid on `platform`.
///
/// Local-shell `~` expansion (Linux `/home/<user>/...`, macOS `/Users/<user>/...`)
/// is folded back to `~/...` for POSIX remotes so the remote home is used.
/// Remaining Linux `/home/...` paths are rewritten to `/Users/...` on macOS
/// because `/home` is autofs there. See #675.
pub(super) fn prepare_remote_install_dir(
    platform: &str,
    install_dir: &str,
    local_home: Option<&str>,
) -> Result<String> {
    let trimmed = install_dir.trim();
    if trimmed.is_empty() {
        return Ok(default_install_dir(platform));
    }
    let candidate = if platform == "windows" {
        trimmed.to_string()
    } else {
        rewrite_local_home_to_tilde(trimmed, local_home)
    };
    match platform {
        "windows" => prepare_windows_install_dir(trimmed),
        "macos" => prepare_macos_install_dir(&candidate),
        "linux" => prepare_linux_install_dir(&candidate),
        _ => Ok(candidate),
    }
}

fn rewrite_local_home_to_tilde(install_dir: &str, local_home: Option<&str>) -> String {
    let Some(home) = local_home.map(str::trim).filter(|value| !value.is_empty()) else {
        return install_dir.to_string();
    };
    if is_tilde_path(install_dir) {
        return install_dir.to_string();
    }
    let home = posix_slashes(home).trim_end_matches('/').to_string();
    let dir = posix_slashes(install_dir);
    let dir_trimmed = dir.trim_end_matches('/');
    if dir_trimmed == home {
        return "~".to_string();
    }
    match dir_trimmed.strip_prefix(&format!("{home}/")) {
        Some(rest) if !rest.is_empty() => format!("~/{rest}"),
        Some(_) => "~".to_string(),
        None => install_dir.to_string(),
    }
}

fn prepare_macos_install_dir(install_dir: &str) -> Result<String> {
    if looks_like_windows_path(install_dir) {
        bail!(
            "install directory {install_dir} is not valid on macOS; use ~/.alera/sidecar or a path under /Users."
        );
    }
    if looks_like_linux_home_path(install_dir) {
        return rewrite_linux_home_prefix_to_macos(install_dir);
    }
    Ok(install_dir.to_string())
}

fn prepare_linux_install_dir(install_dir: &str) -> Result<String> {
    if looks_like_windows_path(install_dir) {
        bail!(
            "install directory {install_dir} is not valid on Linux; use ~/.alera/sidecar or an absolute POSIX path."
        );
    }
    Ok(install_dir.to_string())
}

fn prepare_windows_install_dir(install_dir: &str) -> Result<String> {
    if is_tilde_path(install_dir)
        || looks_like_linux_home_path(install_dir)
        || looks_like_macos_users_path(install_dir)
    {
        bail!(
            "install directory {install_dir} is not valid on Windows; use %LOCALAPPDATA%\\Alera\\runtime or an absolute Windows path."
        );
    }
    Ok(install_dir.to_string())
}

fn rewrite_linux_home_prefix_to_macos(install_dir: &str) -> Result<String> {
    let trimmed = posix_slashes(install_dir).trim_end_matches('/').to_string();
    if trimmed == "/home" {
        bail!("{}", macos_linux_home_error(install_dir));
    }
    let Some(rest) = trimmed.strip_prefix("/home/") else {
        return Ok(install_dir.to_string());
    };
    Ok(format!("/Users/{rest}"))
}

fn macos_linux_home_error(install_dir: &str) -> String {
    format!(
        "install directory {install_dir} uses the Linux home prefix /home, which is autofs on macOS; use ~/.alera/sidecar or a path under /Users."
    )
}

fn is_tilde_path(value: &str) -> bool {
    value == "~" || value.starts_with("~/")
}

fn looks_like_linux_home_path(install_dir: &str) -> bool {
    let trimmed = posix_slashes(install_dir).trim_end_matches('/').to_string();
    trimmed == "/home" || trimmed.starts_with("/home/")
}

fn looks_like_macos_users_path(install_dir: &str) -> bool {
    let trimmed = posix_slashes(install_dir).trim_end_matches('/').to_string();
    trimmed == "/Users" || trimmed.starts_with("/Users/")
}

fn looks_like_windows_path(install_dir: &str) -> bool {
    let normalized = posix_slashes(install_dir);
    if normalized.to_ascii_uppercase().contains("%LOCALAPPDATA%")
        || normalized.to_ascii_uppercase().contains("%USERPROFILE%")
    {
        return true;
    }
    let without_leading = normalized.trim_start_matches('/');
    let mut chars = without_leading.chars();
    matches!(
        (chars.next(), chars.next()),
        (Some(drive), Some(':')) if drive.is_ascii_alphabetic()
    )
}

fn posix_slashes(value: &str) -> String {
    value.replace('\\', "/")
}
