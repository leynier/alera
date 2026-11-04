use super::super::super::agent_chat_runtime::{CallerCtx, InstanceDirectory};
use super::super::{credentials::ProviderSecrets, ProviderSettingsService};
use super::*;
use alera_core::runtime::RuntimeStore;
use async_trait::async_trait;
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct Secrets(Mutex<BTreeMap<String, String>>);
#[async_trait]
impl ProviderSecrets for Secrets {
    async fn load(&self, key: &str) -> HostResult<Option<String>> {
        Ok(self.0.lock().unwrap().get(key).cloned())
    }
    async fn save(&self, key: &str, value: &str) -> HostResult<()> {
        self.0.lock().unwrap().insert(key.into(), value.into());
        Ok(())
    }
    async fn clear(&self, key: &str) -> HostResult<()> {
        self.0.lock().unwrap().remove(key);
        Ok(())
    }
}
async fn fixture() -> (tempfile::TempDir, ProviderSettingsService) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let mut service = ProviderSettingsService::new(
        store,
        Arc::new(InstanceDirectory::default()),
        dir.path(),
        "setup-test",
        Arc::new(|_, _| {}),
    );
    service.secrets = Arc::new(Secrets::default());
    service.initialize().await.unwrap();
    (dir, service)
}
fn desktop() -> CallerCtx {
    CallerCtx {
        scope: "desktop".into(),
        actor: "desktop".into(),
        mobile: false,
    }
}
fn launch(id: &str) -> TerminalHostLaunch {
    TerminalHostLaunch {
        label: "Display".into(),
        shell: "untrusted-shell".into(),
        arguments: vec!["untrusted-argument".into()],
        environment: BTreeMap::from([
            ("CODEX_HOME".into(), "client-default".into()),
            ("CLAUDE_CONFIG_DIR".into(), "client-default".into()),
            ("CLIENT_OVERRIDE".into(), "client".into()),
        ]),
        provider_setup: Some(ProviderSetupContext {
            provider_instance_id: id.into(),
            action: "signIn".into(),
        }),
    }
}
async fn add(service: &ProviderSettingsService, provider: &str, home_name: &str) -> Value {
    service.dispatch("agentChat.providerInstances.upsert",&json!({"requestId":"profile","expectedRevision":0,
        "instance":{"providerInstanceId":"work","provider":provider,"enabled":true,"executable":"/custom/provider",
        "environment":[{"name":home_name,"sensitive":false,"value":"profile-home"},{"name":"SETUP_TOKEN","sensitive":true}]}}),&desktop()).await.unwrap()
}

#[tokio::test]
async fn setup_honors_codex_and_claude_profiles_without_exposing_secrets() {
    for (provider, home_name, args) in [
        ("codex", "CODEX_HOME", vec!["login"]),
        ("claudeAgent", "CLAUDE_CONFIG_DIR", vec!["auth", "login"]),
    ] {
        let (_dir, service) = fixture().await;
        let saved = add(&service, provider, home_name).await;
        let secret = service
            .dispatch(
                "agentChat.secrets.set",
                &json!({"requestId":"secret","expectedRevision":saved["revision"],
            "providerInstanceId":"work","name":"SETUP_TOKEN","value":"synthetic-setup-secret"}),
                &desktop(),
            )
            .await
            .unwrap();
        let mut launch = launch("work");
        let environment = BTreeMap::from([
            ("LOGIN_ONLY".into(), "login".into()),
            ("CLIENT_OVERRIDE".into(), "login".into()),
        ]);
        service
            .prepare_provider_setup_with_environment(&mut launch, environment)
            .await
            .unwrap();
        assert_eq!(launch.shell, "/custom/provider");
        assert_eq!(launch.arguments, args);
        assert_eq!(launch.environment[home_name], "profile-home");
        assert_eq!(launch.environment["SETUP_TOKEN"], "synthetic-setup-secret");
        assert_eq!(launch.environment["CLIENT_OVERRIDE"], "client");
        assert_eq!(launch.environment["LOGIN_ONLY"], "login");
        assert_eq!(launch.to_json()["environment"], json!({}));
        assert!(!launch.to_json().to_string().contains("profile-home"));
        assert!(!format!("{launch:?}").contains("profile-home"));
        for public in [
            saved.to_string(),
            secret.to_string(),
            launch.to_json().to_string(),
            format!("{launch:?}"),
        ] {
            assert!(!public.contains("synthetic-setup-secret"));
        }
    }
}

#[test]
fn setup_rejects_unknown_actions_and_command_tampering() {
    for value in [
        json!({"providerInstanceId":"codex","action":"run"}),
        json!({"providerInstanceId":"codex","action":"signIn","command":"arbitrary"}),
        json!({"providerInstanceId":"codex","action":"signIn","environment":{"TOKEN":"secret"}}),
    ] {
        assert!(ProviderSetupContext::from_json(&value).is_err());
    }
    let normal =
        TerminalHostLaunch::from_json(&json!({"shell":"shell","environment":{"NORMAL":"value"}}))
            .unwrap();
    assert_eq!(normal.to_json()["environment"]["NORMAL"], "value");
    assert!(normal.to_json().get("providerSetup").is_none());
}

#[tokio::test]
async fn setup_rechecks_disabled_removed_and_unsupported_instances() {
    let (_dir, service) = fixture().await;
    add(&service, "codex", "CODEX_HOME").await;
    let context = launch("work").provider_setup.unwrap();
    service.validate_provider_setup(&context).await.unwrap();
    service
        .dispatch(
            "agentChat.providerInstances.upsert",
            &json!({"requestId":"off","expectedRevision":1,
        "instance":{"providerInstanceId":"work","enabled":false}}),
            &desktop(),
        )
        .await
        .unwrap();
    assert!(service.validate_provider_setup(&context).await.is_err());
    service
        .dispatch(
            "agentChat.providerInstances.remove",
            &json!({"requestId":"remove","expectedRevision":2,"providerInstanceId":"work"}),
            &desktop(),
        )
        .await
        .unwrap();
    assert!(service.validate_provider_setup(&context).await.is_err());
    let mut unsupported = launch("cursor").provider_setup.unwrap();
    assert!(service.validate_provider_setup(&unsupported).await.is_err());
    unsupported.provider_instance_id = "codex".into();
    unsupported.action = "update".into();
    assert!(service.validate_provider_setup(&unsupported).await.is_err());
}

#[tokio::test]
async fn setup_cannot_silently_ignore_custom_launch_arguments() {
    let (_dir, service) = fixture().await;
    service
        .dispatch(
            "agentChat.providerInstances.upsert",
            &json!({"requestId":"args","expectedRevision":0,
        "instance":{"providerInstanceId":"codex","args":["--profile","special"]}}),
            &desktop(),
        )
        .await
        .unwrap();
    assert!(service
        .validate_provider_setup(&launch("codex").provider_setup.unwrap())
        .await
        .is_err());
}

#[tokio::test]
async fn missing_saved_secret_refuses_setup_without_hydrating_any_public_state() {
    let (_dir, service) = fixture().await;
    add(&service, "codex", "CODEX_HOME").await;
    service
        .dispatch(
            "agentChat.secrets.set",
            &json!({"requestId":"secret","expectedRevision":1,
        "providerInstanceId":"work","name":"SETUP_TOKEN","value":"synthetic-missing-token"}),
            &desktop(),
        )
        .await
        .unwrap();
    let record = service
        .store
        .agent_chat_provider_instances()
        .await
        .unwrap()
        .instances
        .pop()
        .unwrap();
    service
        .secrets
        .clear(&record.secret_refs["SETUP_TOKEN"])
        .await
        .unwrap();
    let mut launch = launch("work");
    let error = service
        .prepare_provider_setup_with_environment(&mut launch, BTreeMap::new())
        .await
        .unwrap_err();
    assert!(!error.wire_message().contains("synthetic-missing-token"));
    assert!(!launch
        .to_json()
        .to_string()
        .contains("synthetic-missing-token"));
    assert_eq!(launch.shell, "untrusted-shell");
}
