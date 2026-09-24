#[cfg(not(target_os = "linux"))]
pub(crate) use keyring::{Entry, Error, Result};
#[cfg(target_os = "linux")]
use keyring_core::api::CredentialStoreApi;
#[cfg(target_os = "linux")]
pub(crate) use keyring_core::{Entry, Error, Result};

pub(crate) fn native_credential_entry(service: &str, user: &str) -> Result<Entry> {
    // Keep the v3 native stores and service/user mapping. Construct on each
    // attempt so an unavailable keyring can recover without restarting Alera.
    #[cfg(target_os = "linux")]
    {
        // V3 scoped matching to this target, even when searching all collections.
        let modifiers = std::collections::HashMap::from([("target", "default")]);
        dbus_secret_service_keyring_store::Store::new()?.build(service, user, Some(&modifiers))
    }
    // Retain the existing backends until migration can be certified in an
    // interactive Keychain / Credential Manager session on those platforms.
    #[cfg(not(target_os = "linux"))]
    Entry::new(service, user)
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    #[ignore = "requires an isolated, unlocked Secret Service session"]
    fn default_target_ignores_unrelated_credentials() {
        assert_eq!(
            std::env::var("ALERA_KEYRING_TEST_DISPOSABLE").as_deref(),
            Ok("1"),
            "Run only with a private D-Bus session and disposable keyring data"
        );
        let user = format!(
            "{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let service = "dev.leynier.alera.keyring-compatibility-test";
        let store = dbus_secret_service_keyring_store::Store::new().unwrap();
        let modifiers = HashMap::from([("target", "default")]);
        let original = store.build(service, &user, Some(&modifiers)).unwrap();
        original.set_password("synthetic-original").unwrap();
        let other = store
            .build(service, &format!("{user}-other"), Some(&modifiers))
            .unwrap();
        other.set_password("synthetic-unrelated").unwrap();
        // Change only this synthetic item, without creating another collection.
        let other = other.get_credential().unwrap();
        other
            .update_attributes(&HashMap::from([
                ("username", user.as_str()),
                ("target", "unrelated"),
            ]))
            .unwrap();

        let result = (|| -> Result<()> {
            let entry = native_credential_entry(service, &user)?;
            assert_eq!(entry.get_password()?, "synthetic-original");
            entry.set_password("synthetic-updated")?;
            assert_eq!(original.get_password()?, "synthetic-updated");
            assert_eq!(other.get_password()?, "synthetic-unrelated");
            entry.delete_credential()?;
            assert!(matches!(original.get_password(), Err(Error::NoEntry)));
            assert_eq!(other.get_password()?, "synthetic-unrelated");
            Ok(())
        })();
        let _ = original.delete_credential();
        other.delete_credential().unwrap();
        result.unwrap();
    }
}
