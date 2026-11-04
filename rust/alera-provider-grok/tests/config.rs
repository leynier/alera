use alera_provider_grok::{grok_spawn_args, GrokAuthMethod, GrokProviderConfig};
use alera_provider_protocol::RuntimeMode;
use std::ffi::OsString;

#[test]
fn launch_modes_match_grok_stdio_contract() {
    assert_eq!(
        grok_spawn_args(RuntimeMode::ApprovalRequired),
        ["--permission-mode", "default", "agent", "stdio"]
    );
    assert_eq!(
        grok_spawn_args(RuntimeMode::Auto),
        ["--permission-mode", "auto", "agent", "stdio"]
    );
    assert_eq!(
        grok_spawn_args(RuntimeMode::FullAccess),
        ["agent", "--always-approve", "stdio"]
    );
}

#[test]
fn referrer_default_preserves_explicit_override() {
    let config = GrokProviderConfig::default();
    assert_eq!(
        config
            .effective_env()
            .get(&OsString::from("GROK_OAUTH2_REFERRER")),
        Some(&OsString::from("alera"))
    );

    let mut overridden = config.clone();
    overridden.env.insert(
        OsString::from("GROK_OAUTH2_REFERRER"),
        OsString::from("custom"),
    );
    assert_eq!(
        overridden
            .effective_env()
            .get(&OsString::from("GROK_OAUTH2_REFERRER")),
        Some(&OsString::from("custom"))
    );
}

#[test]
fn api_key_wins_auth_method_when_present() {
    let mut config = GrokProviderConfig {
        auth_method: GrokAuthMethod::CachedToken,
        ..Default::default()
    };
    assert_eq!(config.resolved_auth_method(), GrokAuthMethod::CachedToken);
    config
        .env
        .insert(OsString::from("XAI_API_KEY"), OsString::from("secret"));
    assert_eq!(config.resolved_auth_method(), GrokAuthMethod::ApiKey);
}
