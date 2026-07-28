use clap::{Args, Subcommand, ValueEnum};

use super::{OutputArgs, RuntimeDirArgs};

/// Inspect and automate Android emulators and iOS simulators.
#[derive(Debug, Args)]
pub struct EmulatorCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: EmulatorAction,
}

#[derive(Debug, Subcommand)]
pub enum EmulatorAction {
    /// Report the installed emulator backends and their supported operations.
    Capabilities,
    /// List virtual devices available to the installed backends.
    Devices(EmulatorDevicesArgs),
    /// List active emulator attachments.
    List(EmulatorOptionalTargetArgs),
    /// Attach a virtual device to the workspace emulator tab.
    Attach(EmulatorAttachArgs),
    /// Capture a screenshot and accessibility observation.
    Snapshot(EmulatorSnapshotArgs),
    /// Tap one point from a current observation.
    Tap(EmulatorTapArgs),
    /// Drag or swipe between two points from a current observation.
    Gesture(EmulatorGestureArgs),
    /// Type text into the focused control.
    Type(EmulatorTypeArgs),
    /// Press a device button.
    Button(EmulatorButtonArgs),
    /// Change the device orientation.
    Rotate(EmulatorRotateArgs),
    /// Install an application package on the attached virtual device.
    Install(EmulatorInstallArgs),
    /// Launch an installed application.
    Launch(EmulatorLaunchArgs),
    /// Grant or revoke an Android application permission.
    Permission(EmulatorPermissionArgs),
    /// Read a bounded, filtered Android logcat snapshot.
    Logcat(EmulatorLogcatArgs),
    /// Release this caller's active stream lease.
    Detach(EmulatorTargetArgs),
    /// Stop the virtual device when Alera owns its lifecycle.
    Shutdown(EmulatorTargetArgs),
}

#[derive(Debug, Args, Clone, Default)]
pub struct EmulatorTargetArgs {
    /// Target an existing emulator tab. Takes precedence over --workspace-id.
    #[arg(long = "tab-id", value_name = "id")]
    pub tab_id: Option<String>,
    /// Target the emulator tab belonging to this workspace.
    #[arg(long = "workspace-id", value_name = "id")]
    pub workspace_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct EmulatorOptionalTargetArgs {
    #[command(flatten)]
    pub target: EmulatorTargetArgs,
}

#[derive(Debug, Args)]
pub struct EmulatorDevicesArgs {
    /// Restrict the inventory to one platform.
    #[arg(long, value_enum)]
    pub platform: Option<EmulatorPlatformArg>,
}

#[derive(Debug, Args)]
pub struct EmulatorAttachArgs {
    #[command(flatten)]
    pub target: EmulatorTargetArgs,
    #[arg(long, value_enum)]
    pub platform: EmulatorPlatformArg,
    /// Stable AVD name or simulator UDID from `emulator devices`.
    #[arg(long = "device-id", value_name = "id")]
    pub device_id: String,
}

#[derive(Debug, Args)]
pub struct EmulatorSnapshotArgs {
    #[command(flatten)]
    pub target: EmulatorTargetArgs,
    /// Return only the accessibility observation.
    #[arg(long = "no-screenshot")]
    pub no_screenshot: bool,
}

#[derive(Debug, Args)]
pub struct EmulatorObservedActionArgs {
    #[command(flatten)]
    pub target: EmulatorTargetArgs,
    /// Exact observation returned by `emulator snapshot`.
    #[arg(long = "snapshot-id", value_name = "id")]
    pub snapshot_id: String,
}

#[derive(Debug, Args)]
pub struct EmulatorTapArgs {
    #[command(flatten)]
    pub observed: EmulatorObservedActionArgs,
    /// Horizontal viewport position from 0.0 at the left to 1.0 at the right.
    #[arg(long, value_parser = parse_normalized_coordinate)]
    pub x: f64,
    /// Vertical viewport position from 0.0 at the top to 1.0 at the bottom.
    #[arg(long, value_parser = parse_normalized_coordinate)]
    pub y: f64,
}

#[derive(Debug, Args)]
pub struct EmulatorGestureArgs {
    #[command(flatten)]
    pub observed: EmulatorObservedActionArgs,
    #[arg(long = "from-x", value_parser = parse_normalized_coordinate)]
    pub from_x: f64,
    #[arg(long = "from-y", value_parser = parse_normalized_coordinate)]
    pub from_y: f64,
    #[arg(long = "to-x", value_parser = parse_normalized_coordinate)]
    pub to_x: f64,
    #[arg(long = "to-y", value_parser = parse_normalized_coordinate)]
    pub to_y: f64,
    #[arg(
        long = "duration-ms",
        default_value_t = 300,
        value_parser = clap::value_parser!(u64).range(1..=60_000)
    )]
    pub duration_ms: u64,
}

#[derive(Debug, Args)]
pub struct EmulatorTypeArgs {
    #[command(flatten)]
    pub observed: EmulatorObservedActionArgs,
    /// Text to type into the focused control.
    #[arg(long, value_name = "text", conflicts_with = "text_stdin")]
    pub text: Option<String>,
    /// Read text from stdin to keep it out of shell history.
    #[arg(long = "text-stdin", conflicts_with = "text")]
    pub text_stdin: bool,
}

#[derive(Debug, Args)]
pub struct EmulatorButtonArgs {
    #[command(flatten)]
    pub observed: EmulatorObservedActionArgs,
    #[arg(long, value_enum)]
    pub button: EmulatorButtonArg,
}

#[derive(Debug, Args)]
pub struct EmulatorRotateArgs {
    #[command(flatten)]
    pub observed: EmulatorObservedActionArgs,
    #[arg(long, value_enum)]
    pub orientation: EmulatorOrientationArg,
}

#[derive(Debug, Args)]
pub struct EmulatorInstallArgs {
    #[command(flatten)]
    pub target: EmulatorTargetArgs,
    /// Local APK or simulator-compatible application path.
    #[arg(long, value_name = "path")]
    pub path: String,
}

#[derive(Debug, Args)]
pub struct EmulatorLaunchArgs {
    #[command(flatten)]
    pub target: EmulatorTargetArgs,
    /// Android application id or iOS bundle identifier.
    #[arg(long = "bundle-id", value_name = "id")]
    pub bundle_id: String,
    /// Optional Android activity name.
    #[arg(long, value_name = "name")]
    pub activity: Option<String>,
}

#[derive(Debug, Args)]
pub struct EmulatorPermissionArgs {
    #[command(flatten)]
    pub target: EmulatorTargetArgs,
    #[arg(long = "bundle-id", value_name = "id")]
    pub bundle_id: String,
    #[arg(long, value_name = "permission")]
    pub permission: String,
    #[arg(long, value_enum)]
    pub operation: EmulatorPermissionOperationArg,
}

#[derive(Debug, Args)]
pub struct EmulatorLogcatArgs {
    #[command(flatten)]
    pub target: EmulatorTargetArgs,
    /// Maximum number of newest matching lines to return.
    #[arg(
        long = "max-lines",
        default_value_t = 200,
        value_parser = clap::value_parser!(u64).range(1..=1000)
    )]
    pub max_lines: u64,
    /// Include only these Android log tags. May be repeated.
    #[arg(long, value_name = "tag")]
    pub tag: Vec<String>,
    /// Minimum Android log priority.
    #[arg(long, value_enum)]
    pub level: Option<EmulatorLogLevelArg>,
    /// Include only lines containing this text.
    #[arg(long, value_name = "text")]
    pub contains: Option<String>,
    /// Read logs at or after this RFC 3339 timestamp.
    #[arg(long, value_name = "timestamp")]
    pub since: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum EmulatorPlatformArg {
    Android,
    Ios,
}

impl EmulatorPlatformArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Android => "android",
            Self::Ios => "ios",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum EmulatorButtonArg {
    Home,
    Back,
    AppSwitcher,
    Power,
    VolumeUp,
    VolumeDown,
}

impl EmulatorButtonArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Home => "home",
            Self::Back => "back",
            Self::AppSwitcher => "appSwitcher",
            Self::Power => "power",
            Self::VolumeUp => "volumeUp",
            Self::VolumeDown => "volumeDown",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum EmulatorOrientationArg {
    Portrait,
    LandscapeLeft,
    LandscapeRight,
    PortraitUpsideDown,
}

impl EmulatorOrientationArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Portrait => "portrait",
            Self::LandscapeLeft => "landscapeLeft",
            Self::LandscapeRight => "landscapeRight",
            Self::PortraitUpsideDown => "portraitUpsideDown",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum EmulatorPermissionOperationArg {
    Grant,
    Revoke,
}

impl EmulatorPermissionOperationArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Grant => "grant",
            Self::Revoke => "revoke",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum EmulatorLogLevelArg {
    Verbose,
    Debug,
    Info,
    Warn,
    Error,
    Fatal,
}

impl EmulatorLogLevelArg {
    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Verbose => "verbose",
            Self::Debug => "debug",
            Self::Info => "info",
            Self::Warn => "warn",
            Self::Error => "error",
            Self::Fatal => "fatal",
        }
    }
}

fn parse_normalized_coordinate(value: &str) -> Result<f64, String> {
    let parsed = value
        .parse::<f64>()
        .map_err(|_| "coordinate must be a number between 0 and 1".to_string())?;
    if parsed.is_finite() && (0.0..=1.0).contains(&parsed) {
        Ok(parsed)
    } else {
        Err("coordinate must be a finite number between 0 and 1".to_string())
    }
}
