use super::*;
use std::sync::atomic::AtomicU64;

fn config_dir(settings: Option<&str>) -> String {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let dir = std::env::temp_dir().join(format!(
        "alera-claude-permission-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    if let Some(settings) = settings {
        std::fs::write(dir.join("settings.json"), settings).unwrap();
    }
    dir.to_string_lossy().into_owned()
}

fn launch(settings: Option<&str>, runtime_mode: RuntimeMode) -> (Option<String>, bool) {
    let mut config = ClaudeProviderConfig::default();
    config
        .options
        .env
        .insert("CLAUDE_CONFIG_DIR".into(), config_dir(settings));
    let provider = ClaudeProvider::new(config).unwrap();
    let input = SessionStartInput {
        runtime_mode,
        ..SessionStartInput::new("app")
    };
    let (options, stepped_down) = provider.launch_options(&input).unwrap();
    (options.permission_mode, stepped_down)
}

const NO_BYPASS: &str = r#"{"permissions": {"disableBypassPermissionsMode": "disable"}}"#;
const NO_BYPASS_OR_AUTO: &str =
    r#"{"permissions": {"disableBypassPermissionsMode": "disable", "disableAutoMode": "disable"}}"#;

#[test]
fn full_access_steps_down_when_settings_disable_bypass() {
    assert_eq!(
        launch(Some(NO_BYPASS), RuntimeMode::FullAccess),
        (Some("auto".into()), true)
    );
    assert_eq!(
        launch(Some(NO_BYPASS_OR_AUTO), RuntimeMode::FullAccess),
        (Some("default".into()), true)
    );
    assert_eq!(
        launch(None, RuntimeMode::FullAccess),
        (Some("bypassPermissions".into()), false)
    );
    assert_eq!(
        launch(Some(NO_BYPASS), RuntimeMode::ApprovalRequired),
        (Some("default".into()), false)
    );
    assert_eq!(
        launch(Some(NO_BYPASS), RuntimeMode::Auto),
        (Some("dontAsk".into()), false)
    );
}

#[test]
fn a_reported_mode_is_adopted_and_a_refused_bypass_is_announced_once() {
    let options = ClaudeAgentOptions {
        permission_mode: Some("bypassPermissions".into()),
        ..Default::default()
    };
    let mut permission = LaunchPermission::new(&options, false, false);
    assert!(!permission.adopt_reported("plan", false));
    assert!(permission.adopt_reported("default", false));
    assert_eq!(permission.base_mode(), "default");
    assert!(permission.take_notice());
    assert!(!permission.take_notice());
    assert!(!permission.adopt_reported("default", false));

    let options = ClaudeAgentOptions {
        permission_mode: Some("acceptEdits".into()),
        ..Default::default()
    };
    let mut permission = LaunchPermission::new(&options, false, false);
    assert!(!permission.adopt_reported("default", false));
    assert_eq!(permission.base_mode(), "default");
    assert!(!permission.adopt_reported("dontAsk", true));
    assert_eq!(permission.base_mode(), "default");
}
