use super::{AgentProfile, LocalAleraAccount, RuntimeStore};
use chrono::Utc;
use serde_json::{json, Value};

async fn fixture() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store
        .set_alera_account(&LocalAleraAccount {
            account_id: "a".into(),
            email: "a@example.test".into(),
            providers: vec![],
            runtime_id: "runtime".into(),
            cloud_base_url: "https://example.test".into(),
            signed_in_at: Utc::now(),
            access_token_expires_at: Utc::now(),
            push_subscription_count: 0,
        })
        .await
        .unwrap();
    store
        .configuration_seed(
            json!({"terminal": {"fontSize": 12}, "keyboard": {"overrides": {"copy": ["Mod+C"]}}}),
        )
        .await
        .unwrap();
    (dir, store)
}
fn profile(id: &str) -> AgentProfile {
    serde_json::from_value(
        json!({"id": id, "name": id, "agentType": "codex", "command": "codex",
        "createdAt": Utc::now(), "updatedAt": Utc::now()}),
    )
    .unwrap()
}
async fn apply(store: &RuntimeStore, snapshot: &Value, document: &Value) -> anyhow::Result<()> {
    store
        .configuration_apply(
            "a",
            snapshot["fingerprint"].as_str().unwrap(),
            document,
            &Value::Null,
            &Value::Null,
        )
        .await
}

#[tokio::test]
async fn configuration_migration_is_idempotent_and_preserves_local_settings() {
    let (_dir, store) = fixture().await;
    store
        .set_metadata("settings.agents.agentStatusHooks", "{\"codex\":true}")
        .await
        .unwrap();
    store
        .configuration_seed(json!({"terminal": {"fontSize": 99}}))
        .await
        .unwrap();
    let snapshot = store.configuration_snapshot("a").await.unwrap();
    assert_eq!(
        snapshot["document"]["desktop"]["settings"]["terminal"]["fontSize"],
        12
    );
    let mut next = snapshot["document"].clone();
    next["desktop"]["settings"]["terminal"]["fontSize"] = json!(18);
    apply(&store, &snapshot, &next).await.unwrap();
    assert!(store.agent_status_hook_settings().await.unwrap().codex);
    assert!(store
        .get_metadata("configuration.backup.a")
        .await
        .unwrap()
        .is_some());
    assert!(apply(&store, &snapshot, &next).await.is_err());
    assert!(store.configuration_snapshot("other").await.is_err());
}

#[tokio::test]
async fn configuration_settings_reset_removes_dictionary_overrides() {
    let (_dir, store) = fixture().await;
    store
        .configuration_update_settings(json!({"keyboard": {"overrides": {}}}))
        .await
        .unwrap();
    assert_eq!(
        store.configuration_settings().await.unwrap()["keyboard"]["overrides"],
        json!({})
    );
}

#[tokio::test]
async fn configuration_profile_deletion_is_atomic_and_keeps_referenced_profiles() {
    let (_dir, store) = fixture().await;
    store
        .upsert_agent_profile(profile("one"), None)
        .await
        .unwrap();
    let automation = super::agent_profile_removal_store_tests::automation("one");
    store
        .upsert_automation(automation.clone(), automation.created_by.clone())
        .await
        .unwrap();
    let snapshot = store.configuration_snapshot("a").await.unwrap();
    let mut next = snapshot["document"].clone();
    next["shared"]["agentProfiles"] = json!({"items": {}, "order": []});
    next["desktop"]["settings"]["terminal"]["fontSize"] = json!(42);
    assert!(apply(&store, &snapshot, &next).await.is_err());
    assert_eq!(
        store.configuration_snapshot("a").await.unwrap()["document"],
        snapshot["document"]
    );
}

#[tokio::test]
async fn configuration_preserves_unknown_fields_and_local_profile_revisions() {
    let (_dir, store) = fixture().await;
    store
        .upsert_agent_profile(profile("one"), None)
        .await
        .unwrap();
    let snapshot = store.configuration_snapshot("a").await.unwrap();
    let mut next = snapshot["document"].clone();
    next["shared"]["agentProfiles"]["items"]["one"]["futureSetting"] = json!("keep");
    next["mobile"] = json!({"futurePhonePreference": true});
    next["desktop"]["settings"]["futureSection"] = json!(["opaque"]);
    apply(&store, &snapshot, &next).await.unwrap();
    let final_snapshot = store.configuration_snapshot("a").await.unwrap();
    assert_eq!(
        final_snapshot["document"]["shared"]["agentProfiles"]["items"]["one"]["futureSetting"],
        "keep"
    );
    assert_eq!(final_snapshot["document"]["mobile"], next["mobile"]);
    assert_eq!(
        final_snapshot["document"]["desktop"]["settings"]["futureSection"],
        json!(["opaque"])
    );
    assert!(
        final_snapshot["document"]["shared"]["agentProfiles"]["items"]["one"]
            .get("revision")
            .is_none()
    );
    assert_eq!(
        store
            .find_agent_profile("one")
            .await
            .unwrap()
            .unwrap()
            .revision,
        1
    );
}

#[tokio::test]
async fn configuration_upload_completion_does_not_overwrite_new_local_edits() {
    let (_dir, store) = fixture().await;
    let snapshot = store.configuration_snapshot("a").await.unwrap();
    let pending = json!({"operationId": "op"});
    store
        .configuration_apply(
            "a",
            snapshot["fingerprint"].as_str().unwrap(),
            &snapshot["document"],
            &Value::Null,
            &pending,
        )
        .await
        .unwrap();
    assert!(
        apply(&store, &snapshot, &snapshot["document"])
            .await
            .is_err(),
        "Changing only pending state must invalidate another review"
    );
    store
        .configuration_update_settings(json!({"terminal": {"fontSize": 16}}))
        .await
        .unwrap();
    store
        .configuration_published(
            "a",
            "op",
            &json!({"revision": 1, "document": snapshot["document"]}),
        )
        .await
        .unwrap();
    let current = store.configuration_snapshot("a").await.unwrap();
    assert_eq!(
        current["document"]["desktop"]["settings"]["terminal"]["fontSize"],
        16
    );
    assert!(current["pending"].is_null());
}

#[tokio::test]
async fn configuration_rejects_invalid_actions_without_any_writes() {
    let (_dir, store) = fixture().await;
    let before = store.configuration_snapshot("a").await.unwrap();
    for bad in [
        json!({"id":"two","name":" SUMMARIZE ","prompt":"valid"}),
        json!({"id":"two","name":"Other","prompt":" "}),
        json!({"id":"two","name":"Other","prompt":"valid","agentOverride":"unknown"}),
    ] {
        let mut next = before["document"].clone();
        next["shared"]["textActions"] = json!({"items": {"one":{"id":"one","name":"Summarize","prompt":"valid"},"two":bad},"order":["one","two"]});
        next["desktop"]["settings"]["terminal"]["fontSize"] = json!(20);
        assert!(apply(&store, &before, &next).await.is_err());
        assert_eq!(store.configuration_snapshot("a").await.unwrap(), before);
        assert!(store
            .get_metadata("configuration.backup.a")
            .await
            .unwrap()
            .is_none());
    }
}

#[tokio::test]
async fn configuration_restoration_removes_stale_native_values() {
    let (_dir, store) = fixture().await;
    store.set_confirm_project_removal(false).await.unwrap();
    store.set_confirm_workspace_removal(false).await.unwrap();
    let before = store.configuration_snapshot("a").await.unwrap();
    let mut next = before["document"].clone();
    next["desktop"]["settings"] = json!({});
    apply(&store, &before, &next).await.unwrap();
    assert!(store.confirm_project_removal().await.unwrap());
    assert!(store.confirm_workspace_removal().await.unwrap());
    assert!(store
        .configuration_settings()
        .await
        .unwrap()
        .get("terminal")
        .is_none());
}

#[tokio::test]
async fn configuration_preserves_catalog_and_action_metadata_after_normal_edits() {
    let (_dir, store) = fixture().await;
    let before = store.configuration_snapshot("a").await.unwrap();
    let mut next = before["document"].clone();
    next["shared"]["agentProfiles"]["futureCatalogField"] = json!({"keep":true});
    next["shared"]["textActions"] = json!({"futureCatalogField":[42],"items":{"one":{"id":"one","name":"Summarize","prompt":"valid","futureActionField":true}},"order":["one"]});
    apply(&store, &before, &next).await.unwrap();
    let mut actions = store.text_actions_settings().await.unwrap().unwrap();
    actions.actions[0].name = "New name".into();
    store.set_text_actions_settings(actions).await.unwrap();
    let after = store.configuration_snapshot("a").await.unwrap();
    assert_eq!(
        after["document"]["shared"]["agentProfiles"]["futureCatalogField"],
        json!({"keep":true})
    );
    assert_eq!(
        after["document"]["shared"]["textActions"]["futureCatalogField"],
        json!([42])
    );
    assert_eq!(
        after["document"]["shared"]["textActions"]["items"]["one"]["futureActionField"],
        true
    );
    assert_eq!(
        after["document"]["shared"]["textActions"]["items"]["one"]["name"],
        "New name"
    );
}

#[tokio::test]
async fn configuration_keyboard_edits_preserve_future_actions_and_reset_known_actions() {
    let (_dir, store) = fixture().await;
    store.configuration_update_settings(json!({"keyboard":{"overrides":{"openSettings":["Mod+Comma"],"futureAction":["Mod+F12"]}}})).await.unwrap();
    store
        .configuration_update_settings_for_client(
            json!({"keyboard":{"overrides":{}}}),
            Some(&["openSettings".into()]),
        )
        .await
        .unwrap();
    assert_eq!(
        store.configuration_settings().await.unwrap()["keyboard"]["overrides"],
        json!({"futureAction":["Mod+F12"]})
    );
}

#[tokio::test]
async fn configuration_native_edits_preserve_opaque_ai_fields() {
    let (_dir, store) = fixture().await;
    let before = store.configuration_snapshot("a").await.unwrap();
    let mut next = before["document"].clone();
    next["desktop"]["settings"]["aiTextGeneration"] = json!({"futureAi":42,"promptSettingsByOperation":{"commitMessage":{"agent":"codex","futurePrompt":true}}});
    apply(&store, &before, &next).await.unwrap();
    let mut ai = store.ai_assist_settings().await.unwrap().unwrap();
    ai.enabled = false;
    store.set_ai_assist_settings(ai).await.unwrap();
    let after = store.configuration_snapshot("a").await.unwrap();
    assert_eq!(
        after["document"]["desktop"]["settings"]["aiTextGeneration"]["futureAi"],
        42
    );
    assert_eq!(
        after["document"]["desktop"]["settings"]["aiTextGeneration"]["enabled"],
        false
    );
    assert_eq!(
        after["document"]["desktop"]["settings"]["aiTextGeneration"]["promptSettingsByOperation"]
            ["commitMessage"]["futurePrompt"],
        true
    );
}

#[tokio::test]
async fn configuration_absent_catalogs_remove_entries_but_not_referenced_profiles() {
    for referenced in [false, true] {
        let (_dir, store) = fixture().await;
        store
            .upsert_agent_profile(profile("one"), None)
            .await
            .unwrap();
        if referenced {
            let automation = super::agent_profile_removal_store_tests::automation("one");
            store
                .upsert_automation(automation.clone(), automation.created_by.clone())
                .await
                .unwrap();
        }
        store
            .set_text_actions_settings(
                serde_json::from_value(
                    json!({"actions":[{"id":"one","name":"One","prompt":"Text"}]}),
                )
                .unwrap(),
            )
            .await
            .unwrap();
        let before = store.configuration_snapshot("a").await.unwrap();
        let mut next = before["document"].clone();
        next["shared"] = json!({});
        let result = apply(&store, &before, &next).await;
        if referenced {
            assert!(result.is_err());
            assert_eq!(store.configuration_snapshot("a").await.unwrap(), before);
        } else {
            result.unwrap();
            assert!(store.find_agent_profile("one").await.unwrap().is_none());
            assert!(store
                .text_actions_settings()
                .await
                .unwrap()
                .unwrap()
                .actions
                .is_empty());
        }
    }
}

#[tokio::test]
async fn configuration_rejects_invalid_ai_assist_without_any_writes() {
    let (_dir, store) = fixture().await;
    let before = store.configuration_snapshot("a").await.unwrap();
    for ai in [
        json!({"agent":"custom","customCommand":"","timeoutSeconds":120}),
        json!({"agent":"codex","customCommand":"","timeoutSeconds":120,"promptSettingsByOperation":{"commitMessage":{"agent":"custom"}}}),
        json!({"agent":"codex","customCommand":"","timeoutSeconds":601}),
    ] {
        let mut next = before["document"].clone();
        next["desktop"]["settings"]["aiTextGeneration"] = ai;
        next["desktop"]["settings"]["terminal"]["fontSize"] = json!(20);
        assert!(apply(&store, &before, &next).await.is_err());
        assert_eq!(store.configuration_snapshot("a").await.unwrap(), before);
        assert!(store
            .get_metadata("configuration.backup.a")
            .await
            .unwrap()
            .is_none());
    }
}

#[tokio::test]
async fn configuration_settings_edits_preserve_nested_opaque_fields() {
    let (_dir, store) = fixture().await;
    let before = store.configuration_snapshot("a").await.unwrap();
    let mut next = before["document"].clone();
    next["desktop"]["settings"]["terminal"]["colorOverrides"] =
        json!({"foreground":"#ffffff","futureColor":true});
    next["desktop"]["settings"]["aiTextGeneration"] = json!({"agent":"codex","customCommand":"","timeoutSeconds":120,"promptSettingsByOperation":{"commitMessage":{"agent":"codex","futurePrompt":true}}});
    apply(&store, &before, &next).await.unwrap();
    store.configuration_update_settings(json!({
        "general":{"showTrayIcon":false},
        "terminal":{"colorOverrides":{"foreground":null,"background":null,"cursor":null,"selection":null}},
        "aiTextGeneration":{"agent":"codex","customCommand":"","timeoutSeconds":120,"promptSettingsByOperation":{"commitMessage":{"agent":null,"model":null}}}
    })).await.unwrap();
    let after = store.configuration_snapshot("a").await.unwrap();
    let color = &after["document"]["desktop"]["settings"]["terminal"]["colorOverrides"];
    assert_eq!(color["futureColor"], true);
    assert!(color["foreground"].is_null());
    let prompt = &after["document"]["desktop"]["settings"]["aiTextGeneration"]
        ["promptSettingsByOperation"]["commitMessage"];
    assert_eq!(prompt["futurePrompt"], true);
    assert!(prompt["agent"].is_null());
}

#[tokio::test]
async fn configuration_settings_reject_invalid_edits_before_native_persistence() {
    let (_dir, store) = fixture().await;
    store.configuration_update_settings(json!({
        "aiTextGeneration":{"agent":"custom","customCommand":"llm {prompt}","timeoutSeconds":120}
    })).await.unwrap();
    let before = store.configuration_snapshot("a").await.unwrap();
    let native = store
        .get_metadata("settings.aiTextGeneration")
        .await
        .unwrap();
    for ai in [
        json!({"agent":"custom","customCommand":"","timeoutSeconds":120}),
        json!({"agent":"codex","customCommand":"","timeoutSeconds":601}),
    ] {
        assert!(store
            .configuration_update_settings(json!({
                "terminal":{"fontSize":22},"aiTextGeneration":ai
            }))
            .await
            .is_err());
        assert_eq!(store.configuration_snapshot("a").await.unwrap(), before);
        assert_eq!(
            store
                .get_metadata("settings.aiTextGeneration")
                .await
                .unwrap(),
            native
        );
    }
}

#[tokio::test]
async fn configuration_cloud_size_limit_does_not_block_local_settings_or_catalog_deletion() {
    let (_dir, store) = fixture().await;
    store
        .set_text_actions_settings(
            serde_json::from_value(json!({"actions":[
                {"id":"one","name":"One","prompt":"x".repeat(270_000)},
                {"id":"two","name":"Two","prompt":"y".repeat(270_000)}
            ]}))
            .unwrap(),
        )
        .await
        .unwrap();
    let before = store.configuration_snapshot("a").await.unwrap();
    assert!(apply(&store, &before, &before["document"]).await.is_err());
    store.clear_alera_account().await.unwrap();
    store
        .configuration_update_settings(json!({"terminal":{"fontSize":20}}))
        .await
        .unwrap();
    assert_eq!(
        store.configuration_settings().await.unwrap()["terminal"]["fontSize"],
        20
    );
    store
        .set_text_actions_settings(serde_json::from_value(json!({"actions":[]})).unwrap())
        .await
        .unwrap();
    store
        .configuration_update_settings(json!({"terminal":{"fontSize":13}}))
        .await
        .unwrap();
    assert!(store
        .text_actions_settings()
        .await
        .unwrap()
        .unwrap()
        .actions
        .is_empty());
}
