use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};

use crate::cli::DebugArgs;
use crate::debug_processes::{is_alera_process, is_cli_bundle_terminal_host, list_processes};
use crate::flavor::{self, DEV_FLAVOR};
use crate::spawn::{format_command_line, run_inherit};

pub struct DebugContext {
    args: DebugArgs,
    repo_root: PathBuf,
    device: String,
    app_id: String,
}

impl DebugContext {
    pub fn new(args: DebugArgs) -> Result<Self> {
        let device = args.resolved_device()?;
        let app_id = args.resolved_app_id();
        let repo_root = match &args.repo_root {
            Some(path) if path.is_absolute() => path.clone(),
            Some(path) => std::env::current_dir()?.join(path),
            None => std::env::current_dir()?,
        };
        Ok(Self {
            args,
            repo_root,
            device,
            app_id,
        })
    }

    pub fn cli_build(&self) -> Result<i32> {
        self.build_cli(None, true)
    }

    pub fn runtime_dev_build(&self) -> Result<i32> {
        self.build_cli(None, false)
    }

    pub fn cli_help(&self) -> Result<i32> {
        let build_exit = self.build_cli(None, true)?;
        if build_exit != 0 {
            return Ok(build_exit);
        }
        self.run_logged(&self.cli_executable_path(), &["--help"], None, true)
    }

    pub fn host_debug_foreground(&self) -> Result<i32> {
        let build_exit = self.build_cli(None, true)?;
        if build_exit != 0 {
            return Ok(build_exit);
        }
        let paths = self.runtime_paths();
        fs::create_dir_all(&paths.runtime_dir)?;
        if paths.control_file.exists() {
            fs::remove_file(&paths.control_file)?;
        }
        let executable = self.cli_executable_path();
        let args = [
            "runtime-host".to_string(),
            "--runtime-dir".to_string(),
            paths.runtime_dir.to_string_lossy().into_owned(),
            "--control-file".to_string(),
            paths.control_file.to_string_lossy().into_owned(),
            "--token".to_string(),
            self.args.debug_token.clone(),
            "--empty-shutdown-delay-seconds".to_string(),
            self.args.host_empty_shutdown_seconds.clone(),
            "--detached-session-shutdown-delay-seconds".to_string(),
            self.args.host_detached_shutdown_seconds.clone(),
            "--scrollback-bytes".to_string(),
            self.args.host_scrollback_bytes.clone(),
        ];
        self.run_logged(&executable, &args, None, true)
    }

    pub fn app_debug(&self) -> Result<i32> {
        self.prepare_flavor()?;
        self.run_flutter(&self.flutter_run_arguments(false), None)
    }

    pub fn app_profile(&self) -> Result<i32> {
        self.prepare_flavor()?;
        self.run_flutter(&self.flutter_run_arguments(true), None)
    }

    pub fn app_debug_bundled_cli(&self) -> Result<i32> {
        self.prepare_flavor()?;
        let output_dir = self.app_debug_bundled_cli_output_dir()?;
        let build_exit = self.build_cli(Some(&output_dir), true)?;
        if build_exit != 0 {
            return Ok(build_exit);
        }
        self.run_flutter(
            &self.flutter_run_arguments(false),
            Some(self.cli_bundle_path_for(&output_dir)),
        )
    }

    pub fn app_debug_runtime_dev(&self) -> Result<i32> {
        if self.args.flavor != DEV_FLAVOR {
            eprintln!("The dev runtime can only be launched with the dev flavor.");
            return Ok(64);
        }
        self.prepare_flavor()?;
        let output_dir = self.app_debug_bundled_cli_output_dir()?;
        let build_exit = self.build_cli(Some(&output_dir), false)?;
        if build_exit != 0 {
            return Ok(build_exit);
        }
        self.run_flutter(
            &self.flutter_run_arguments(false),
            Some(self.cli_bundle_path_for(&output_dir)),
        )
    }

    pub fn debug_processes(&self) -> Result<i32> {
        let processes = list_processes()?;
        let matches: Vec<_> = processes
            .into_iter()
            .filter(|process| is_alera_process(&process.command_line))
            .collect();
        if matches.is_empty() {
            println!("No Alera app or runtime-host processes found.");
        } else {
            for process in &matches {
                println!("{} {}", process.pid, process.command_line);
            }
        }
        let control_file = self.runtime_paths().control_file;
        if control_file.exists() {
            println!("control file: {}", control_file.display());
            print!("{}", fs::read_to_string(&control_file)?);
        }
        Ok(0)
    }

    pub fn host_stop(&self) -> Result<i32> {
        let control_file = self.runtime_paths().control_file;
        if !control_file.exists() {
            println!(
                "No runtime host control file found at {}.",
                control_file.display()
            );
            return Ok(0);
        }
        let decoded: serde_json::Value = serde_json::from_str(&fs::read_to_string(&control_file)?)
            .context("parse runtime host control file")?;
        let pid = match decoded.get("pid").and_then(serde_json::Value::as_i64) {
            Some(pid) => pid,
            None => {
                eprintln!("Runtime host control file does not contain a pid.");
                return Ok(1);
            }
        };
        let stopped = terminate_pid(pid);
        fs::remove_file(&control_file)?;
        if stopped {
            println!(
                "Stopped runtime host pid {pid} and removed {}.",
                control_file.display()
            );
        } else {
            println!(
                "Runtime host pid {pid} was not running; removed stale {}.",
                control_file.display()
            );
        }
        Ok(0)
    }

    fn build_cli(&self, output_dir: Option<&str>, release: bool) -> Result<i32> {
        let mut args = vec![
            "build".to_string(),
            "--locked".to_string(),
            "-p".to_string(),
            "alera-cli".to_string(),
        ];
        if release {
            args.push("--release".to_string());
        }
        let cargo_exit = self.run_logged(&self.args.cargo, &args, Some(&self.rust_dir()), true)?;
        if cargo_exit != 0 {
            return Ok(cargo_exit);
        }
        self.stage_cli_binary(
            output_dir.unwrap_or(&self.args.bundle_dir),
            if release { "release" } else { "debug" },
        )
    }

    fn stage_cli_binary(&self, output_dir: &str, profile: &str) -> Result<i32> {
        let source = self
            .rust_dir()
            .join("target")
            .join(profile)
            .join(cli_executable_name());
        if !source.exists() {
            eprintln!("Built Alera CLI binary not found at {}.", source.display());
            return Ok(1);
        }
        let destination_dir = PathBuf::from(self.absolute_build_output_path(output_dir));
        fs::create_dir_all(&destination_dir)?;
        let destination = destination_dir.join(cli_executable_name());
        let staged = destination.with_extension(format!(
            "stage-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_micros())
                .unwrap_or(0)
        ));
        let stage_result = (|| -> Result<()> {
            fs::copy(&source, &staged)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let mut permissions = fs::metadata(&staged)?.permissions();
                permissions.set_mode(0o755);
                fs::set_permissions(&staged, permissions)?;
            }
            #[cfg(windows)]
            if destination.exists() {
                fs::remove_file(&destination)?;
            }
            fs::rename(&staged, &destination)?;
            Ok(())
        })();
        if staged.exists() {
            let _ = fs::remove_file(&staged);
        }
        stage_result?;
        Ok(0)
    }

    fn app_debug_bundled_cli_output_dir(&self) -> Result<String> {
        if !cfg!(windows) {
            return Ok(self.args.bundle_dir.clone());
        }
        let hosts = list_processes()?
            .into_iter()
            .filter(|process| {
                is_cli_bundle_terminal_host(
                    &process.command_line,
                    &self.absolute_build_output_path(&self.args.bundle_dir),
                )
            })
            .count();
        if hosts == 0 {
            return Ok(self.args.bundle_dir.clone());
        }
        let output_dir = self.windows_side_by_side_cli_build_output_path();
        println!(
            "Bundled runtime host is still running from {}; building a fresh Windows bundle at {output_dir}.",
            self.args.bundle_dir
        );
        Ok(output_dir)
    }

    fn flutter_run_arguments(&self, profile: bool) -> Vec<String> {
        let mut args = vec!["run".to_string(), "-d".to_string(), self.device.clone()];
        if profile {
            args.push("--profile".to_string());
        }
        args.push(format!("--dart-define=ALERA_FLAVOR={}", self.args.flavor));
        if profile {
            args.push("--dart-define=ALERA_PERF_TRACE=true".to_string());
        }
        args
    }

    fn run_flutter(&self, args: &[String], cli_bundle_dir: Option<String>) -> Result<i32> {
        let mut environment = std::collections::HashMap::new();
        environment.insert("ALERA_FLAVOR".to_string(), self.args.flavor.clone());
        if let Some(cli_bundle_dir) = cli_bundle_dir {
            environment.insert("ALERA_CLI_BUNDLE_DIR".to_string(), cli_bundle_dir);
        }
        self.run_logged_with_env(&self.args.flutter, args, None, Some(&environment), true)
    }

    fn prepare_flavor(&self) -> Result<()> {
        if !cfg!(target_os = "macos") {
            return Ok(());
        }
        let config_file = self.repo_root.join("macos/Runner/Configs/Flavor.xcconfig");
        if let Some(parent) = config_file.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(config_file, flavor::flavor_xcconfig(&self.args.flavor))?;
        Ok(())
    }

    fn run_logged(
        &self,
        program: &str,
        args: &[impl AsRef<str>],
        cwd: Option<&Path>,
        windows_shell: bool,
    ) -> Result<i32> {
        self.run_logged_with_env(program, args, cwd, None, windows_shell)
    }

    fn run_logged_with_env(
        &self,
        program: &str,
        args: &[impl AsRef<str>],
        cwd: Option<&Path>,
        environment: Option<&std::collections::HashMap<String, String>>,
        windows_shell: bool,
    ) -> Result<i32> {
        let rendered: Vec<String> = args.iter().map(|arg| arg.as_ref().to_string()).collect();
        println!("{}", format_command_line(program, &rendered));
        let cwd = cwd.unwrap_or(&self.repo_root);
        Ok(run_inherit(
            program,
            &rendered,
            cwd,
            environment,
            windows_shell,
        )?)
    }

    fn runtime_paths(&self) -> RuntimePaths {
        let support_dir = self
            .args
            .app_support_dir
            .clone()
            .unwrap_or_else(|| default_app_support_dir(&self.app_id));
        let runtime_dir = PathBuf::from(support_dir).join("terminal_host");
        let control_file = runtime_dir.join("host.json");
        RuntimePaths {
            runtime_dir,
            control_file,
        }
    }

    fn rust_dir(&self) -> PathBuf {
        self.repo_root.join("rust")
    }

    fn cli_executable_path(&self) -> String {
        PathBuf::from(self.cli_bundle_path_for(&self.args.bundle_dir))
            .join(cli_executable_name())
            .to_string_lossy()
            .into_owned()
    }

    fn cli_bundle_path_for(&self, build_output_dir: &str) -> String {
        self.absolute_build_output_path(build_output_dir)
    }

    fn absolute_build_output_path(&self, build_output_dir: &str) -> String {
        let bundle_dir = PathBuf::from(build_output_dir);
        if bundle_dir.is_absolute() {
            bundle_dir.to_string_lossy().into_owned()
        } else {
            self.repo_root
                .join(bundle_dir)
                .to_string_lossy()
                .into_owned()
        }
    }

    fn windows_side_by_side_cli_build_output_path(&self) -> String {
        let absolute_output = PathBuf::from(self.absolute_build_output_path(&self.args.bundle_dir));
        let output_name = absolute_output
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| "alera".to_string());
        let millis = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_millis())
            .unwrap_or(0);
        absolute_output
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join(format!("{output_name}-runs"))
            .join(format!("app-debug-{millis}"))
            .to_string_lossy()
            .into_owned()
    }
}

struct RuntimePaths {
    runtime_dir: PathBuf,
    control_file: PathBuf,
}

fn cli_executable_name() -> &'static str {
    if cfg!(windows) {
        "alera.exe"
    } else {
        "alera"
    }
}

fn default_app_support_dir(app_id: &str) -> String {
    if cfg!(target_os = "macos") {
        return home_directory()
            .join("Library/Application Support")
            .join(app_id)
            .to_string_lossy()
            .into_owned();
    }
    if cfg!(windows) {
        if let Ok(app_data) = std::env::var("APPDATA") {
            if !app_data.is_empty() {
                return PathBuf::from(app_data)
                    .join(app_id)
                    .to_string_lossy()
                    .into_owned();
            }
        }
    }
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME") {
        if !xdg.is_empty() {
            return PathBuf::from(xdg)
                .join(app_id)
                .to_string_lossy()
                .into_owned();
        }
    }
    home_directory()
        .join(".local/share")
        .join(app_id)
        .to_string_lossy()
        .into_owned()
}

fn home_directory() -> PathBuf {
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home);
    }
    if let Ok(profile) = std::env::var("USERPROFILE") {
        return PathBuf::from(profile);
    }
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn terminate_pid(pid: i64) -> bool {
    #[cfg(unix)]
    {
        unsafe { libc::kill(pid as i32, libc::SIGTERM) == 0 }
    }
    #[cfg(windows)]
    {
        crate::spawn::run_captured(
            "taskkill.exe",
            &["/PID", &pid.to_string(), "/F"],
            None,
            false,
        )
        .map(|output| output.status == 0)
        .unwrap_or(false)
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = pid;
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::DebugArgs;
    use crate::flavor::DEV_FLAVOR;

    #[test]
    fn runtime_dev_rejects_non_dev_flavor() {
        let args = DebugArgs {
            cargo: "cargo".into(),
            flutter: "flutter".into(),
            device: Some("linux".into()),
            flavor: "release".into(),
            app_id: None,
            bundle_dir: ".dart_tool/alera".into(),
            debug_token: "dev-token".into(),
            host_empty_shutdown_seconds: "30".into(),
            host_detached_shutdown_seconds: "3600".into(),
            host_scrollback_bytes: "10000000".into(),
            app_support_dir: None,
            repo_root: None,
        };
        let context = DebugContext::new(args).expect("context");
        let code = context.app_debug_runtime_dev().expect("run");
        assert_eq!(code, 64);
        assert_ne!(DEV_FLAVOR, "release");
    }
}
