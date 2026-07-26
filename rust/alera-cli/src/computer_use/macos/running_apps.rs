use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};

use crate::computer_use::contract::AppInfo;
use crate::computer_use::error::ComputerResult;
use crate::computer_use::macos::ax_tree::AxApplication;

/// Applications with at least one accessible window.
///
/// macOS has no accessibility-side application list, so the process table is
/// filtered to bundled applications and each candidate is asked whether it has
/// windows. Filtering first matters: asking every process on the machine would
/// mean hundreds of cross-process calls per listing.
pub fn list_apps() -> ComputerResult<Vec<AppInfo>> {
    let mut apps = Vec::new();
    for (pid, name) in bundled_processes() {
        let Ok(application) = AxApplication::for_pid(pid) else {
            continue;
        };
        if application.windows().is_empty() {
            continue;
        }
        apps.push(AppInfo {
            name,
            // The bundle identifier lives in the app's Info.plist, which is
            // often a binary property list; reading it would mean parsing one or
            // shelling out. Names are unambiguous enough here, and `pid:` covers
            // the rest.
            bundle_id: None,
            pid,
        });
    }
    apps.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then(left.pid.cmp(&right.pid))
    });
    Ok(apps)
}

/// Processes that look like bundled applications, with the name a user knows.
fn bundled_processes() -> Vec<(u32, String)> {
    let mut system = System::new();
    // `without_tasks` is required: on some platforms the default puts every
    // thread in the table as a process, and here it would multiply the number of
    // accessibility probes by the thread count.
    system.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing()
            .with_exe(UpdateKind::Always)
            .without_tasks(),
    );
    system
        .processes()
        .values()
        .filter_map(|process| {
            let path = process.exe()?.to_string_lossy().to_string();
            let name = bundle_name(&path)?;
            Some((process.pid().as_u32(), name))
        })
        .collect()
}

/// The application name inside a bundle executable path.
///
/// `/Applications/Safari.app/Contents/MacOS/Safari` becomes `Safari`. Anything
/// that is not inside a bundle is not an application a user would name.
fn bundle_name(executable_path: &str) -> Option<String> {
    let (before, _) = executable_path.split_once(".app/Contents/MacOS/")?;
    let name = before.rsplit('/').next()?;
    (!name.is_empty()).then(|| name.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_bundled_executable_yields_the_application_name() {
        assert_eq!(
            bundle_name("/Applications/Safari.app/Contents/MacOS/Safari").as_deref(),
            Some("Safari")
        );
        assert_eq!(
            bundle_name("/Applications/Visual Studio Code.app/Contents/MacOS/Electron").as_deref(),
            Some("Visual Studio Code")
        );
        assert_eq!(
            bundle_name("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder").as_deref(),
            Some("Finder")
        );
    }

    /// A helper in a nested bundle is named after its own bundle rather than the
    /// outer application, which is how it appears in Activity Monitor and keeps
    /// two helpers of one app distinguishable.
    #[test]
    fn a_nested_helper_takes_its_own_bundle_name() {
        assert_eq!(
            bundle_name(
                "/Applications/Chrome.app/Contents/Frameworks/Chrome Helper.app/Contents/MacOS/Chrome Helper"
            )
            .as_deref(),
            Some("Chrome Helper")
        );
    }

    /// Daemons and command-line tools are not applications an agent would drive,
    /// and probing each one costs a round trip.
    #[test]
    fn processes_outside_a_bundle_are_skipped() {
        assert_eq!(bundle_name("/usr/sbin/cupsd"), None);
        assert_eq!(bundle_name("/bin/zsh"), None);
        assert_eq!(bundle_name(""), None);
        // A path with the marker but nothing before it names no bundle.
        assert_eq!(bundle_name(".app/Contents/MacOS/tool"), None);
    }
}
