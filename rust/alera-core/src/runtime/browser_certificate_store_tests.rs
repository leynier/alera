use chrono::{Duration, Utc};

use super::{BrowserProfile, BrowserTrustedCertificate, RuntimeStore};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn profile(id: &str, name: &str) -> BrowserProfile {
    let now = Utc::now();
    BrowserProfile {
        id: id.to_string(),
        name: name.to_string(),
        persistent: true,
        is_default: false,
        source: None,
        created_at: now,
        updated_at: now,
    }
}

#[tokio::test]
async fn trusted_certificates_are_exact_and_removed_with_the_profile() {
    let (_dir, store) = store().await;
    store
        .upsert_browser_profile(profile("work", "Work"))
        .await
        .unwrap();
    let now = Utc::now();
    let trusted = store
        .trust_browser_certificate(BrowserTrustedCertificate {
            profile_id: "work".to_string(),
            host: " [LOCALHOST.] ".to_string(),
            fingerprint_sha256: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                .to_string(),
            subject: Some(" Local Service ".to_string()),
            issuer: Some(" Development CA ".to_string()),
            valid_from: Some(now - Duration::minutes(1)),
            valid_to: Some(now + Duration::days(30)),
            created_at: now,
            last_used_at: now,
        })
        .await
        .unwrap();

    assert_eq!(trusted.host, "localhost");
    assert_eq!(
        trusted.fingerprint_sha256,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    );
    assert_eq!(trusted.subject.as_deref(), Some("Local Service"));
    assert_eq!(
        store
            .list_browser_trusted_certificates(Some("work"))
            .await
            .unwrap(),
        vec![trusted]
    );

    assert!(store.remove_browser_profile("work").await.unwrap());
    assert!(store
        .list_browser_trusted_certificates(None)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn ephemeral_profiles_and_invalid_fingerprints_cannot_persist_trust() {
    let (_dir, store) = store().await;
    let mut ephemeral = profile("temporary", "Temporary");
    ephemeral.persistent = false;
    store.upsert_browser_profile(ephemeral).await.unwrap();
    let now = Utc::now();
    let certificate = BrowserTrustedCertificate {
        profile_id: "temporary".to_string(),
        host: "localhost".to_string(),
        fingerprint_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            .to_string(),
        subject: None,
        issuer: None,
        valid_from: None,
        valid_to: None,
        created_at: now,
        last_used_at: now,
    };
    assert!(store
        .trust_browser_certificate(certificate.clone())
        .await
        .is_err());

    let invalid = BrowserTrustedCertificate {
        profile_id: "temporary".to_string(),
        fingerprint_sha256: "short".to_string(),
        ..certificate
    };
    assert!(store.trust_browser_certificate(invalid).await.is_err());
}
