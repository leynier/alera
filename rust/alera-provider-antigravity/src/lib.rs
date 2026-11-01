//! Rust provider boundary for Antigravity's ACP executable.
//!
//! The proprietary Antigravity host is intentionally external. This crate
//! contains launch/auth policy and delegates ACP lifecycle handling to the
//! shared runtime.

mod config;
mod models;
mod probe;
mod provider;
mod session_files;
mod skills;

pub use alera_provider_protocol;
pub use config::{
    AntigravityPermissionMode, AntigravityProviderConfig, ANTIGRAVITY_AUTH_METHOD,
    ANTIGRAVITY_CLIENT_NAME, ANTIGRAVITY_CLIENT_VERSION, FORCE_FILE_STORAGE_ENV, GEMINI_HOME_ENV,
};
pub use models::{
    models_from_session, thinking_from_options, AntigravityModel, AntigravityThinking,
};
pub use probe::{discover_models, probe_cwd, probe_models};
pub use provider::AntigravityProvider;
pub use session_files::{profile_root, remove_session_files};
pub use skills::{antigravity_user_home, discover_skills, discover_skills_at};
