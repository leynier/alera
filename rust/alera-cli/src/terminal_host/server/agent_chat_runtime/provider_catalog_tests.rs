use super::super::provider_factory::{BoxedProvider, ProviderLaunch};
use super::*;
use alera_provider_protocol::ProviderError;
use async_trait::async_trait;
use std::sync::atomic::{AtomicUsize, Ordering};

#[derive(Default)]
struct CatalogFactory {
    discoveries: AtomicUsize,
    probes: AtomicUsize,
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
        self.probes.fetch_add(1, Ordering::SeqCst);
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
async fn configured_models_are_merged_with_real_discovery() {
    let factory = CatalogFactory {
        discovered: vec!["provider-model".into(), "configured-model".into()],
        ..Default::default()
    };
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
    assert_eq!(source, "discoveredAndConfigured");
    assert_eq!(
        models,
        vec![
            json!({"id":"provider-model", "label":"provider-model", "isDefault":false}),
            json!({"id":"configured-model", "label":"configured-model", "isDefault":false}),
            json!({"id":"default-model", "label":"default-model", "isDefault":true,"source":"configured"})
        ]
    );
    assert!(error.is_none());
    assert_eq!(factory.discoveries.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn no_model_discovery_produces_an_honest_provider_default() {
    let factory = Arc::new(CatalogFactory::default());
    let catalog = provider_catalog(
        factory.clone(),
        Arc::new(InstanceDirectory::default()),
        None,
        false,
    )
    .await;
    let entries = catalog["providers"].as_array().unwrap();
    assert_eq!(entries.len(), PROVIDERS.len());
    for entry in entries {
        assert_eq!(entry["modelsSource"], "providerDefault");
        assert_eq!(
            entry["models"],
            json!([{"id":null, "label":"Provider Default", "isDefault":true}])
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
    assert_eq!(factory.discoveries.load(Ordering::SeqCst), PROVIDERS.len());
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

#[tokio::test]
async fn catalog_cache_coalesces_reads_and_settings_edit_invalidates_it() {
    let factory = Arc::new(CatalogFactory::default());
    let instances = Arc::new(InstanceDirectory::default());
    let first = provider_catalog(factory.clone(), instances.clone(), None, false).await;
    let second = provider_catalog(factory.clone(), instances.clone(), None, false).await;
    assert_eq!(first, second);
    assert_eq!(factory.probes.load(Ordering::SeqCst), PROVIDERS.len());
    let (third, fourth) = tokio::join!(
        provider_catalog(factory.clone(), instances.clone(), None, false),
        provider_catalog(factory.clone(), instances.clone(), None, false)
    );
    assert_eq!(third, fourth);
    assert_eq!(factory.probes.load(Ordering::SeqCst), PROVIDERS.len());
    provider_catalog(factory.clone(), instances.clone(), None, true).await;
    assert_eq!(factory.probes.load(Ordering::SeqCst), PROVIDERS.len() * 2);
    instances
        .replace(vec![ProviderInstanceConfig {
            provider: "codex".into(),
            provider_instance_id: "codex".into(),
            enabled: false,
            ..Default::default()
        }])
        .await;
    let disabled = provider_catalog(factory.clone(), instances.clone(), None, false).await;
    assert_eq!(
        disabled["providers"].as_array().unwrap().len(),
        PROVIDERS.len()
    );
    let codex = disabled["providers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["providerInstanceId"] == "codex")
        .unwrap();
    assert_eq!(codex["enabled"], false);
    assert_eq!(codex["available"], false);
    assert_eq!(codex["auth"]["status"], "unknown");
}

#[tokio::test]
async fn stale_catalog_returns_snapshot_while_single_refresh_runs() {
    let factory = Arc::new(CatalogFactory::default());
    let instances = Arc::new(InstanceDirectory::default());
    let first = provider_catalog(factory.clone(), instances.clone(), None, false).await;
    instances.catalog_cache.lock().await.checked = Some(Instant::now() - CACHE_TTL);
    let stale = provider_catalog(factory.clone(), instances.clone(), None, false).await;
    assert_eq!(stale, first);
    tokio::task::yield_now().await;
    let _guard = instances.catalog_refresh.lock().await;
    assert_eq!(factory.probes.load(Ordering::SeqCst), PROVIDERS.len() * 2);
}

#[tokio::test]
async fn unconfigured_acp_requires_setup_without_claiming_a_missing_binary() {
    let factory = super::super::production_factory::ProductionProviderFactory;
    let instances = [
        None,
        Some(ProviderInstanceConfig {
            provider: "acpRegistry".into(),
            provider_instance_id: "blank-acp".into(),
            ..Default::default()
        }),
        Some(ProviderInstanceConfig {
            provider: "acpRegistry".into(),
            provider_instance_id: "empty-acp".into(),
            executable: Some(PathBuf::new()),
            ..Default::default()
        }),
        Some(ProviderInstanceConfig {
            provider: "acpRegistry".into(),
            provider_instance_id: "whitespace-acp".into(),
            executable: Some(" \t ".into()),
            ..Default::default()
        }),
    ];
    for instance in instances {
        let entry = entry(&factory, "acpRegistry".into(), instance, None).await;
        assert_eq!(entry["setupRequired"], true);
        assert_eq!(entry["available"], false);
        assert!(entry["installed"].is_null());
        assert!(entry["version"].is_null());
        assert_eq!(entry["auth"]["status"], "unknown");
        assert_eq!(entry["setup"], json!([]));
        assert_eq!(
            entry["unavailableReason"],
            "Configure an executable in Providers Settings."
        );
        assert!(entry["modelsError"].is_null());
    }
}

#[tokio::test]
async fn configured_invalid_acp_reports_safe_validation_failure_without_setup_required() {
    let instance = ProviderInstanceConfig {
        provider: "acpRegistry".into(),
        provider_instance_id: "invalid-acp".into(),
        executable: Some("/private/acp-sensitive-path".into()),
        env: std::collections::BTreeMap::from([("PRIVATE_ENV".into(), "private-env-value".into())]),
        options: serde_json::from_value(json!({"authMethodId":{"secret":"private-option-value"}}))
            .unwrap(),
        ..Default::default()
    };
    let entry = entry(
        &super::super::production_factory::ProductionProviderFactory,
        "acpRegistry".into(),
        Some(instance),
        None,
    )
    .await;
    assert_eq!(entry["setupRequired"], false);
    assert_eq!(entry["available"], false);
    assert!(entry["installed"].is_null());
    assert_eq!(entry["auth"]["status"], "unknown");
    assert_eq!(entry["setup"], json!([]));
    assert_eq!(
        entry["unavailableReason"],
        "Provider launch configuration is invalid."
    );
    let encoded = entry.to_string();
    for private in [
        "acp-sensitive-path",
        "private-env-value",
        "private-option-value",
        "authMethodId",
    ] {
        assert!(!encoded.contains(private));
    }
}

#[tokio::test]
async fn configured_missing_acp_binary_reports_safe_installation_failure() {
    let executable = std::env::temp_dir().join(format!("missing-acp-{}", uuid::Uuid::new_v4()));
    let instance = ProviderInstanceConfig {
        provider: "acpRegistry".into(),
        provider_instance_id: "missing-acp".into(),
        executable: Some(executable.clone()),
        ..Default::default()
    };
    let entry = entry(
        &super::super::production_factory::ProductionProviderFactory,
        "acpRegistry".into(),
        Some(instance),
        None,
    )
    .await;
    assert_eq!(entry["setupRequired"], false);
    assert_eq!(entry["available"], false);
    assert_eq!(entry["installed"], false);
    assert_eq!(
        entry["unavailableReason"],
        "Provider executable is unavailable."
    );
    assert!(!entry
        .to_string()
        .contains(&executable.to_string_lossy().to_string()));
}
