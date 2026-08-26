use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct ProcessIdentity {
    pub pid: u32,
    pub start_marker: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum ProcessLookup {
    Live(ProcessIdentity),
    Exited,
    Unknown(String),
}

impl fmt::Display for ProcessLookup {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ProcessLookup::Live(identity) => write!(
                formatter,
                "process {} is live with start marker {}",
                identity.pid, identity.start_marker
            ),
            ProcessLookup::Exited => formatter.write_str("process has exited"),
            ProcessLookup::Unknown(reason) => formatter.write_str(reason),
        }
    }
}

pub(super) trait ProcessIdentityProbe {
    fn lookup(&self, pid: u32) -> ProcessLookup;
}

pub(super) struct SystemProcessIdentityProbe;

impl ProcessIdentityProbe for SystemProcessIdentityProbe {
    fn lookup(&self, pid: u32) -> ProcessLookup {
        platform::lookup(pid)
    }
}

pub(super) fn current_process_identity() -> Result<ProcessIdentity, String> {
    let pid = std::process::id();
    match SystemProcessIdentityProbe.lookup(pid) {
        ProcessLookup::Live(identity) => Ok(identity),
        ProcessLookup::Exited => Err(format!("current process {pid} was not found")),
        ProcessLookup::Unknown(reason) => Err(format!(
            "current process {pid} identity could not be read: {reason}"
        )),
    }
}

pub(super) fn terminate_process(identity: ProcessIdentity) -> Result<(), String> {
    platform::terminate(identity)
}

pub(super) const PLATFORM: &str = std::env::consts::OS;

#[cfg(target_os = "linux")]
mod platform {
    use super::{ProcessIdentity, ProcessLookup};

    pub(super) fn lookup(pid: u32) -> ProcessLookup {
        let path = format!("/proc/{pid}/stat");
        let stat = match std::fs::read_to_string(&path) {
            Ok(stat) => stat,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return ProcessLookup::Exited;
            }
            Err(error) => {
                return ProcessLookup::Unknown(format!("failed reading {path}: {error}"));
            }
        };
        match parse_process_record(&stat) {
            Some(("Z" | "X", _)) => ProcessLookup::Exited,
            Some((_, start_marker)) => ProcessLookup::Live(ProcessIdentity { pid, start_marker }),
            None => ProcessLookup::Unknown(format!("{path} had an invalid process record")),
        }
    }

    pub(super) fn terminate(identity: ProcessIdentity) -> Result<(), String> {
        terminate_unix(identity)
    }

    fn terminate_unix(identity: ProcessIdentity) -> Result<(), String> {
        match lookup(identity.pid) {
            ProcessLookup::Live(actual) if actual == identity => {}
            ProcessLookup::Live(actual) => {
                return Err(format!(
                    "runtime owner process {} was replaced before termination; expected start marker {}, found {}",
                    identity.pid, identity.start_marker, actual.start_marker
                ));
            }
            ProcessLookup::Exited => return Ok(()),
            ProcessLookup::Unknown(reason) => return Err(reason),
        }
        let result = unsafe { libc::kill(identity.pid as libc::pid_t, libc::SIGTERM) };
        if result == 0 {
            return Ok(());
        }
        let error = std::io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ESRCH) {
            Ok(())
        } else {
            Err(format!(
                "failed terminating runtime owner process {}: {error}",
                identity.pid
            ))
        }
    }

    fn parse_process_record(stat: &str) -> Option<(&str, u64)> {
        // The command name is parenthesized and may itself contain spaces or
        // parentheses. Field 3 starts after the final `) `; starttime is field
        // 22, so it is item 19 in that suffix.
        let fields = stat.get(stat.rfind(") ")? + 2..)?;
        let mut fields = fields.split_whitespace();
        let state = fields.next()?;
        let start_marker = fields.nth(18)?.parse().ok()?;
        Some((state, start_marker))
    }

    #[cfg(test)]
    mod tests {
        use super::parse_process_record;

        #[test]
        fn parses_linux_start_ticks_after_a_complex_process_name() {
            let mut suffix = vec!["S"; 19];
            suffix.push("987654");
            assert_eq!(
                parse_process_record(&format!("42 (name with ) paren) {}", suffix.join(" "))),
                Some(("S", 987654))
            );
        }

        #[test]
        fn parses_linux_zombie_state() {
            let mut suffix = vec!["Z"; 19];
            suffix.push("987654");
            assert_eq!(
                parse_process_record(&format!("42 (zombie) {}", suffix.join(" "))),
                Some(("Z", 987654))
            );
        }
    }
}

#[cfg(target_os = "macos")]
mod platform {
    use std::mem;

    use super::{ProcessIdentity, ProcessLookup};

    const ZOMBIE_PROCESS_STATUS: u32 = 5;

    pub(super) fn lookup(pid: u32) -> ProcessLookup {
        let mut info = unsafe { mem::zeroed::<libc::proc_bsdinfo>() };
        let size = mem::size_of::<libc::proc_bsdinfo>() as libc::c_int;
        let read = unsafe {
            libc::proc_pidinfo(
                pid as libc::c_int,
                libc::PROC_PIDTBSDINFO,
                0,
                &mut info as *mut _ as *mut libc::c_void,
                size,
            )
        };
        if read == size {
            if info.pbi_status == ZOMBIE_PROCESS_STATUS {
                return ProcessLookup::Exited;
            }
            let Some(start_marker) = info
                .pbi_start_tvsec
                .checked_mul(1_000_000)
                .and_then(|seconds| seconds.checked_add(info.pbi_start_tvusec))
            else {
                return ProcessLookup::Unknown(format!("process {pid} start timestamp overflowed"));
            };
            return ProcessLookup::Live(ProcessIdentity { pid, start_marker });
        }
        let errno = unsafe { *libc::__error() };
        if errno == libc::ESRCH {
            ProcessLookup::Exited
        } else {
            ProcessLookup::Unknown(format!(
                "proc_pidinfo failed for process {pid}: errno {errno}"
            ))
        }
    }

    pub(super) fn terminate(identity: ProcessIdentity) -> Result<(), String> {
        terminate_unix(identity)
    }

    fn terminate_unix(identity: ProcessIdentity) -> Result<(), String> {
        match lookup(identity.pid) {
            ProcessLookup::Live(actual) if actual == identity => {}
            ProcessLookup::Live(actual) => {
                return Err(format!(
                    "runtime owner process {} was replaced before termination; expected start marker {}, found {}",
                    identity.pid, identity.start_marker, actual.start_marker
                ));
            }
            ProcessLookup::Exited => return Ok(()),
            ProcessLookup::Unknown(reason) => return Err(reason),
        }
        let result = unsafe { libc::kill(identity.pid as libc::pid_t, libc::SIGTERM) };
        if result == 0 {
            return Ok(());
        }
        let error = std::io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ESRCH) {
            Ok(())
        } else {
            Err(format!(
                "failed terminating runtime owner process {}: {error}",
                identity.pid
            ))
        }
    }
}

#[cfg(target_os = "windows")]
mod platform {
    use windows::Win32::Foundation::{
        CloseHandle, GetLastError, ERROR_INVALID_PARAMETER, FILETIME,
    };
    use windows::Win32::System::Threading::{
        GetExitCodeProcess, GetProcessTimes, OpenProcess, TerminateProcess,
        PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_TERMINATE,
    };

    use super::{ProcessIdentity, ProcessLookup};

    pub(super) fn lookup(pid: u32) -> ProcessLookup {
        let handle = match unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) } {
            Ok(handle) => handle,
            Err(error) => {
                let code = unsafe { GetLastError() };
                return if code == ERROR_INVALID_PARAMETER {
                    ProcessLookup::Exited
                } else {
                    ProcessLookup::Unknown(format!("OpenProcess failed for process {pid}: {error}"))
                };
            }
        };
        let mut created = FILETIME::default();
        let mut exited = FILETIME::default();
        let mut kernel = FILETIME::default();
        let mut user = FILETIME::default();
        let mut exit_code = 0;
        let exit_result = unsafe { GetExitCodeProcess(handle, &mut exit_code) };
        let time_result =
            unsafe { GetProcessTimes(handle, &mut created, &mut exited, &mut kernel, &mut user) };
        let _ = unsafe { CloseHandle(handle) };
        if let Err(error) = exit_result {
            return ProcessLookup::Unknown(format!(
                "GetExitCodeProcess failed for process {pid}: {error}"
            ));
        }
        if exit_code != windows::Win32::Foundation::STILL_ACTIVE.0 as u32 {
            return ProcessLookup::Exited;
        }
        match time_result {
            Ok(()) => ProcessLookup::Live(ProcessIdentity {
                pid,
                start_marker: (u64::from(created.dwHighDateTime) << 32)
                    | u64::from(created.dwLowDateTime),
            }),
            Err(error) => {
                ProcessLookup::Unknown(format!("GetProcessTimes failed for process {pid}: {error}"))
            }
        }
    }

    pub(super) fn terminate(identity: ProcessIdentity) -> Result<(), String> {
        let handle = unsafe {
            OpenProcess(
                PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE,
                false,
                identity.pid,
            )
        }
        .map_err(|error| {
            format!(
                "OpenProcess failed for runtime owner process {}: {error}",
                identity.pid
            )
        })?;
        let mut created = FILETIME::default();
        let mut exited = FILETIME::default();
        let mut kernel = FILETIME::default();
        let mut user = FILETIME::default();
        let mut exit_code = 0;
        let exit_result = unsafe { GetExitCodeProcess(handle, &mut exit_code) };
        let time_result =
            unsafe { GetProcessTimes(handle, &mut created, &mut exited, &mut kernel, &mut user) };
        if let Err(error) = exit_result {
            let _ = unsafe { CloseHandle(handle) };
            return Err(format!(
                "GetExitCodeProcess failed for runtime owner process {}: {error}",
                identity.pid
            ));
        }
        if exit_code != windows::Win32::Foundation::STILL_ACTIVE.0 as u32 {
            let _ = unsafe { CloseHandle(handle) };
            return Ok(());
        }
        if let Err(error) = time_result {
            let _ = unsafe { CloseHandle(handle) };
            return Err(format!(
                "GetProcessTimes failed for runtime owner process {}: {error}",
                identity.pid
            ));
        }
        let actual_start_marker =
            (u64::from(created.dwHighDateTime) << 32) | u64::from(created.dwLowDateTime);
        if actual_start_marker != identity.start_marker {
            let _ = unsafe { CloseHandle(handle) };
            return Err(format!(
                "runtime owner process {} was replaced before termination; expected start marker {}, found {}",
                identity.pid, identity.start_marker, actual_start_marker
            ));
        }
        let result = unsafe { TerminateProcess(handle, 1) };
        let _ = unsafe { CloseHandle(handle) };
        result.map_err(|error| {
            format!(
                "failed terminating runtime owner process {}: {error}",
                identity.pid
            )
        })
    }
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
mod platform {
    use super::{ProcessIdentity, ProcessLookup};

    pub(super) fn lookup(pid: u32) -> ProcessLookup {
        ProcessLookup::Unknown(format!(
            "process identity is unsupported on {} for process {pid}",
            std::env::consts::OS
        ))
    }

    pub(super) fn terminate(identity: ProcessIdentity) -> Result<(), String> {
        Err(format!(
            "process termination is unsupported on {} for process {}",
            std::env::consts::OS,
            identity.pid
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::{
        current_process_identity, ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe,
    };

    #[test]
    fn current_process_has_a_stable_nonzero_identity() {
        let first = current_process_identity().unwrap();
        let second = current_process_identity().unwrap();
        assert_eq!(first, second);
        assert_eq!(first.pid, std::process::id());
        assert_ne!(first.start_marker, 0);
        assert_eq!(
            SystemProcessIdentityProbe.lookup(first.pid),
            ProcessLookup::Live(first)
        );
    }
}
