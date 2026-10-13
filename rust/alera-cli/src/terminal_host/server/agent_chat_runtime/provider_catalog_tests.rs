use super::super::provider_factory::{BoxedProvider, ProviderLaunch};
use super::*;
use alera_provider_protocol::ProviderError;
use async_trait::async_trait;
use std::sync::atomic::{AtomicUsize, Ordering};

#[derive(Default)]
struct CatalogFactory {
    discoveries: AtomicUsize,
    discovered: Vec<String>,
}

#[async_trait]
impl ProviderFactory for CatalogFactory {
    async fn spawn(&self, _: &ProviderLaunch) -> Result<BoxedProvider, ProviderError> {
        panic!("catalog must not spawn providers");
    }
    async fn availability(
        &self,
        _: &str,
        _: Option<&ProviderInstanceConfig>,
    ) -> Result<(), String> {
        Ok(())
    }
    async fn discover_models(
        &self,
        _: &str,
        _: Option<&ProviderInstanceConfig>,
        _: Option<PathBuf>,
    ) -> Option<Result<Vec<String>, String>> {
        self.discoveries.fetch_add(1, Ordering::SeqCst);
        Some(Ok(self.discovered.clone()))
    }
}

#[tokio::test]
async fn configured_models_are_reported_without_fake_discovery() {
    let factory = CatalogFactory::default();
    let instance = ProviderInstanceConfig {
        provider: "codex".into(),
        provider_instance_id: "configured".into(),
        models: vec![
            "configured-model".into(),
            "configured-model".into(),
            " ".into(),
        ],
        default_model: Some("default-model".into()),
        ..Default::default()
    };
    let (models, source, error) = models(&factory, "codex", Some(&instance), None, true).await;
    assert_eq!(source, "configured");
    assert_eq!(
        models,
        vec![
            json!({"id":"default-model", "label":"default-model", "isDefault":true}),
            json!({"id":"configured-model", "label":"configured-model", "isDefault":false})
        ]
    );
    assert!(error.is_none());
    assert_eq!(factory.discoveries.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn no_model_discovery_produces_an_honest_provider_default() {
    let factory = CatalogFactory::default();
    let catalog = provider_catalog(&factory, &InstanceDirectory::default(), None, false).await;
    let entries = catalog["providers"].as_array().unwrap();
    assert_eq!(entries.len(), PROVIDERS.len());
    for entry in entries {
        assert_eq!(entry["modelsSource"], "providerDefault");
        assert_eq!(
            entry["models"],
            json!([{"id":null, "label":"Provider default", "isDefault":true}])
        );
        assert_eq!(entry["capabilitiesSource"], "adapterExpected");
        assert!(entry["capabilities"]["mcpInjection"]["stdio"].is_boolean());
        assert!(entry["capabilities"]["mcpInjection"]["http"].is_boolean());
        assert!(entry["runtimeModes"]
            .as_array()
            .unwrap()
            .contains(&json!("approval-required")));
        assert!(entry["interactionModes"]
            .as_array()
            .unwrap()
            .contains(&json!("default")));
        if entry["provider"] == "pi" {
            assert_eq!(entry["capabilities"]["mcpInjection"]["http"], false);
        }
        if [
            json!("grok"),
            json!("antigravity"),
            json!("acpRegistry"),
            json!("muse"),
        ]
        .contains(&entry["provider"])
        {
            assert_eq!(entry["mcpInjectionSource"], "negotiated");
        }
    }
    assert_eq!(factory.discoveries.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn discovery_reports_only_the_provider_supplied_models() {
    let factory = CatalogFactory {
        discovered: vec!["provider-reported-model".into()],
        ..Default::default()
    };
    let (models, source, error) = models(&factory, "codex", None, None, true).await;
    assert_eq!(source, "discovered");
    assert_eq!(
        models,
        vec![
            json!({"id":"provider-reported-model", "label":"provider-reported-model", "isDefault":false})
        ]
    );
    assert!(error.is_none());
    assert_eq!(factory.discoveries.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn external_opencode_reports_no_mcp_and_catalog_excludes_private_configuration() {
    let instance = ProviderInstanceConfig {
        provider: "opencode".into(),
        provider_instance_id: "shared-server".into(),
        env: std::collections::BTreeMap::from([("PRIVATE_ENV".into(), "private-env-value".into())]),
        options: serde_json::from_value(
            json!({"serverUrl":"http://127.0.0.1:1234", "serverPassword":"private-password-value"}),
        )
        .unwrap(),
        ..Default::default()
    };
    let entry = entry(
        &CatalogFactory::default(),
        "opencode".into(),
        Some(instance),
        None,
        false,
    )
    .await;
    assert_eq!(
        entry["capabilities"]["mcpInjection"],
        json!({"stdio":false,"http":false})
    );
    let encoded = entry.to_string();
    assert!(!encoded.contains("private-env-value"));
    assert!(!encoded.contains("private-password-value"));
    assert!(!encoded.contains("serverUrl"));
}
