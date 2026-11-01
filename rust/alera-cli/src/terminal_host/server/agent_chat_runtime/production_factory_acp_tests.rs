//! Launch configuration of the ACP-based providers.

use super::launch_config::{build_config, configured_models, ProductionConfig};
use super::*;
use alera_provider_protocol::RuntimeMode;

fn launch(provider: &str) -> ProviderLaunch {
    ProviderLaunch {
        chat_id: "chat".into(),
        generation: 1,
        provider: provider.into(),
        provider_instance_id: format!("{provider}-test"),
        cwd: Some(std::env::temp_dir().join("chat-workspace")),
        model: Some("selected-model".into()),
        runtime_mode: RuntimeMode::ApprovalRequired,
        instance: Some(ProviderInstanceConfig {
            provider_instance_id: format!("{provider}-test"),
            provider: provider.into(),
            executable: Some("custom-provider".into()),
            default_model: Some("configured-default".into()),
            models: vec![
                "custom-a".into(),
                " ".into(),
                "configured-default".into(),
                "custom-b".into(),
            ],
            ..Default::default()
        }),
        mcp_servers: Vec::new(),
        env: BTreeMap::new(),
        instructions: Vec::new(),
    }
}

const EXPECTED: [&str; 3] = ["custom-a", "configured-default", "custom-b"];

#[test]
fn configured_models_join_the_instance_models_and_default_once() {
    let launch = launch("grok");
    assert_eq!(configured_models(launch.instance.as_ref()), EXPECTED);
    assert!(configured_models(None).is_empty());
}

#[test]
fn acp_wrappers_receive_custom_and_default_models() {
    for provider in ["grok", "antigravity", "acpRegistry"] {
        let launch = launch(provider);
        let models = match build_config(&launch, &BTreeMap::new()).unwrap() {
            ProductionConfig::Grok(config) => config.custom_models,
            ProductionConfig::Antigravity(config) => config.custom_models,
            ProductionConfig::Registry(config) => config.custom_models,
            _ => panic!("{provider} is an ACP provider"),
        };
        assert_eq!(models, EXPECTED, "{provider}");
    }
}

#[tokio::test]
async fn a_missing_antigravity_runtime_is_named_in_the_catalog() {
    let instance = ProviderInstanceConfig {
        provider_instance_id: "antigravity-missing".into(),
        provider: "antigravity".into(),
        executable: Some("/nonexistent/alera-test/agy_acp_server.par".into()),
        ..Default::default()
    };
    let status = ProductionProviderFactory
        .status("antigravity", Some(&instance))
        .await;
    assert!(!status.available);
    assert_eq!(status.installed, Some(false));
    assert_eq!(
        status.unavailable_reason.as_deref(),
        Some(alera_provider_antigravity::MISSING_RUNTIME_MESSAGE)
    );
}

#[test]
fn an_fx_acp_agent_launches_with_the_fx_flavor() {
    let mut launch = launch("acpRegistry");
    let instance = launch.instance.as_mut().unwrap();
    instance.executable = Some("fx".into());
    instance.args = Some(vec!["acp".into()]);
    instance
        .options
        .insert("agentId".into(), serde_json::json!("fx"));
    let ProductionConfig::Registry(config) = build_config(&launch, &BTreeMap::new()).unwrap()
    else {
        panic!("an ACP agent launches through the registry");
    };
    assert_eq!(
        config.agent_flavor(),
        alera_provider_acp_registry::AcpRegistryAgentFlavor::Fx
    );
    assert_eq!(config.args, vec![std::ffi::OsString::from("acp")]);
}
