pub mod frame_codec;

pub const PROTOCOL_VERSION: i64 = 4;
pub const RUNTIME_HOST_CAPABILITY: &str = "runtimeStore";
pub const RUNTIME_HOST_BOOTSTRAP_CAPABILITY: &str = "sshTargetBootstrap";
pub const RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY: &str = "managedWorkspaceLifecycle";
pub const RUNTIME_HOST_MOBILE_CAPABILITY: &str = "mobileCompanionAccess";
pub const RUNTIME_HOST_ORCHESTRATION_CAPABILITY: &str = "orchestration";
pub const RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY: &str =
    "orchestrationTerminalInspectionV1";
pub const RUNTIME_HOST_BINARY_FRAMES_CAPABILITY: &str = "binaryFrames";
pub const BINARY_FRAMES_ENABLED_EVENT: &str = "binaryFramesEnabled";
pub const MOBILE_EMULATOR_TAB_KIND: &str = "mobileEmulator";

pub const DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS: u64 = 30;
pub const DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS: u64 = 60 * 60;
pub const DEFAULT_SCROLLBACK_BYTES: u64 = 10 * 1000 * 1000;
