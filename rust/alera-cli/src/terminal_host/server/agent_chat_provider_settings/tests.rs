use super::*;
use async_trait::async_trait;
use std::collections::BTreeMap;
use std::sync::Mutex;

#[derive(Default)]
struct FakeSecrets(Mutex<BTreeMap<String, String>>);

#[async_trait]
impl ProviderSecrets for FakeSecrets {
    async fn load(&self, reference: &str) -> HostResult<Option<String>> {
        Ok(self.0.lock().unwrap().get(reference).cloned())
    }
    async fn save(&self, reference: &str, value: &str) -> HostResult<()> {
        self.0
            .lock()
            .unwrap()
            .insert(reference.into(), value.into());
        Ok(())
    }
    async fn clear(&self, reference: &str) -> HostResult<()> {
        self.0.lock().unwrap().remove(reference);
        Ok(())
    }
}

async fn service() -> (
    tempfile::TempDir,
    ProviderSettingsService,
    Arc<FakeSecrets>,
    Arc<Mutex<Vec<(String, Value)>>>,
) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let secrets = Arc::new(FakeSecrets::default());
    let events = Arc::new(Mutex::new(Vec::new()));
    let sink = events.clone();
    let mut service = ProviderSettingsService::new(
        store,
        Arc::new(InstanceDirectory::default()),
        dir.path(),
        "runtime-test",
        Arc::new(move |name, payload| {
            sink.lock().unwrap().push((name.into(), payload));
        }),
    );
    service.secrets = secrets.clone();
    service.initialize().await.unwrap();
    (dir, service, secrets, events)
}

fn desktop() -> CallerCtx {
    CallerCtx {
        scope: "desktop".into(),
        actor: "desktop".into(),
        mobile: false,
    }
}
fn mobile() -> CallerCtx {
    CallerCtx {
        scope: "mobile:test".into(),
        actor: "mobile:test".into(),
        mobile: true,
    }
}
fn error_code(error: HostError) -> String {
    match error {
        HostError::Conflict { code, .. } => code,
        _ => panic!("expected typed conflict"),
    }
}

#[tokio::test]
async fn secret_save_is_redacted_receipt_backed_and_clears_previous_value() {
    let (_dir, service, secrets, events) = service().await;
    let input = json!({"requestId":"secret-save","expectedRevision":0,"providerInstanceId":"codex","name":"OPENAI_API_KEY","value":"synthetic-private-secret"});
    let first = service
        .dispatch("agentChat.secrets.set", &input, &mobile())
        .await
        .unwrap();
    assert_eq!(first["revision"], 1);
    assert_eq!(first["instances"].as_array().unwrap().len(), 9);
    assert!(!first.to_string().contains("synthetic-private-secret"));
    assert_eq!(secrets.0.lock().unwrap().len(), 1);
    assert_eq!(
        service
            .dispatch("agentChat.secrets.set", &input, &mobile())
            .await
            .unwrap(),
        first
    );
    assert_eq!(events.lock().unwrap().len(), 1);
    assert_eq!(secrets.0.lock().unwrap().len(), 1);
    let records = service.store.agent_chat_provider_instances().await.unwrap();
    assert!(!records.instances[0]
        .envelope
        .to_string()
        .contains("synthetic-private-secret"));
    assert!(records.instances[0]
        .secret_refs
        .contains_key("OPENAI_API_KEY"));
    let clear = json!({"requestId":"clear","expectedRevision":1,"providerInstanceId":"codex","name":"OPENAI_API_KEY"});
    let cleared = service
        .dispatch("agentChat.secrets.clear", &clear, &mobile())
        .await
        .unwrap();
    assert_eq!(cleared["revision"], 2);
    assert!(secrets.0.lock().unwrap().is_empty());
    assert!(!events
        .lock()
        .unwrap()
        .iter()
        .any(|(_, event)| event.to_string().contains("synthetic-private-secret")));
}

#[tokio::test]
async fn mobile_edits_enabled_and_models_but_cannot_change_launch_or_create_instances() {
    let (_dir, service, _secrets, _events) = service().await;
    let enabled = json!({"requestId":"off","expectedRevision":0,"instance":{"providerInstanceId":"codex","enabled":false,"customModels":["custom"]}});
    service
        .dispatch("agentChat.providerInstances.upsert", &enabled, &mobile())
        .await
        .unwrap();
    assert!(!service.instances.enabled("codex"));
    let launch = json!({"requestId":"launch","expectedRevision":1,"instance":{"providerInstanceId":"codex","executable":"/new/path"}});
    assert_eq!(
        error_code(
            service
                .dispatch("agentChat.providerInstances.upsert", &launch, &mobile())
                .await
                .unwrap_err()
        ),
        "notAllowed"
    );
    let custom = json!({"requestId":"new","expectedRevision":1,"instance":{"providerInstanceId":"my-agent","provider":"codex"}});
    assert_eq!(
        error_code(
            service
                .dispatch("agentChat.providerInstances.upsert", &custom, &mobile())
                .await
                .unwrap_err()
        ),
        "notAllowed"
    );
    assert_eq!(error_code(service.dispatch("agentChat.providerInstances.remove",&json!({"requestId":"remove","expectedRevision":1,"providerInstanceId":"codex"}),&mobile()).await.unwrap_err()),"notAllowed");
}

#[tokio::test]
async fn custom_crud_preserves_other_instances_and_rejects_sensitive_values() {
    let (_dir, service, _secrets, _events) = service().await;
    let add = json!({"requestId":"custom-add","expectedRevision":0,"instance":{"providerInstanceId":"work","provider":"codex","label":"Work","customModels":["verified-custom"],"environment":[{"name":"TOKEN","sensitive":true}]}});
    let first = service
        .dispatch("agentChat.providerInstances.upsert", &add, &desktop())
        .await
        .unwrap();
    assert_eq!(first["instances"].as_array().unwrap().len(), 10);
    assert_eq!(
        service.instances.provider_of("work", None).as_deref(),
        Some("codex")
    );
    let plaintext = json!({"requestId":"unsafe","expectedRevision":1,"instance":{"providerInstanceId":"work","environment":[{"name":"TOKEN","sensitive":true,"value":"synthetic-private-token"}]}});
    let error = service
        .dispatch("agentChat.providerInstances.upsert", &plaintext, &desktop())
        .await
        .unwrap_err();
    assert!(!error.wire_message().contains("synthetic-private-token"));
    assert_eq!(
        service
            .store
            .agent_chat_provider_instances()
            .await
            .unwrap()
            .revision,
        1
    );
    let remove =
        json!({"requestId":"custom-remove","expectedRevision":1,"providerInstanceId":"work"});
    let removed = service
        .dispatch("agentChat.providerInstances.remove", &remove, &desktop())
        .await
        .unwrap();
    assert_eq!(removed["revision"], 2);
    assert_eq!(removed["instances"].as_array().unwrap().len(), 9);
    assert!(service.instances.provider_of("work", None).is_none());
    assert_eq!(
        service
            .dispatch("agentChat.providerInstances.remove", &remove, &desktop())
            .await
            .unwrap(),
        removed
    );
}

#[tokio::test]
async fn full_save_unsets_blank_launch_fields_partial_enable_preserves_and_builtin_remove_resets() {
    let (_dir, service, _secrets, _events) = service().await;
    let full = json!({"requestId":"full-save","expectedRevision":0,"instance":{"providerInstanceId":"codex","provider":"codex","label":"Work","executable":"/custom/codex","enabled":true,"args":["--custom"],"environment":[{"name":"WORK_ROOT","sensitive":false,"value":"/work"}],"options":{},"sensitiveOptions":[],"customModels":["custom-model"],"defaultModel":"custom-model"}});
    service
        .dispatch("agentChat.providerInstances.upsert", &full, &desktop())
        .await
        .unwrap();
    let disabled = json!({"requestId":"disable-partial","expectedRevision":1,"instance":{"providerInstanceId":"codex","provider":"codex","enabled":false}});
    service
        .dispatch("agentChat.providerInstances.upsert", &disabled, &desktop())
        .await
        .unwrap();
    let current = service.instances.find("codex").unwrap();
    assert_eq!(current.label.as_deref(), Some("Work"));
    assert_eq!(
        current.executable.as_deref(),
        Some(Path::new("/custom/codex"))
    );
    assert_eq!(current.models, vec!["custom-model"]);
    assert_eq!(current.env["WORK_ROOT"], "/work");
    assert!(!current.enabled);
    let unset = json!({"requestId":"full-unset","expectedRevision":2,"instance":{"providerInstanceId":"codex","provider":"codex","label":"","executable":"","args":[],"environment":[],"options":{},"sensitiveOptions":[],"customModels":[],"defaultModel":null}});
    service
        .dispatch("agentChat.providerInstances.upsert", &unset, &desktop())
        .await
        .unwrap();
    let current = service.instances.find("codex").unwrap();
    assert!(
        current.label.is_none() && current.executable.is_none() && current.default_model.is_none()
    );
    assert!(current.models.is_empty() && current.env.is_empty());
    let reset =
        json!({"requestId":"reset-builtin","expectedRevision":3,"providerInstanceId":"codex"});
    let snapshot = service
        .dispatch("agentChat.providerInstances.remove", &reset, &desktop())
        .await
        .unwrap();
    assert_eq!(snapshot["instances"].as_array().unwrap().len(), 9);
    assert!(service.instances.find("codex").is_none());
    assert_eq!(
        service.instances.provider_of("codex", None).as_deref(),
        Some("codex")
    );
    assert!(service.instances.enabled("codex"));
}

#[tokio::test]
async fn preferences_are_per_entry_and_revisions_and_receipts_preserve_prior_work() {
    let (_dir, service, _secrets, _events) = service().await;
    let first = json!({"requestId":"default","expectedRevision":0,"operations":[{"type":"setDefaultSelection","selection":{"providerInstanceId":"codex","model":null}}]});
    service
        .dispatch("agentChat.preferences.update", &first, &desktop())
        .await
        .unwrap();
    let second = json!({"requestId":"models","expectedRevision":1,"operations":[{"type":"setModels","providerInstanceId":"codex","hidden":["hidden"],"order":["visible"]},{"type":"setFavorites","favorites":[{"providerInstanceId":"codex","model":null}]}]});
    let updated = service
        .dispatch("agentChat.preferences.update", &second, &mobile())
        .await
        .unwrap();
    assert_eq!(updated["defaultSelection"]["providerInstanceId"], "codex");
    assert_eq!(updated["favorites"].as_array().unwrap().len(), 1);
    let stale = json!({"requestId":"stale","expectedRevision":0,"operations":[{"type":"setDefaultSelection","selection":null}]});
    assert_eq!(
        error_code(
            service
                .dispatch("agentChat.preferences.update", &stale, &desktop())
                .await
                .unwrap_err()
        ),
        "revisionConflict"
    );
    let mut conflict = first.clone();
    conflict["operations"][0]["selection"] = Value::Null;
    assert_eq!(
        error_code(
            service
                .dispatch("agentChat.preferences.update", &conflict, &desktop())
                .await
                .unwrap_err()
        ),
        "receiptConflict"
    );
    assert!(service.dispatch("agentChat.preferences.update",&json!({"requestId":"remember","expectedRevision":2,"operations":[{"type":"rememberedSelection","selection":{"providerInstanceId":"pi"}}]}),&desktop()).await.is_err());
}

#[tokio::test]
async fn less_trusted_callers_cannot_read_or_mutate_settings() {
    let (_dir, service, _secrets, _events) = service().await;
    for scope in ["chat:bound", "satellite:reverse", "agent:bound"] {
        let caller = CallerCtx {
            scope: scope.into(),
            actor: scope.into(),
            mobile: false,
        };
        assert_eq!(
            error_code(
                service
                    .dispatch("agentChat.providerInstances.get", &json!({}), &caller)
                    .await
                    .unwrap_err()
            ),
            "notAllowed"
        );
    }
}

#[tokio::test]
async fn legacy_import_moves_secrets_and_keeps_private_lossless_backup() {
    let (dir, service, secrets, _events) = service().await;
    let legacy = json!({"instances":[{"providerInstanceId":"work-cursor","provider":"cursor","env":{"PRIVATE_KEY":"legacy-env-secret"},"options":{"apiKey":"legacy-option-secret"},"models":["custom"]}]});
    tokio::fs::write(
        dir.path().join("agent-chat-providers.json"),
        legacy.to_string(),
    )
    .await
    .unwrap();
    service.initialize().await.unwrap();
    let snapshot = service.snapshot().await.unwrap();
    assert_eq!(snapshot["revision"], 1);
    assert!(!snapshot.to_string().contains("legacy-env-secret"));
    assert!(!snapshot.to_string().contains("legacy-option-secret"));
    assert_eq!(secrets.0.lock().unwrap().len(), 2);
    assert!(dir
        .path()
        .join("agent-chat-providers.json.imported")
        .exists());
    assert!(!dir.path().join("agent-chat-providers.json").exists());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            std::fs::metadata(dir.path().join("agent-chat-providers.json.imported"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }
}

#[tokio::test]
async fn invalid_legacy_source_is_retained_without_values_in_error() {
    let (dir, service, secrets, _events) = service().await;
    let input = r#"{"instances":[{"providerInstanceId":"unknown","provider":"unsupported","env":{"TOKEN":"private-retained-secret"}}]}"#;
    tokio::fs::write(dir.path().join("agent-chat-providers.json"), input)
        .await
        .unwrap();
    service.initialize().await.unwrap();
    let snapshot = service.snapshot().await.unwrap();
    assert!(snapshot["migrationError"].is_string());
    assert!(!snapshot.to_string().contains("private-retained-secret"));
    assert_eq!(
        tokio::fs::read_to_string(dir.path().join("agent-chat-providers.json"))
            .await
            .unwrap(),
        input
    );
    assert!(secrets.0.lock().unwrap().is_empty());
}

struct FailingSecrets {
    saved: Mutex<BTreeMap<String, String>>,
}
#[async_trait]
impl ProviderSecrets for FailingSecrets {
    async fn load(&self, reference: &str) -> HostResult<Option<String>> {
        Ok(self.saved.lock().unwrap().get(reference).cloned())
    }
    async fn save(&self, reference: &str, value: &str) -> HostResult<()> {
        let mut saved = self.saved.lock().unwrap();
        if !saved.is_empty() {
            return Err(HostError::state("Credential save failed."));
        }
        saved.insert(reference.into(), value.into());
        Ok(())
    }
    async fn clear(&self, reference: &str) -> HostResult<()> {
        self.saved.lock().unwrap().remove(reference);
        Ok(())
    }
}

#[tokio::test]
async fn migration_credential_failure_rolls_back_all_rows_and_preserves_source() {
    let (dir, mut service, _secrets, _events) = service().await;
    let failing = Arc::new(FailingSecrets {
        saved: Default::default(),
    });
    service.secrets = failing.clone();
    let source = json!([{"providerInstanceId":"work","provider":"codex","env":{"KEY_ONE":"private-first-value","KEY_TWO":"private-second-value"}}]).to_string();
    tokio::fs::write(dir.path().join("agent-chat-providers.json"), &source)
        .await
        .unwrap();
    service.initialize().await.unwrap();
    assert_eq!(
        service
            .store
            .agent_chat_provider_instances()
            .await
            .unwrap()
            .revision,
        0
    );
    assert!(failing.saved.lock().unwrap().is_empty());
    assert_eq!(
        tokio::fs::read_to_string(dir.path().join("agent-chat-providers.json"))
            .await
            .unwrap(),
        source
    );
    assert!(!dir
        .path()
        .join("agent-chat-providers.json.imported")
        .exists());
}
