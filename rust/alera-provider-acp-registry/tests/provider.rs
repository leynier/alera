use alera_agent_transport::MockTransport;
use alera_provider_acp_registry::{
    AcpRegistryProvider, AcpRegistryProviderConfig, AcpRegistrySource,
};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput};
use serde_json::json;
use std::path::PathBuf;

#[tokio::test]
async fn generic_registry_rejects_unmapped_full_access_before_initialize() {
    let transport = MockTransport::new([]);
    let config = AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: "github-copilot-cli".into(),
        executable: Some(PathBuf::from("copilot")),
        runtime_mode: alera_provider_protocol::RuntimeMode::ApprovalRequired,
        ..Default::default()
    };
    let mut provider = AcpRegistryProvider::with_transport(transport, config).unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = alera_provider_protocol::RuntimeMode::FullAccess;
    let error = provider
        .start_session(input)
        .await
        .expect_err("generic registry has no mode mapping");
    assert!(matches!(
        error,
        alera_provider_protocol::ProviderError::Unsupported(_)
    ));
    assert!(provider.inner().client().transport().writes().is_empty());
}

#[tokio::test]
async fn generic_registry_rejects_configured_mode_mismatch_before_initialize() {
    let transport = MockTransport::new([]);
    let config = AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: "github-copilot-cli".into(),
        executable: Some(PathBuf::from("copilot")),
        runtime_mode: alera_provider_protocol::RuntimeMode::FullAccess,
        ..Default::default()
    };
    let mut provider = AcpRegistryProvider::with_transport(transport, config).unwrap();
    let error = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .expect_err("approval mode cannot override an unchangeable registry launch mode");
    assert!(matches!(
        error,
        alera_provider_protocol::ProviderError::Unsupported(_)
    ));
    assert!(provider.inner().client().transport().writes().is_empty());
}

#[tokio::test]
async fn generic_registry_rejects_matching_non_default_mode_before_initialize() {
    let transport = MockTransport::new([]);
    let config = AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: "github-copilot-cli".into(),
        executable: Some(PathBuf::from("copilot")),
        runtime_mode: alera_provider_protocol::RuntimeMode::FullAccess,
        ..Default::default()
    };
    let mut provider = AcpRegistryProvider::with_transport(transport, config).unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = alera_provider_protocol::RuntimeMode::FullAccess;
    let error = provider
        .start_session(input)
        .await
        .expect_err("generic registry cannot map even a matching full-access mode");
    assert!(matches!(
        error,
        alera_provider_protocol::ProviderError::Unsupported(_)
    ));
    assert!(provider.inner().client().transport().writes().is_empty());
}

#[tokio::test]
async fn local_recipe_preserves_agent_identity_and_supports_resume() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"sessionCapabilities":{"resume":true}},
                "authMethods":[],
                "configOptions":[{"id":"model","type":"select","currentValue":"default","options":[]}]
            }
        }),
        json!({
            "jsonrpc":"2.0",
            "id":2,
            "result":{
                "sessionId":"registry-session",
                "configOptions":[{"id":"model","type":"select","currentValue":"default","options":[]}]
            }
        }),
        json!({"jsonrpc":"2.0","id":3,"result":{}}),
    ]);
    let config = AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: "github-copilot-cli".into(),
        executable: Some(PathBuf::from("copilot")),
        model: Some("copilot-model".into()),
        runtime_mode: alera_provider_protocol::RuntimeMode::ApprovalRequired,
        ..Default::default()
    };
    let mut provider = AcpRegistryProvider::with_transport(transport, config).unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(session.native_thread_id, "registry-session");
    assert_eq!(session.model.as_deref(), Some("copilot-model"));
    let writes = provider.inner().client().transport().writes();
    assert!(writes
        .iter()
        .all(|write| write["params"]["configId"] != "mode"));
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
}
