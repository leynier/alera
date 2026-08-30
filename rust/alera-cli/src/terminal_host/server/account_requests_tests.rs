use std::collections::HashMap;

use crate::terminal_host::client::ClientHandle;

use super::actor_test_harness::{mobile_client, test_actor};

#[tokio::test]
async fn authoritative_subscription_sync_updates_lifecycle_and_waiter() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut out_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(7, mobile_client(handle, "phone"))]),
        HashMap::new(),
    )
    .await;
    actor.account_push.push_enabled = true;
    actor.account_push.subscription_sync_in_flight = true;
    actor.account_push.subscription_sync_waiters.push((7, 42));
    actor.account_push.cloud_jobs = 1;

    actor.handle_push_subscription_sync_finished(Ok(3));

    assert_eq!(actor.account_push.active_subscriptions, 3);
    assert!(!actor.account_push.subscription_sync_in_flight);
    assert_eq!(actor.account_push.cloud_jobs, 0);
    assert!(actor.account_push.subscription_sync_waiters.is_empty());
    let response = out_rx
        .try_recv()
        .expect("subscription sync response")
        .as_json()
        .expect("JSON response");
    assert_eq!(response["id"], 42);
    assert_eq!(response["payload"]["activeSubscriptions"], 3);
}

#[tokio::test]
async fn disabled_runtime_does_not_retain_authoritative_subscriptions() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.account_push.push_enabled = false;
    actor.account_push.subscription_sync_in_flight = true;
    actor.account_push.cloud_jobs = 1;

    actor.handle_push_subscription_sync_finished(Ok(2));

    assert_eq!(actor.account_push.active_subscriptions, 0);
    assert!(!actor.account_push.subscription_sync_in_flight);
    assert_eq!(actor.account_push.cloud_jobs, 0);
}

#[tokio::test]
async fn configuration_mobile_surface_never_exposes_cloud_credentials_or_settings_seeding() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut out_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(7, mobile_client(handle, "phone"))]),
        HashMap::new(),
    )
    .await;
    for (id, request) in [
        "configuration.cloud.head",
        "configuration.cloud.publish",
        "configuration.settings.seed",
    ]
    .iter()
    .enumerate()
    {
        actor
            .handle_line(
                7,
                serde_json::json!({"id": id, "type": request, "payload": {"accountId": "a"}})
                    .to_string(),
            )
            .await;
        let response = out_rx.try_recv().unwrap().as_json().unwrap();
        assert!(response.get("error").is_some(), "{request}: {response}");
    }
    assert_eq!(actor.account_push.cloud_jobs, 0);
    assert!(actor
        .runtime_store
        .configuration_snapshot("a")
        .await
        .is_err());
}

#[tokio::test]
async fn configuration_transfer_keeps_cas_and_account_checks_at_commit() {
    use base64::{engine::general_purpose::STANDARD, Engine};
    use chrono::Utc;
    use serde_json::{json, Value};
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor
        .runtime_store
        .set_alera_account(&alera_core::runtime::LocalAleraAccount {
            account_id: "a".into(),
            email: "a@example.test".into(),
            providers: vec![],
            runtime_id: "host".into(),
            cloud_base_url: "https://example.test".into(),
            signed_in_at: Utc::now(),
            access_token_expires_at: Utc::now(),
            push_subscription_count: 0,
        })
        .await
        .unwrap();
    let before = actor
        .runtime_store
        .configuration_snapshot("a")
        .await
        .unwrap();
    let mut document = before["document"].clone();
    document["desktop"]["settings"]["terminal"] = json!({"fontSize":20});
    let payload = json!({"accountId":"a","expectedFingerprint":before["fingerprint"],"document":document,"base":null,"pending":null});
    let bytes = serde_json::to_vec(&payload).unwrap();
    for change_account in [false, true] {
        let start = actor
            .handle_configuration_request(
                7,
                "configuration.transfer.start",
                &json!({"accountId":"a","action":"apply","size":bytes.len()}),
            )
            .await
            .unwrap();
        let id = &start["transferId"];
        actor
            .handle_configuration_request(
                7,
                "configuration.transfer.chunk",
                &json!({"accountId":"a","transferId":id,"offset":0,"data":STANDARD.encode(&bytes)}),
            )
            .await
            .unwrap();
        if !change_account {
            assert_eq!(
                actor
                    .runtime_store
                    .configuration_snapshot("a")
                    .await
                    .unwrap()["document"],
                before["document"]
            );
        }
        if change_account {
            actor.runtime_store.clear_alera_account().await.unwrap();
        } else {
            actor
                .runtime_store
                .configuration_update_settings(json!({"terminal":{"fontSize":18}}))
                .await
                .unwrap();
        }
        let result = actor
            .handle_configuration_request(
                7,
                "configuration.transfer.commit",
                &json!({"accountId":"a","transferId":id}),
            )
            .await;
        assert!(result.is_err());
        assert!(actor
            .runtime_store
            .get_metadata("configuration.backup.a")
            .await
            .unwrap()
            .is_none());
    }
    assert_eq!(
        actor.runtime_store.configuration_settings().await.unwrap()["terminal"]["fontSize"],
        Value::from(18)
    );
}

#[tokio::test]
async fn configuration_import_validates_adapters_and_managed_launches_before_writing() {
    use base64::{engine::general_purpose::STANDARD, Engine};
    use chrono::Utc;
    use serde_json::json;
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor
        .runtime_store
        .set_alera_account(&alera_core::runtime::LocalAleraAccount {
            account_id: "a".into(),
            email: "a@example.test".into(),
            providers: vec![],
            runtime_id: "host".into(),
            cloud_base_url: "https://example.test".into(),
            signed_in_at: Utc::now(),
            access_token_expires_at: Utc::now(),
            push_subscription_count: 0,
        })
        .await
        .unwrap();
    let before = actor
        .runtime_store
        .configuration_snapshot("a")
        .await
        .unwrap();
    for via_transfer in [false, true] {
        for profile in [
            json!({"id":"one","name":"One","agentType":"codex","command":"codex","launchMode":"managed",
                "managedConfig":{"bypassApprovalsAndSandbox":true,"sandbox":"read-only"}}),
            json!({"id":"one","name":"One","agentType":"unsupported","command":"unknown"}),
        ] {
            let mut document = before["document"].clone();
            document["shared"]["agentProfiles"] = json!({"items":{"one":profile},"order":["one"]});
            document["desktop"]["settings"]["terminal"] = json!({"fontSize":20});
            let payload = json!({"accountId":"a","expectedFingerprint":before["fingerprint"],
                "document":document,"base":null,"pending":{"operationId":"pending"}});
            let result = if via_transfer {
                let bytes = serde_json::to_vec(&payload).unwrap();
                let start = actor
                    .handle_configuration_request(
                        7,
                        "configuration.transfer.start",
                        &json!({"accountId":"a","action":"apply","size":bytes.len()}),
                    )
                    .await
                    .unwrap();
                actor.handle_configuration_request(7,"configuration.transfer.chunk",
                    &json!({"accountId":"a","transferId":start["transferId"],"offset":0,"data":STANDARD.encode(&bytes)})).await.unwrap();
                actor
                    .handle_configuration_request(
                        7,
                        "configuration.transfer.commit",
                        &json!({"accountId":"a","transferId":start["transferId"]}),
                    )
                    .await
            } else {
                actor
                    .handle_configuration_request(7, "configuration.apply", &payload)
                    .await
            };
            assert!(result.is_err());
            assert_eq!(
                actor
                    .runtime_store
                    .configuration_snapshot("a")
                    .await
                    .unwrap(),
                before
            );
            assert!(actor
                .runtime_store
                .get_metadata("configuration.backup.a")
                .await
                .unwrap()
                .is_none());
        }
    }
}
