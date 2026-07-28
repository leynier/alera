use chrono::{Duration, Utc};

use super::*;

#[tokio::test]
async fn local_account_roundtrips_without_credentials() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let account = LocalAleraAccount {
        account_id: "account-1".to_string(),
        email: "person@example.com".to_string(),
        providers: vec!["google".to_string(), "github".to_string()],
        runtime_id: "runtime-1".to_string(),
        cloud_base_url: "https://api.alera.build".to_string(),
        signed_in_at: Utc::now(),
        access_token_expires_at: Utc::now() + Duration::minutes(15),
        push_subscription_count: 2,
    };

    store.set_alera_account(&account).await.unwrap();
    let saved = store.alera_account().await.unwrap().unwrap();

    assert_eq!(saved.account_id, account.account_id);
    assert_eq!(saved.providers, account.providers);
    assert_eq!(saved.push_subscription_count, 2);
    store.clear_alera_account().await.unwrap();
    assert!(store.alera_account().await.unwrap().is_none());
}
