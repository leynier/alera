use std::collections::BTreeMap;

use serde_json::{json, Value};

use super::agent_chat_test_support::store;
use super::*;

pub(super) fn settings_receipt(id: &str) -> AgentChatReceipt {
    AgentChatReceipt {
        caller_scope: "desktop".into(),
        request_id: id.into(),
        digest: agent_chat_command_digest(&json!({"id": id})),
        receipt: json!({}),
    }
}

fn edit(section: &str, key: Option<&str>, value: Value) -> AgentChatPreferenceOperation {
    AgentChatPreferenceOperation {
        section: section.into(),
        key: key.map(str::to_string),
        value: Some(value),
    }
}

pub(super) fn provider_envelope(id: &str) -> Value {
    json!({"providerInstanceId": id, "provider": "codex", "enabled": true,
        "environment": [{"name": "API_KEY", "sensitive": true}], "options": {}, "customModels": []})
}

#[tokio::test]
async fn preferences_preserve_other_entries_replay_original_response_and_reopen() {
    let (dir, store) = store().await;
    assert_eq!(store.agent_chat_preferences().await.unwrap()["revision"], 0);
    let first = settings_receipt("project-default");
    let operations = [edit(
        "projectDefaults",
        Some("project"),
        json!({"providerInstanceId": "codex", "model": null}),
    )];
    let applied = store
        .update_agent_chat_preferences(0, &operations, &first)
        .await
        .unwrap();
    assert!(matches!(applied, AgentChatSettingsOutcome::Applied(_)));
    store
        .update_agent_chat_preferences(
            1,
            &[
                edit(
                    "defaultSelection",
                    None,
                    json!({"providerInstanceId": "claudeAgent"}),
                ),
                edit(
                    "models",
                    Some("codex"),
                    json!({"hidden": ["hidden"], "order": ["visible", "hidden"]}),
                ),
                edit(
                    "favorites",
                    None,
                    json!([{"providerInstanceId": "codex", "model": null}]),
                ),
            ],
            &settings_receipt("desktop-settings"),
        )
        .await
        .unwrap();
    let remembered = json!({"providerInstanceId": "pi", "model": "some-model"});
    store
        .remember_agent_chat_selection(&remembered, &settings_receipt("remember"))
        .await
        .unwrap();
    let current = store.agent_chat_preferences().await.unwrap();
    assert_eq!(current["revision"], 3);
    assert_eq!(
        current["projectDefaults"]["project"]["providerInstanceId"],
        "codex"
    );
    assert_eq!(
        current["defaultSelection"]["providerInstanceId"],
        "claudeAgent"
    );
    assert_eq!(current["rememberedSelection"], remembered);
    assert_eq!(current["favorites"].as_array().unwrap().len(), 1);
    let replay = store
        .update_agent_chat_preferences(0, &operations, &first)
        .await
        .unwrap();
    assert!(matches!(replay, AgentChatSettingsOutcome::Replay(value) if value["revision"] == 1));
    let mut conflict = first.clone();
    conflict.digest = "different-payload".into();
    assert_eq!(
        store
            .update_agent_chat_preferences(3, &operations, &conflict)
            .await
            .unwrap(),
        AgentChatSettingsOutcome::ReceiptConflict
    );
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(reopened.agent_chat_preferences().await.unwrap(), current);
}

#[tokio::test]
async fn competing_preferences_use_revision_without_lost_updates() {
    let (dir, store) = store().await;
    let phone = RuntimeStore::open(dir.path()).await.unwrap();
    let desktop_ops = [edit(
        "projectDefaults",
        Some("desktop"),
        json!({"providerInstanceId": "codex"}),
    )];
    let phone_ops = [edit(
        "projectDefaults",
        Some("phone"),
        json!({"providerInstanceId": "pi"}),
    )];
    let desktop_receipt = settings_receipt("desktop");
    let phone_receipt = settings_receipt("phone");
    let (desktop, phone_result) = tokio::join!(
        store.update_agent_chat_preferences(0, &desktop_ops, &desktop_receipt),
        phone.update_agent_chat_preferences(0, &phone_ops, &phone_receipt),
    );
    let desktop = desktop.unwrap();
    let phone_result = phone_result.unwrap();
    assert!(matches!(
        (&desktop, &phone_result),
        (
            AgentChatSettingsOutcome::Applied(_),
            AgentChatSettingsOutcome::RevisionConflict { revision: 1 }
        ) | (
            AgentChatSettingsOutcome::RevisionConflict { revision: 1 },
            AgentChatSettingsOutcome::Applied(_)
        )
    ));
    if matches!(desktop, AgentChatSettingsOutcome::RevisionConflict { .. }) {
        store
            .update_agent_chat_preferences(1, &desktop_ops, &desktop_receipt)
            .await
            .unwrap();
    } else {
        phone
            .update_agent_chat_preferences(1, &phone_ops, &phone_receipt)
            .await
            .unwrap();
    }
    let result = store.agent_chat_preferences().await.unwrap();
    assert_eq!(result["projectDefaults"].as_object().unwrap().len(), 2);
    assert_eq!(result["revision"], 2);
}

#[tokio::test]
async fn receipt_failure_rolls_back_preferences_and_provider_revision() {
    let (_dir, store) = store().await;
    sqlx::query("CREATE TRIGGER rejectSettingsReceipt BEFORE INSERT ON agentChatReceipts BEGIN SELECT RAISE(ABORT, 'reject settings'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .update_agent_chat_preferences(
            0,
            &[edit(
                "defaultSelection",
                None,
                json!({"providerInstanceId": "codex"})
            )],
            &settings_receipt("preference")
        )
        .await
        .is_err());
    assert_eq!(store.agent_chat_preferences().await.unwrap()["revision"], 0);
    let operation = AgentChatProviderInstanceMutation::Upsert {
        provider_instance_id: "work".into(),
        envelope: provider_envelope("work"),
    };
    assert!(store
        .mutate_agent_chat_provider_instances(0, &operation, &settings_receipt("provider"))
        .await
        .is_err());
    let providers = store.agent_chat_provider_instances().await.unwrap();
    assert_eq!(providers.revision, 0);
    assert!(providers.instances.is_empty());
}

#[tokio::test]
async fn provider_secret_refs_are_durable_and_never_enter_response_or_receipt() {
    let (dir, store) = store().await;
    let opaque = uuid::Uuid::new_v4().to_string();
    let operation = AgentChatProviderInstanceMutation::UpsertWithSecretRef {
        provider_instance_id: "work".into(),
        envelope: provider_envelope("work"),
        name: "API_KEY".into(),
        secret_ref: Some(opaque.clone()),
    };
    let receipt = settings_receipt("secret-save");
    let response = store
        .mutate_agent_chat_provider_instances(0, &operation, &receipt)
        .await
        .unwrap();
    assert!(
        matches!(&response, AgentChatSettingsOutcome::Applied(value) if value["instances"][0]["environment"][0]["secretSaved"] == true)
    );
    let stored = store.agent_chat_provider_instances().await.unwrap();
    assert_eq!(stored.instances[0].secret_refs["API_KEY"], opaque);
    let safe = agent_chat_provider_instances_response(&stored);
    assert!(!safe.to_string().contains(&opaque));
    assert!(safe["instances"][0]["environment"][0]
        .get("value")
        .is_none());
    let receipt_json: String = sqlx::query_scalar(
        "SELECT receiptJson FROM agentChatReceipts WHERE requestId = 'secret-save'",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert!(!receipt_json.contains(&opaque));
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened.agent_chat_provider_instances().await.unwrap(),
        stored
    );
    let replay = store
        .mutate_agent_chat_provider_instances(0, &operation, &receipt)
        .await
        .unwrap();
    assert_eq!(replay, AgentChatSettingsOutcome::Replay(safe));
    let mut plaintext = provider_envelope("bad");
    plaintext["environment"][0]["value"] = json!("do-not-save-this");
    assert!(store
        .mutate_agent_chat_provider_instances(
            1,
            &AgentChatProviderInstanceMutation::Upsert {
                provider_instance_id: "bad".into(),
                envelope: plaintext
            },
            &settings_receipt("plaintext")
        )
        .await
        .is_err());
    let mut options = provider_envelope("bad");
    options["options"] = json!({"nested": {"apiKey": "do-not-save-this"}});
    assert!(store
        .mutate_agent_chat_provider_instances(
            1,
            &AgentChatProviderInstanceMutation::Upsert {
                provider_instance_id: "bad".into(),
                envelope: options
            },
            &settings_receipt("plaintext-options")
        )
        .await
        .is_err());
    assert_eq!(
        store
            .agent_chat_provider_instances()
            .await
            .unwrap()
            .revision,
        1
    );
}

#[tokio::test]
async fn import_is_atomic_and_never_overwrites_a_previously_edited_domain() {
    let (_dir, store) = store().await;
    let records: Vec<_> = ["one", "two"]
        .into_iter()
        .map(|id| AgentChatProviderInstanceRecord {
            provider_instance_id: id.into(),
            envelope: provider_envelope(id),
            secret_refs: BTreeMap::from([("API_KEY".into(), uuid::Uuid::new_v4().to_string())]),
            revision: 0,
        })
        .collect();
    sqlx::query("CREATE TRIGGER rejectSecondProvider BEFORE INSERT ON agentChatProviderInstances WHEN NEW.providerInstanceId = 'two' BEGIN SELECT RAISE(ABORT, 'second provider failed'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .import_agent_chat_provider_instances_if_empty(&records)
        .await
        .is_err());
    assert!(store
        .agent_chat_provider_instances()
        .await
        .unwrap()
        .instances
        .is_empty());
    assert_eq!(
        store
            .agent_chat_provider_instances()
            .await
            .unwrap()
            .revision,
        0
    );
    sqlx::query("DROP TRIGGER rejectSecondProvider")
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .import_agent_chat_provider_instances_if_empty(&records)
        .await
        .unwrap());
    assert_eq!(
        store
            .agent_chat_provider_instances()
            .await
            .unwrap()
            .instances
            .len(),
        2
    );
    assert!(!store
        .import_agent_chat_provider_instances_if_empty(&records)
        .await
        .unwrap());
    for (revision, id) in [(1, "one"), (2, "two")] {
        store
            .mutate_agent_chat_provider_instances(
                revision,
                &AgentChatProviderInstanceMutation::Remove {
                    provider_instance_id: id.into(),
                },
                &settings_receipt(id),
            )
            .await
            .unwrap();
    }
    assert!(store
        .agent_chat_provider_instances()
        .await
        .unwrap()
        .instances
        .is_empty());
    assert!(!store
        .import_agent_chat_provider_instances_if_empty(&records)
        .await
        .unwrap());
}

#[tokio::test]
async fn a_reopen_leaves_an_existing_reader_able_to_become_a_writer() {
    let (dir, store) = store().await;
    store
        .update_agent_chat_preferences(
            0,
            &[edit(
                "defaultSelection",
                None,
                json!({"providerInstanceId": "codex"}),
            )],
            &settings_receipt("initial"),
        )
        .await
        .unwrap();
    let mut transaction = store.pool().begin().await.unwrap();
    let _: i64 = sqlx::query_scalar(
        "SELECT revision FROM agentChatSettingsRevisions WHERE domain = 'preferences'",
    )
    .fetch_one(&mut *transaction)
    .await
    .unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    reopened.pool().close().await;
    sqlx::query("UPDATE agentChatSettingsRevisions SET revision = revision + 1 WHERE domain = 'preferences'")
        .execute(&mut *transaction).await.unwrap();
    transaction.commit().await.unwrap();
    assert_eq!(store.agent_chat_preferences().await.unwrap()["revision"], 2);
}

#[tokio::test]
async fn concurrent_secret_reference_edits_keep_only_the_receipted_revision_winner() {
    let (dir, store) = store().await;
    let upsert = AgentChatProviderInstanceMutation::Upsert {
        provider_instance_id: "work".into(),
        envelope: provider_envelope("work"),
    };
    store
        .mutate_agent_chat_provider_instances(0, &upsert, &settings_receipt("upsert"))
        .await
        .unwrap();
    let phone = RuntimeStore::open(dir.path()).await.unwrap();
    let desktop_ref = uuid::Uuid::new_v4().to_string();
    let phone_ref = uuid::Uuid::new_v4().to_string();
    let desktop = AgentChatProviderInstanceMutation::SetSecretRef {
        provider_instance_id: "work".into(),
        name: "API_KEY".into(),
        secret_ref: Some(desktop_ref.clone()),
    };
    let mobile = AgentChatProviderInstanceMutation::SetSecretRef {
        provider_instance_id: "work".into(),
        name: "API_KEY".into(),
        secret_ref: Some(phone_ref.clone()),
    };
    let desktop_receipt = settings_receipt("desktop-secret");
    let phone_receipt = settings_receipt("phone-secret");
    let (desktop, mobile) = tokio::join!(
        store.mutate_agent_chat_provider_instances(1, &desktop, &desktop_receipt),
        phone.mutate_agent_chat_provider_instances(1, &mobile, &phone_receipt),
    );
    let desktop = desktop.unwrap();
    let mobile = mobile.unwrap();
    let winning_ref = match (&desktop, &mobile) {
        (
            AgentChatSettingsOutcome::Applied(_),
            AgentChatSettingsOutcome::RevisionConflict { revision: 2 },
        ) => desktop_ref,
        (
            AgentChatSettingsOutcome::RevisionConflict { revision: 2 },
            AgentChatSettingsOutcome::Applied(_),
        ) => phone_ref,
        _ => panic!("expected exactly one reference edit winner"),
    };
    let stored = store.agent_chat_provider_instances().await.unwrap();
    assert_eq!(stored.revision, 2);
    assert_eq!(stored.instances[0].secret_refs["API_KEY"], winning_ref);
    let safe = agent_chat_provider_instances_response(&stored).to_string();
    assert!(!safe.contains(&winning_ref));
}
