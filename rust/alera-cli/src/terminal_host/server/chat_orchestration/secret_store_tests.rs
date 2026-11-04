use std::sync::Arc;
use std::time::Duration;

use super::secret_store::{SecretDelivery, SecretVault, REF_EXPIRED};
use super::test_support::MemorySecrets;

const VALUE: &str = "synthetic-test-value-0042";

fn vault(directory: &std::path::Path, ttl: Duration) -> SecretVault {
    SecretVault::new(
        Arc::new(MemorySecrets::default()),
        directory.join("secrets"),
    )
    .with_ttl(ttl)
}

#[tokio::test]
async fn a_ref_is_spent_by_its_own_chat_only_once() {
    let directory = tempfile::tempdir().unwrap();
    let vault = vault(directory.path(), Duration::from_secs(60));
    let saved = vault
        .deliver("chat-a", SecretDelivery::Ref, VALUE)
        .await
        .unwrap();
    let secret_ref = saved["secretRef"].as_str().unwrap();
    assert!(vault.consume(secret_ref, Some("chat-b")).await.is_err());
    assert!(vault.consume(secret_ref, Some("chat-a")).await.unwrap() == VALUE);
    assert!(vault.consume(secret_ref, Some("chat-a")).await.is_err());
    assert!(vault.consume("secret-ref:nothex", None).await.is_err());
}

#[tokio::test]
async fn expired_refs_and_files_are_refused_and_swept() {
    let directory = tempfile::tempdir().unwrap();
    let vault = vault(directory.path(), Duration::ZERO);
    let saved = vault
        .deliver("chat-a", SecretDelivery::Ref, VALUE)
        .await
        .unwrap();
    let error = vault
        .consume(saved["secretRef"].as_str().unwrap(), Some("chat-a"))
        .await
        .unwrap_err();
    assert!(error.wire_message().contains(REF_EXPIRED));

    let saved = vault
        .deliver("chat-a", SecretDelivery::Ref, VALUE)
        .await
        .unwrap();
    let file = vault
        .deliver("chat-a", SecretDelivery::File, VALUE)
        .await
        .unwrap();
    let file = std::path::PathBuf::from(file["file"].as_str().unwrap());
    assert!(file.exists());
    vault.sweep().await;
    assert!(!file.exists());
    let refs = directory.path().join("secrets").join("refs");
    assert_eq!(std::fs::read_dir(refs).unwrap().count(), 0);
    assert!(vault
        .consume(saved["secretRef"].as_str().unwrap(), None)
        .await
        .is_err());
}

#[tokio::test]
async fn a_live_file_survives_a_sweep() {
    let directory = tempfile::tempdir().unwrap();
    let vault = vault(directory.path(), Duration::from_secs(60));
    let file = vault
        .deliver("chat-a", SecretDelivery::File, VALUE)
        .await
        .unwrap();
    vault.sweep().await;
    assert!(std::path::Path::new(file["file"].as_str().unwrap()).exists());
    assert!(SecretDelivery::parse(None).unwrap() == SecretDelivery::File);
    assert!(SecretDelivery::parse(Some("env")).is_err());
}
