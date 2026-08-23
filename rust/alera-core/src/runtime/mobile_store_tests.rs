use super::*;
use chrono::Utc;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn mobile_device(id: &str, token_hash: &str) -> MobileDevice {
    MobileDevice {
        id: id.to_string(),
        display_name: id.to_string(),
        token_hash: token_hash.to_string(),
        public_key_b64: None,
        permission: MobileDevicePermission::FullControl,
        paired_at: Utc::now(),
        last_seen_at: Some(Utc::now()),
        revoked_at: None,
    }
}

#[tokio::test]
async fn mobile_access_settings_roundtrip() {
    let (_dir, store) = store().await;
    let settings = store.mobile_access_settings().await.unwrap();
    assert!(!settings.enabled);
    assert_eq!(settings.port, 6768);

    let saved = store
        .set_mobile_access_settings(MobileAccessSettings {
            enabled: true,
            remote_access_enabled: true,
            bind_host: "127.0.0.1".to_string(),
            port: 7777,
            endpoint_mode: MobileEndpointMode::Tailscale,
            netbird_endpoint: MobileNetbirdEndpoint::default(),
            server_public_key_b64: Some("pub".to_string()),
            updated_at: Utc::now(),
        })
        .await
        .unwrap();

    assert!(saved.enabled);
    assert!(saved.remote_access_enabled);
    assert_eq!(saved.bind_host, "127.0.0.1");
    assert_eq!(saved.port, 7777);
    assert_eq!(saved.endpoint_mode, MobileEndpointMode::Tailscale);
    assert_eq!(saved.server_public_key_b64.as_deref(), Some("pub"));

    let reloaded = store.mobile_access_settings().await.unwrap();
    assert!(reloaded.remote_access_enabled);
    assert_eq!(reloaded.endpoint_mode, MobileEndpointMode::Tailscale);
}

#[tokio::test]
async fn mobile_access_settings_roundtrip_netbird_mode() {
    let (_dir, store) = store().await;
    let saved = store
        .set_mobile_access_settings(MobileAccessSettings {
            endpoint_mode: MobileEndpointMode::Netbird,
            netbird_endpoint: MobileNetbirdEndpoint::Dns,
            ..MobileAccessSettings::default()
        })
        .await
        .unwrap();

    assert_eq!(saved.endpoint_mode, MobileEndpointMode::Netbird);
    assert_eq!(saved.netbird_endpoint, MobileNetbirdEndpoint::Dns);
    assert_eq!(
        store.mobile_access_settings().await.unwrap().endpoint_mode,
        MobileEndpointMode::Netbird
    );
    assert_eq!(
        store
            .mobile_access_settings()
            .await
            .unwrap()
            .netbird_endpoint,
        MobileNetbirdEndpoint::Dns
    );
}

#[tokio::test]
async fn mobile_endpoint_mode_column_is_added_to_legacy_runtime_databases() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(RUNTIME_DATABASE_FILE_NAME);
    let pool = SqlitePoolOptions::new()
        .connect_with(
            SqliteConnectOptions::new()
                .filename(path)
                .create_if_missing(true),
        )
        .await
        .unwrap();
    sqlx::query(
        "CREATE TABLE mobileAccessSettings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            enabled INTEGER NOT NULL DEFAULT 0,
            bindHost TEXT NOT NULL,
            port INTEGER NOT NULL,
            serverPublicKeyB64 TEXT,
            updatedAt TEXT NOT NULL
        )",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO mobileAccessSettings (id, enabled, bindHost, port, updatedAt) \
         VALUES (1, 1, '127.0.0.1', 6768, '2026-01-01T00:00:00Z')",
    )
    .execute(&pool)
    .await
    .unwrap();
    pool.close().await;

    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let settings = store.mobile_access_settings().await.unwrap();
    assert!(settings.enabled);
    assert_eq!(settings.endpoint_mode, MobileEndpointMode::Loopback);
    assert_eq!(settings.netbird_endpoint, MobileNetbirdEndpoint::Ip);
}

#[tokio::test]
async fn mobile_pairing_offers_only_list_active_unclaimed_entries() {
    let (_dir, store) = store().await;
    let now = Utc::now();
    store
        .upsert_mobile_pairing_offer(MobilePairingOffer {
            id: "active".to_string(),
            endpoint: "ws://localhost:6768".to_string(),
            secret_hash: "hash".to_string(),
            expected_device_name: None,
            server_public_key_b64: None,
            created_at: now,
            expires_at: now + chrono::Duration::minutes(10),
            claimed_device_id: None,
        })
        .await
        .unwrap();
    store
        .upsert_mobile_pairing_offer(MobilePairingOffer {
            id: "expired".to_string(),
            endpoint: "ws://localhost:6768".to_string(),
            secret_hash: "hash".to_string(),
            expected_device_name: None,
            server_public_key_b64: None,
            created_at: now,
            expires_at: now - chrono::Duration::minutes(1),
            claimed_device_id: None,
        })
        .await
        .unwrap();

    let offers = store.list_mobile_pairing_offers().await.unwrap();
    assert_eq!(offers.len(), 1);
    assert_eq!(offers[0].id, "active");
}

#[tokio::test]
async fn mobile_pairing_offer_claim_is_single_use() {
    let (_dir, store) = store().await;
    let now = Utc::now();
    store
        .upsert_mobile_pairing_offer(MobilePairingOffer {
            id: "offer".to_string(),
            endpoint: "ws://localhost:6768".to_string(),
            secret_hash: "secret-hash".to_string(),
            expected_device_name: None,
            server_public_key_b64: None,
            created_at: now,
            expires_at: now + chrono::Duration::minutes(10),
            claimed_device_id: None,
        })
        .await
        .unwrap();

    let claimed = store
        .claim_mobile_pairing_offer("offer", "secret-hash", mobile_device("phone-1", "token-1"))
        .await
        .unwrap();
    assert_eq!(claimed.id, "phone-1");

    let error = store
        .claim_mobile_pairing_offer("offer", "secret-hash", mobile_device("phone-2", "token-2"))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("already claimed"));
    assert!(store.find_mobile_device("phone-2").await.unwrap().is_none());
    let offer = store
        .find_mobile_pairing_offer("offer")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(offer.claimed_device_id.as_deref(), Some("phone-1"));
}

#[tokio::test]
async fn mobile_pairing_offer_delete_only_removes_unclaimed_entries() {
    let (_dir, store) = store().await;
    let now = Utc::now();
    store
        .upsert_mobile_pairing_offer(MobilePairingOffer {
            id: "open".to_string(),
            endpoint: "ws://localhost:6768".to_string(),
            secret_hash: "hash".to_string(),
            expected_device_name: None,
            server_public_key_b64: None,
            created_at: now,
            expires_at: now + chrono::Duration::minutes(10),
            claimed_device_id: None,
        })
        .await
        .unwrap();
    store
        .upsert_mobile_pairing_offer(MobilePairingOffer {
            id: "claimed".to_string(),
            endpoint: "ws://localhost:6768".to_string(),
            secret_hash: "hash".to_string(),
            expected_device_name: None,
            server_public_key_b64: None,
            created_at: now,
            expires_at: now + chrono::Duration::minutes(10),
            claimed_device_id: Some("phone".to_string()),
        })
        .await
        .unwrap();

    assert!(store.delete_mobile_pairing_offer("open").await.unwrap());
    assert!(store
        .find_mobile_pairing_offer("open")
        .await
        .unwrap()
        .is_none());
    assert!(!store.delete_mobile_pairing_offer("missing").await.unwrap());
    assert!(!store.delete_mobile_pairing_offer("claimed").await.unwrap());
    assert!(store
        .find_mobile_pairing_offer("claimed")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn mobile_device_rename_skips_revoked_and_unknown_devices() {
    let (_dir, store) = store().await;
    store
        .upsert_mobile_device(mobile_device("phone", "hash"))
        .await
        .unwrap();

    let renamed = store
        .rename_mobile_device("phone", "Leynier's Phone")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(renamed.display_name, "Leynier's Phone");

    assert!(store
        .rename_mobile_device("missing", "Name")
        .await
        .unwrap()
        .is_none());

    store.revoke_mobile_device("phone").await.unwrap();
    assert!(store
        .rename_mobile_device("phone", "Other")
        .await
        .unwrap()
        .is_none());
    let stored = store.find_mobile_device("phone").await.unwrap().unwrap();
    assert_eq!(stored.display_name, "Leynier's Phone");
}

#[tokio::test]
async fn mobile_devices_can_be_revoked() {
    let (_dir, store) = store().await;
    store
        .upsert_mobile_device(mobile_device("phone", "hash"))
        .await
        .unwrap();

    assert_eq!(store.list_mobile_devices(false).await.unwrap().len(), 1);
    store.revoke_mobile_device("phone").await.unwrap();
    assert!(store.list_mobile_devices(false).await.unwrap().is_empty());
    assert_eq!(store.list_mobile_devices(true).await.unwrap().len(), 1);
}

#[tokio::test]
async fn mobile_devices_can_be_deleted_only_when_revoked() {
    let (_dir, store) = store().await;
    store
        .upsert_mobile_device(mobile_device("phone", "hash"))
        .await
        .unwrap();

    assert!(!store.delete_mobile_device("phone").await.unwrap());
    assert_eq!(store.list_mobile_devices(true).await.unwrap().len(), 1);

    store.revoke_mobile_device("phone").await.unwrap();
    assert!(store.delete_mobile_device("phone").await.unwrap());
    assert!(store.list_mobile_devices(true).await.unwrap().is_empty());
    assert!(!store.delete_mobile_device("phone").await.unwrap());
}

#[tokio::test]
async fn mobile_device_seen_update_does_not_revive_revoked_device() {
    let (_dir, store) = store().await;
    let mut stale = store
        .upsert_mobile_device(mobile_device("phone", "hash"))
        .await
        .unwrap();
    store.revoke_mobile_device("phone").await.unwrap();

    stale.last_seen_at = Some(Utc::now());
    store.upsert_mobile_device(stale).await.unwrap();
    let stored = store.find_mobile_device("phone").await.unwrap().unwrap();
    assert!(stored.revoked_at.is_some());

    let active = store
        .mark_mobile_device_seen_if_active("phone", Utc::now())
        .await
        .unwrap();
    assert!(active.is_none());
    assert!(store.list_mobile_devices(false).await.unwrap().is_empty());
}
