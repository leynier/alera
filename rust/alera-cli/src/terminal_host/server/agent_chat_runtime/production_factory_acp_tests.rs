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
