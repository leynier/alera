use std::fs;
use std::path::{Path, PathBuf};

use alera_core::runtime::{RuntimeAutomationSettings, RuntimeStore};
use anyhow::{Context, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AutostartPlatform {
    Macos,
    Windows,
    Linux,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct AutostartPaths {
    pub file: PathBuf,
    pub content: String,
}

pub(crate) fn current_platform() -> AutostartPlatform {
    if cfg!(target_os = "macos") {
        AutostartPlatform::Macos
    } else if cfg!(target_os = "windows") {
        AutostartPlatform::Windows
    } else {
        AutostartPlatform::Linux
    }
}

pub(crate) async fn reconcile_runtime_autostart(runtime_store: &RuntimeStore, runtime_dir: &Path) {
    let Ok(settings) = runtime_store.automation_settings().await else {
        return;
    };
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| runtime_dir.to_path_buf());
    let app_data = std::env::var_os("APPDATA").map(PathBuf::from);
    let xdg_config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from);
    let Ok(executable) = std::env::current_exe() else {
        return;
    };
    let paths = build_autostart_paths(
        current_platform(),
        &home,
        app_data.as_deref(),
        xdg_config.as_deref(),
        &executable,
        runtime_dir,
    );
    if let Err(error) = reconcile_autostart(&settings, &paths) {
        tracing::warn!("automation autostart reconciliation failed: {error}");
    }
}

pub(crate) fn build_autostart_paths(
    platform: AutostartPlatform,
    home: &Path,
    app_data: Option<&Path>,
    xdg_config: Option<&Path>,
    executable: &Path,
    runtime_dir: &Path,
) -> AutostartPaths {
    let executable = executable.to_string_lossy();
    let runtime_dir = runtime_dir.to_string_lossy();
    match platform {
        AutostartPlatform::Macos => {
            let file = home
                .join("Library")
                .join("LaunchAgents")
                .join("dev.alera.automation-host.plist");
            let content = format!(
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict><key>Label</key><string>dev.alera.automation-host</string><key>ProgramArguments</key><array><string>{}</string><string>automation-host</string><string>--runtime-dir</string><string>{}</string></array><key>RunAtLoad</key><true/><key>KeepAlive</key><true/></dict></plist>\n",
                xml_escape(&executable),
                xml_escape(&runtime_dir),
            );
            AutostartPaths { file, content }
        }
        AutostartPlatform::Windows => {
            let base = app_data.unwrap_or(home);
            let file = base
                .join("Microsoft")
                .join("Windows")
                .join("Start Menu")
                .join("Programs")
                .join("Startup")
                .join("Alera Automation Host.cmd");
            let content = format!(
                "@echo off\r\nstart \"Alera Automation Host\" /b \"{}\" automation-host --runtime-dir \"{}\"\r\n",
                windows_quote(&executable),
                windows_quote(&runtime_dir),
            );
            AutostartPaths { file, content }
        }
        AutostartPlatform::Linux => {
            let default_config = home.join(".config");
            let base = xdg_config.unwrap_or(&default_config);
            let file = base.join("autostart").join("alera-automation-host.desktop");
            let content = format!(
                "[Desktop Entry]\nType=Application\nName=Alera Automation Host\nComment=Run Alera automations at login\nExec={} automation-host --runtime-dir {}\nTerminal=false\nX-GNOME-Autostart-enabled=true\n",
                desktop_escape(&executable),
                desktop_escape(&runtime_dir),
            );
            AutostartPaths { file, content }
        }
    }
}

pub(crate) fn reconcile_autostart(
    settings: &RuntimeAutomationSettings,
    paths: &AutostartPaths,
) -> Result<()> {
    if settings.autostart {
        if let Some(parent) = paths.file.parent() {
            fs::create_dir_all(parent).with_context(|| {
                format!("could not create autostart directory {}", parent.display())
            })?;
        }
        fs::write(&paths.file, &paths.content)
            .with_context(|| format!("could not write autostart file {}", paths.file.display()))?;
    } else if paths.file.exists() {
        fs::remove_file(&paths.file)
            .with_context(|| format!("could not remove autostart file {}", paths.file.display()))?;
    }
    Ok(())
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('\"', "&quot;")
        .replace('\'', "&apos;")
}

fn windows_quote(value: &str) -> String {
    // This value is inserted into a quoted argument in a .cmd file. Percent
    // expansion still happens inside quotes, so double it before the file is
    // interpreted by cmd.exe. The other command metacharacters stay inside
    // the surrounding quotes and are therefore data, not syntax.
    value.replace('%', "%%").replace('"', "\"\"")
}

fn desktop_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace(' ', "\\ ")
        .replace('\t', "\\t")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disabled_autostart_is_safe_and_platform_specific() {
        let root = tempfile::tempdir().unwrap();
        for platform in [
            AutostartPlatform::Macos,
            AutostartPlatform::Windows,
            AutostartPlatform::Linux,
        ] {
            let paths = build_autostart_paths(
                platform,
                root.path(),
                Some(root.path()),
                Some(root.path()),
                Path::new("/opt/Alera/alera"),
                Path::new("/private/runtime"),
            );
            reconcile_autostart(&RuntimeAutomationSettings::default(), &paths).unwrap();
            assert!(!paths.file.exists());
        }
    }

    #[test]
    fn enabled_autostart_writes_login_entry_without_shell_expansion() {
        let root = tempfile::tempdir().unwrap();
        let paths = build_autostart_paths(
            AutostartPlatform::Linux,
            root.path(),
            None,
            Some(root.path()),
            Path::new("/opt/Alera Desktop/alera"),
            Path::new("/private/runtime with spaces"),
        );
        let settings = RuntimeAutomationSettings {
            autostart: true,
            ..RuntimeAutomationSettings::default()
        };
        reconcile_autostart(&settings, &paths).unwrap();
        let content = fs::read_to_string(paths.file).unwrap();
        assert!(content.contains("Alera\\ Desktop/alera"));
        assert!(content.contains("runtime\\ with\\ spaces"));
        assert!(!content.contains("$(`"));
    }

    #[test]
    fn enabled_macos_autostart_uses_launch_agent_and_escaped_arguments() {
        let root = tempfile::tempdir().unwrap();
        let paths = build_autostart_paths(
            AutostartPlatform::Macos,
            root.path(),
            None,
            None,
            Path::new("/Applications/Alera Desktop/alera"),
            Path::new("/private/runtime with spaces"),
        );
        reconcile_autostart(
            &RuntimeAutomationSettings {
                autostart: true,
                ..RuntimeAutomationSettings::default()
            },
            &paths,
        )
        .unwrap();
        let content = fs::read_to_string(paths.file).unwrap();
        assert!(content.contains("<key>RunAtLoad</key><true/>"));
        assert!(content.contains("Alera Desktop/alera"));
        assert!(content.contains("runtime with spaces"));
    }

    #[test]
    fn enabled_windows_autostart_uses_startup_command_without_shell_expansion() {
        let root = tempfile::tempdir().unwrap();
        let paths = build_autostart_paths(
            AutostartPlatform::Windows,
            root.path(),
            Some(root.path()),
            None,
            Path::new(r"C:\Program Files\Alera\alera.exe"),
            Path::new(r"C:\Users\Alera User\runtime"),
        );
        reconcile_autostart(
            &RuntimeAutomationSettings {
                autostart: true,
                ..RuntimeAutomationSettings::default()
            },
            &paths,
        )
        .unwrap();
        let content = fs::read_to_string(paths.file).unwrap();
        assert!(content.contains("start \"Alera Automation Host\" /b"));
        assert!(content.contains("automation-host"));
        assert!(content.contains(r#"C:\Program Files\Alera\alera.exe"#));
    }

    #[test]
    fn windows_autostart_escapes_percent_expansion_in_paths() {
        let paths = build_autostart_paths(
            AutostartPlatform::Windows,
            Path::new(r"C:\Users\Alera"),
            Some(Path::new(r"C:\Users\Alera")),
            None,
            Path::new(r"C:\Alera %LOCALAPPDATA%\alera.exe"),
            Path::new(r"C:\runtime\100%"),
        );
        assert!(paths
            .content
            .contains(r"C:\Alera %%LOCALAPPDATA%%\alera.exe"));
        assert!(paths.content.contains(r"C:\runtime\100%%"));
    }
}
