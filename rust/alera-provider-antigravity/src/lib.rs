//! Rust provider boundary for Antigravity's ACP executable.
//!
//! The proprietary Antigravity host is intentionally external. This crate
//! contains launch/auth policy and delegates ACP lifecycle handling to the
//! shared runtime.

mod config;
mod provider;
mod skills;

pub use alera_provider_protocol;
pub use config::{
    AntigravityPermissionMode, AntigravityProviderConfig, ANTIGRAVITY_AUTH_METHOD,
    FORCE_FILE_STORAGE_ENV, GEMINI_HOME_ENV,
};
pub use provider::AntigravityProvider;
pub use skills::{antigravity_user_home, discover_skills, discover_skills_at};
