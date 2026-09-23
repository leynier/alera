use std::path::PathBuf;

use clap::{Args, Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(
    name = "alera-xtask",
    about = "Alera developer tooling used by the makefile.",
    disable_help_subcommand = false,
    after_help = "\
Make-only targets:
  rust-test                 Format, lint, and test the Rust workspace.
  perf-linux                Capture Linux startup and frame timings.
  perf-macos-resources      Capture macOS CPU and RSS by process group."
)]
pub struct Xtask {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Initialize the two source submodules required to resolve and build Alera.
    #[command(name = "init-submodules")]
    InitSubmodules(InitSubmodulesArgs),
    /// Build the Rust alera CLI sidecar (cargo).
    #[command(name = "cli-build")]
    CliBuild(DebugArgs),
    /// Build the sidecar and print alera --help.
    #[command(name = "cli-help")]
    CliHelp(DebugArgs),
    /// Build an isolated dev-profile runtime host.
    #[command(name = "runtime-dev-build")]
    RuntimeDevBuild(DebugArgs),
    /// Run the Rust alera runtime-host in the foreground.
    #[command(name = "host-debug")]
    HostDebug(DebugArgs),
    /// Run the Flutter desktop app.
    #[command(name = "app-debug")]
    AppDebug(DebugArgs),
    /// Run the Flutter desktop app in profile mode.
    #[command(name = "app-profile")]
    AppProfile(DebugArgs),
    /// Run the app against the compiled CLI bundle.
    #[command(name = "app-debug-bundled-cli")]
    AppDebugBundledCli(DebugArgs),
    /// Run Alera Dev against the dev runtime bundle.
    #[command(name = "app-debug-runtime-dev")]
    AppDebugRuntimeDev(DebugArgs),
    /// List likely Alera UI and host processes.
    #[command(name = "debug-processes")]
    DebugProcesses(DebugArgs),
    /// Stop the current runtime host from host.json.
    #[command(name = "host-stop")]
    HostStop(DebugArgs),
}

#[derive(Debug, Args)]
pub struct InitSubmodulesArgs {
    /// Repository root. Defaults to the current directory.
    #[arg(long)]
    pub repo_root: Option<PathBuf>,
}

#[derive(Debug, Clone, Args)]
pub struct DebugArgs {
    #[arg(long, env = "CARGO", default_value = "cargo")]
    pub cargo: String,
    #[arg(long, env = "FLUTTER", default_value = "flutter")]
    pub flutter: String,
    #[arg(long, env = "APP_DEVICE")]
    pub device: Option<String>,
    #[arg(long = "alera-flavor", env = "ALERA_FLAVOR", default_value = "dev")]
    pub flavor: String,
    #[arg(long = "app-id", env = "ALERA_APP_ID")]
    pub app_id: Option<String>,
    #[arg(
        long = "bundle-dir",
        env = "ALERA_CLI_BUNDLE_DIR",
        default_value = ".dart_tool/alera"
    )]
    pub bundle_dir: String,
    #[arg(
        long = "debug-token",
        env = "ALERA_CLI_DEBUG_TOKEN",
        default_value = "dev-token"
    )]
    pub debug_token: String,
    #[arg(
        long = "host-empty-shutdown-seconds",
        env = "ALERA_HOST_EMPTY_SHUTDOWN_SECONDS",
        default_value = "30"
    )]
    pub host_empty_shutdown_seconds: String,
    #[arg(
        long = "host-detached-shutdown-seconds",
        env = "ALERA_HOST_DETACHED_SHUTDOWN_SECONDS",
        default_value = "3600"
    )]
    pub host_detached_shutdown_seconds: String,
    #[arg(
        long = "host-scrollback-bytes",
        env = "ALERA_HOST_SCROLLBACK_BYTES",
        default_value = "10000000"
    )]
    pub host_scrollback_bytes: String,
    #[arg(long = "app-support-dir", env = "ALERA_APP_SUPPORT_DIR")]
    pub app_support_dir: Option<String>,
    /// Repository root. Defaults to the current directory.
    #[arg(long, hide = true)]
    pub repo_root: Option<PathBuf>,
}

impl DebugArgs {
    pub fn resolved_device(&self) -> anyhow::Result<String> {
        if let Some(device) = &self.device {
            return Ok(device.clone());
        }
        default_flutter_device()
    }

    pub fn resolved_app_id(&self) -> String {
        if let Some(app_id) = &self.app_id {
            return app_id.clone();
        }
        crate::flavor::bundle_id(&self.flavor).to_string()
    }
}

pub fn default_flutter_device() -> anyhow::Result<String> {
    if cfg!(target_os = "macos") {
        return Ok("macos".to_string());
    }
    if cfg!(target_os = "windows") {
        return Ok("windows".to_string());
    }
    if cfg!(target_os = "linux") {
        return Ok("linux".to_string());
    }
    anyhow::bail!(
        "No default Flutter desktop device is available for this host platform. \
         Pass --device explicitly."
    );
}
