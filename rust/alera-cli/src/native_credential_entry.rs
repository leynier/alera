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
        dbus_secret_service_keyring_store::Store::new()?.build(service, user, None)
    }
    // Retain the existing backends until migration can be certified in an
    // interactive Keychain / Credential Manager session on those platforms.
    #[cfg(not(target_os = "linux"))]
    Entry::new(service, user)
}
