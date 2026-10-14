use alera_provider_protocol::{ProviderError, RuntimeMode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

pub const ANTIGRAVITY_AUTH_METHOD: &str = "oauth-personal";
pub const GEMINI_HOME_ENV: &str = "GEMINI_HOME";
pub const FORCE_FILE_STORAGE_ENV: &str = "AGY_ACP_FORCE_FILE_STORAGE";

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AntigravityPermissionMode {
    #[default]
    Default,
    AutoEdit,
    Yolo,
}

impl AntigravityPermissionMode {
    pub fn from_runtime_mode(mode: RuntimeMode) -> Result<Self, ProviderError> {
        match mode {
            RuntimeMode::ApprovalRequired | RuntimeMode::Auto => Ok(Self::Default),
            RuntimeMode::AutoAcceptEdits => Ok(Self::AutoEdit),
            RuntimeMode::FullAccess => Ok(Self::Yolo),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Default => "default",
            Self::AutoEdit => "auto_edit",
            Self::Yolo => "yolo",
        }
    }
}

#[derive(Debug, Clone)]
pub struct AntigravityProviderConfig {
    pub executable: PathBuf,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub profile_dir: Option<PathBuf>,
    pub auth_method_id: String,
    pub instance_id: String,
    pub model: Option<String>,
    pub runtime_mode: RuntimeMode,
    pub permission_mode: AntigravityPermissionMode,
    pub request_timeout: Duration,
    pub max_frame_bytes: usize,
    pub shutdown_timeout: Duration,
}

impl Default for AntigravityProviderConfig {
    fn default() -> Self {
        Self {
            executable: default_executable(),
            args: Vec::new(),
            cwd: None,
            env: BTreeMap::new(),
            profile_dir: None,
            auth_method_id: ANTIGRAVITY_AUTH_METHOD.to_owned(),
            instance_id: "antigravity-default".to_owned(),
            model: None,
            runtime_mode: RuntimeMode::ApprovalRequired,
            permission_mode: AntigravityPermissionMode::Default,
            request_timeout: Duration::from_secs(120),
            max_frame_bytes: 1024 * 1024,
            shutdown_timeout: Duration::from_secs(5),
        }
    }
}

impl AntigravityProviderConfig {
    pub fn validate(&self) -> Result<(), ProviderError> {
        if self.instance_id.trim().is_empty() {
            return Err(ProviderError::Validation(
                "instanceId must not be empty".into(),
            ));
        }
        if self.auth_method_id.trim().is_empty() {
            return Err(ProviderError::Validation(
                "authMethodId must not be empty".into(),
            ));
        }
        let inferred = self.effective_permission_mode()?;
        if self.permission_mode != AntigravityPermissionMode::Default
            && self.permission_mode != inferred
        {
            return Err(ProviderError::Validation(
                "permissionMode conflicts with runtimeMode".into(),
            ));
        }
        Ok(())
    }

    pub fn effective_permission_mode(&self) -> Result<AntigravityPermissionMode, ProviderError> {
        AntigravityPermissionMode::from_runtime_mode(self.runtime_mode)
    }

    pub fn spawn_args_for_platform(&self, platform: &str) -> Vec<OsString> {
        let mut args = self.args.clone();
        if platform.eq_ignore_ascii_case("linux") && self.profile_dir.is_some() {
            args.push(OsString::from("--uid="));
        }
        args
    }

    pub fn effective_env(&self) -> BTreeMap<OsString, OsString> {
        let mut env = self.env.clone();
        if let Some(profile) = &self.profile_dir {
            env.entry(OsString::from(GEMINI_HOME_ENV))
                .or_insert_with(|| profile.as_os_str().to_owned());
            env.entry(OsString::from(FORCE_FILE_STORAGE_ENV))
                .or_insert_with(|| OsString::from("1"));
            let temp = profile.join("tmp");
            if cfg!(windows) {
                env.entry(OsString::from("TEMP"))
                    .or_insert_with(|| temp.as_os_str().to_owned());
                env.entry(OsString::from("TMP"))
                    .or_insert_with(|| temp.as_os_str().to_owned());
            } else {
                env.entry(OsString::from("TMPDIR"))
                    .or_insert_with(|| temp.as_os_str().to_owned());
            }
        }
        env
    }
}

fn default_executable() -> PathBuf {
    if cfg!(windows) {
        PathBuf::from("agy_acp_server.exe")
    } else {
        PathBuf::from("agy_acp_server.par")
    }
}
