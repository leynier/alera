use anyhow::Result;
use serde_json::Value;

use crate::spawn::run_captured;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessInfo {
    pub pid: i64,
    pub command_line: String,
}

pub fn list_processes() -> Result<Vec<ProcessInfo>> {
    if cfg!(windows) {
        list_windows_processes()
    } else {
        list_unix_processes()
    }
}

fn list_unix_processes() -> Result<Vec<ProcessInfo>> {
    let output = run_captured("ps", &["-ax", "-o", "pid=,command="], None, false)?;
    if output.status != 0 {
        eprint!("{}", output.stderr);
        return Ok(Vec::new());
    }
    Ok(parse_ps_table(&output.stdout))
}

fn list_windows_processes() -> Result<Vec<ProcessInfo>> {
    let executable = first_available_executable(&["pwsh", "powershell"])?;
    let Some(executable) = executable else {
        eprintln!("PowerShell 7 is required on Windows for debug-processes.");
        return Ok(Vec::new());
    };
    let output = run_captured(
        &executable,
        &[
            "-NoLogo",
            "-NoProfile",
            "-Command",
            r"Get-CimInstance Win32_Process | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress",
        ],
        None,
        false,
    )?;
    if output.status != 0 {
        eprint!("{}", output.stderr);
        return Ok(Vec::new());
    }
    Ok(parse_windows_process_json(output.stdout.trim()))
}

fn first_available_executable(executables: &[&str]) -> Result<Option<String>> {
    let finder = if cfg!(windows) { "where" } else { "which" };
    for executable in executables {
        let output = run_captured(finder, &[*executable], None, false)?;
        if output.status == 0 {
            return Ok(Some((*executable).to_string()));
        }
    }
    Ok(None)
}

pub fn parse_ps_table(stdout: &str) -> Vec<ProcessInfo> {
    stdout
        .lines()
        .filter_map(parse_ps_line)
        .filter(|process| process.pid >= 0)
        .collect()
}

pub fn parse_ps_line(line: &str) -> Option<ProcessInfo> {
    let trimmed = line.trim_start();
    let first_space = trimmed.find(' ')?;
    let pid = trimmed[..first_space].parse().unwrap_or(-1);
    Some(ProcessInfo {
        pid,
        command_line: trimmed[first_space + 1..].trim_start().to_string(),
    })
}

pub fn parse_windows_process_json(raw: &str) -> Vec<ProcessInfo> {
    if raw.is_empty() {
        return Vec::new();
    }
    let decoded: Value = match serde_json::from_str(raw) {
        Ok(value) => value,
        Err(_) => return Vec::new(),
    };
    let entries = match decoded {
        Value::Array(entries) => entries,
        other => vec![other],
    };
    entries
        .into_iter()
        .filter_map(|entry| {
            let pid = entry.get("ProcessId")?.as_i64()?;
            let command_line = entry
                .get("CommandLine")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            Some(ProcessInfo { pid, command_line })
        })
        .collect()
}

pub fn is_alera_process(command_line: &str) -> bool {
    let normalized = normalize_separators(command_line);
    command_line.contains("alera runtime-host")
        || command_line.contains("alera terminal-host")
        || normalized.contains("/alera/alera")
        || normalized.contains("/.dart_tool/alera/alera")
        || normalized.contains("/Alera.app/Contents/MacOS/Alera")
        || normalized.contains("/Alera Dev.app/Contents/MacOS/Alera Dev")
        || normalized.contains("/alera-dev")
        || normalized.ends_with("alera-dev")
        || normalized.ends_with("alera-dev.exe")
}

pub fn is_cli_bundle_terminal_host(command_line: &str, bundle_path: &str) -> bool {
    let command_line = normalize_process_text(command_line);
    (command_line.contains("runtime-host") || command_line.contains("terminal-host"))
        && contains_normalized_path_root(&command_line, &normalize_process_text(bundle_path))
}

pub fn normalize_separators(value: &str) -> String {
    value.replace('\\', "/")
}

pub fn normalize_process_text(value: &str) -> String {
    normalize_separators(value).to_lowercase()
}

pub fn contains_normalized_path_root(value: &str, path_root: &str) -> bool {
    value.contains(&format!("{path_root}/"))
        || value.contains(&format!("{path_root} "))
        || value.contains(&format!("{path_root}\""))
        || value.contains(&format!("{path_root}'"))
        || value.ends_with(path_root)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_ps_line_splits_pid_and_command() {
        let process =
            parse_ps_line("  1234 /opt/alera/resources/alera/alera runtime-host").unwrap();
        assert_eq!(process.pid, 1234);
        assert_eq!(
            process.command_line,
            "/opt/alera/resources/alera/alera runtime-host"
        );
        assert!(is_alera_process(&process.command_line));
    }

    #[test]
    fn bundled_host_matches_bundle_root() {
        assert!(is_cli_bundle_terminal_host(
            "/repo/.dart_tool/alera/alera runtime-host --runtime-dir /tmp",
            "/repo/.dart_tool/alera"
        ));
        assert!(!is_cli_bundle_terminal_host(
            "/repo/.dart_tool/alera-dev/alera runtime-host",
            "/repo/.dart_tool/alera"
        ));
    }

    #[test]
    fn windows_json_accepts_a_single_object() {
        let processes =
            parse_windows_process_json(r#"{"ProcessId":44,"CommandLine":"C:\\alera-dev.exe"}"#);
        assert_eq!(processes.len(), 1);
        assert_eq!(processes[0].pid, 44);
        assert!(is_alera_process(&processes[0].command_line));
    }
}
