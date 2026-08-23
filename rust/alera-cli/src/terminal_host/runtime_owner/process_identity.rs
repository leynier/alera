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
}

#[cfg(target_os = "windows")]
mod platform {
    use windows::Win32::Foundation::{
        CloseHandle, GetLastError, ERROR_INVALID_PARAMETER, FILETIME,
    };
    use windows::Win32::System::Threading::{
        GetExitCodeProcess, GetProcessTimes, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
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
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
mod platform {
    use super::ProcessLookup;

    pub(super) fn lookup(pid: u32) -> ProcessLookup {
        ProcessLookup::Unknown(format!(
            "process identity is unsupported on {} for process {pid}",
            std::env::consts::OS
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
