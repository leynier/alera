use alera_provider_antigravity::{
    AntigravityPermissionMode, AntigravityProviderConfig, ANTIGRAVITY_AUTH_METHOD,
    FORCE_FILE_STORAGE_ENV, GEMINI_HOME_ENV,
};
use alera_provider_protocol::RuntimeMode;
use std::ffi::OsString;
use std::path::PathBuf;

#[test]
fn runtime_modes_map_to_native_permission_modes() {
    assert_eq!(
        AntigravityPermissionMode::from_runtime_mode(RuntimeMode::ApprovalRequired).unwrap(),
        AntigravityPermissionMode::Default
    );
    assert_eq!(
        AntigravityPermissionMode::from_runtime_mode(RuntimeMode::Auto).unwrap(),
        AntigravityPermissionMode::Default
    );
    assert_eq!(
        AntigravityPermissionMode::from_runtime_mode(RuntimeMode::AutoAcceptEdits).unwrap(),
        AntigravityPermissionMode::AutoEdit
    );
    assert_eq!(
        AntigravityPermissionMode::from_runtime_mode(RuntimeMode::FullAccess).unwrap(),
        AntigravityPermissionMode::Yolo
    );
}

#[test]
fn conflicting_explicit_permission_mode_is_rejected() {
    let config = AntigravityProviderConfig {
        runtime_mode: RuntimeMode::ApprovalRequired,
        permission_mode: AntigravityPermissionMode::Yolo,
        ..Default::default()
    };
    assert!(config.validate().is_err());
}

#[test]
fn linux_profile_uid_and_environment_are_explicit() {
    let mut config = AntigravityProviderConfig {
        profile_dir: Some(PathBuf::from("/tmp/agy-profile")),
        ..Default::default()
    };
    assert_eq!(config.auth_method_id, ANTIGRAVITY_AUTH_METHOD);
    assert_eq!(
        config.spawn_args_for_platform("linux"),
        [OsString::from("--uid=")]
    );
    assert_eq!(
        config.effective_env().get(&OsString::from(GEMINI_HOME_ENV)),
        Some(&OsString::from("/tmp/agy-profile"))
    );
    assert_eq!(
        config
            .effective_env()
            .get(&OsString::from(FORCE_FILE_STORAGE_ENV)),
        Some(&OsString::from("1"))
    );

    config.env.insert(
        OsString::from("ANTIGRAVITY_PROFILE_DIR"),
        OsString::from("custom"),
    );
    assert_eq!(
        config
            .effective_env()
            .get(&OsString::from("ANTIGRAVITY_PROFILE_DIR")),
        Some(&OsString::from("custom"))
    );
}
