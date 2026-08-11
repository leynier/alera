use serde_json::{json, Value};

#[cfg(windows)]
use serde_json::Map;

#[cfg(windows)]
fn environment() -> Value {
    let mut environment = Map::new();
    environment.insert("TERM".to_string(), json!("xterm"));
    for name in ["PATH", "SystemRoot", "WINDIR", "TEMP", "TMP"] {
        if let Ok(value) = std::env::var(name) {
            environment.insert(name.to_string(), json!(value));
        }
    }
    Value::Object(environment)
}

#[cfg(not(windows))]
fn environment() -> Value {
    json!({"PATH": "/usr/bin:/bin", "TERM": "xterm"})
}

#[cfg(windows)]
fn shell() -> String {
    std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string())
}

#[cfg(windows)]
fn powershell() -> String {
    std::env::var_os("SystemRoot")
        .map(std::path::PathBuf::from)
        .map(|root| {
            root.join("System32")
                .join("WindowsPowerShell")
                .join("v1.0")
                .join("powershell.exe")
        })
        .filter(|path| path.is_file())
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_else(|| "powershell.exe".to_string())
}

pub fn working_directory() -> String {
    #[cfg(windows)]
    {
        std::env::temp_dir().to_string_lossy().into_owned()
    }
    #[cfg(not(windows))]
    {
        "/tmp".to_string()
    }
}

pub fn long_running_launch() -> Value {
    #[cfg(windows)]
    {
        json!({
            "shell": powershell(),
            "arguments": ["-NoLogo", "-NoProfile", "-Command", "Start-Sleep -Seconds 30"],
            "environment": environment()
        })
    }
    #[cfg(not(windows))]
    {
        json!({
            "shell": "/bin/sh",
            "arguments": ["-c", "sleep 30"],
            "environment": environment()
        })
    }
}

pub fn marker_exit_launch(marker: &str, exit_code: i32) -> Value {
    #[cfg(windows)]
    {
        json!({
            "shell": shell(),
            "arguments": ["/d", "/s", "/c", format!("echo {marker}& exit /b {exit_code}")],
            "environment": environment()
        })
    }
    #[cfg(not(windows))]
    {
        json!({
            "shell": "/bin/sh",
            "arguments": ["-c", format!("printf {marker}; exit {exit_code}")],
            "environment": environment()
        })
    }
}

pub fn interactive_launch() -> Value {
    #[cfg(windows)]
    {
        json!({
            "shell": shell(),
            "arguments": [],
            "environment": environment()
        })
    }
    #[cfg(not(windows))]
    {
        json!({
            "shell": "/bin/sh",
            "arguments": [],
            "environment": environment()
        })
    }
}

pub fn input_echo_launch() -> Value {
    #[cfg(windows)]
    {
        json!({
            "shell": shell(),
            "arguments": [
                "/d",
                "/v:on",
                "/s",
                "/c",
                "echo READY& set /p line=& echo GOT:!line!& exit /b 0"
            ],
            "environment": environment()
        })
    }
    #[cfg(not(windows))]
    {
        json!({
            "shell": "/bin/sh",
            "arguments": ["-c", "printf READY; IFS= read -r line; printf 'GOT:%s' \"$line\"; exit 0"],
            "environment": environment()
        })
    }
}

pub fn delayed_markers_launch() -> Value {
    #[cfg(windows)]
    {
        json!({
            "shell": shell(),
            "arguments": [
                "/d",
                "/s",
                "/c",
                "echo FIRST& ping -n 2 127.0.0.1 >NUL& echo SECOND& exit /b 3"
            ],
            "environment": environment()
        })
    }
    #[cfg(not(windows))]
    {
        json!({
            "shell": "/bin/sh",
            "arguments": ["-c", "printf FIRST; sleep 0.2; printf SECOND; exit 3"],
            "environment": environment()
        })
    }
}
