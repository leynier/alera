//! Standard Webhooks signing secrets: validation, generation, signing, and encryption at rest.

use aws_lc_rs::aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_256_GCM, NONCE_LEN};
use base64::{
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    Engine,
};
use hmac::{Hmac, KeyInit, Mac};
use rand::{rand_core::UnwrapErr, rngs::SysRng, Rng};
use sha2::{Digest, Sha256};

use crate::config::SecretKey;

pub const SECRET_PREFIX: &str = "whsec_";
const CIPHERTEXT_VERSION: &str = "v1";

/// Decodes a `whsec_` secret whose base64 key is 24 to 64 bytes, as OpenAI MCP Events
/// requires. Returns the raw HMAC key.
pub fn signing_key(secret: &str) -> Option<Vec<u8>> {
    let encoded = secret.strip_prefix(SECRET_PREFIX)?;
    let key = STANDARD.decode(encoded).ok()?;
    (24..=64).contains(&key.len()).then_some(key)
}

/// A new random 32-byte signing secret in `whsec_` form.
pub fn generate_secret() -> String {
    let mut bytes = [0_u8; 32];
    UnwrapErr(SysRng).fill_bytes(&mut bytes);
    format!("{SECRET_PREFIX}{}", STANDARD.encode(bytes))
}

/// The Standard Webhooks `v1` signature of `{id}.{timestamp}.{body}`.
pub fn sign(key: &[u8], message_id: &str, timestamp: i64, body: &[u8]) -> String {
    // HMAC accepts keys of any length, so construction cannot fail.
    let mut mac = match Hmac::<Sha256>::new_from_slice(key) {
        Ok(mac) => mac,
        Err(_) => return String::new(),
    };
    mac.update(message_id.as_bytes());
    mac.update(b".");
    mac.update(timestamp.to_string().as_bytes());
    mac.update(b".");
    mac.update(body);
    format!("v1,{}", STANDARD.encode(mac.finalize().into_bytes()))
}

/// The `webhook-signature` header: one signature per key, separated by spaces.
pub fn signature_header(keys: &[Vec<u8>], message_id: &str, timestamp: i64, body: &[u8]) -> String {
    keys.iter()
        .map(|key| sign(key, message_id, timestamp, body))
        .collect::<Vec<_>>()
        .join(" ")
}

/// Encrypts signing secrets with AES-256-GCM. The subscription id is the associated
/// data, so a ciphertext copied to another subscription does not decrypt.
pub struct SecretBox {
    current: (String, LessSafeKey),
    previous: Option<(String, LessSafeKey)>,
}

#[derive(Debug, thiserror::Error)]
#[error("webhook secret encryption failed")]
pub struct SecretBoxError;

fn key_id(key: &SecretKey) -> String {
    hex::encode(&Sha256::digest(key.0)[..4])
}

fn aead_key(key: &SecretKey) -> Result<LessSafeKey, SecretBoxError> {
    UnboundKey::new(&AES_256_GCM, &key.0)
        .map(LessSafeKey::new)
        .map_err(|_| SecretBoxError)
}

impl SecretBox {
    pub fn new(current: &SecretKey, previous: Option<&SecretKey>) -> Result<Self, SecretBoxError> {
        Ok(Self {
            current: (key_id(current), aead_key(current)?),
            previous: previous
                .map(|key| Ok::<_, SecretBoxError>((key_id(key), aead_key(key)?)))
                .transpose()?,
        })
    }

    /// Returns `v1:<key id>:<base64url(nonce || ciphertext || tag)>`.
    pub fn encrypt(
        &self,
        plaintext: &str,
        subscription_id: &str,
    ) -> Result<String, SecretBoxError> {
        let mut nonce = [0_u8; NONCE_LEN];
        UnwrapErr(SysRng).fill_bytes(&mut nonce);
        let mut sealed = plaintext.as_bytes().to_vec();
        self.current
            .1
            .seal_in_place_append_tag(
                Nonce::assume_unique_for_key(nonce),
                Aad::from(subscription_id.as_bytes()),
                &mut sealed,
            )
            .map_err(|_| SecretBoxError)?;
        let mut payload = nonce.to_vec();
        payload.extend_from_slice(&sealed);
        Ok(format!(
            "{CIPHERTEXT_VERSION}:{}:{}",
            self.current.0,
            URL_SAFE_NO_PAD.encode(payload)
        ))
    }

    pub fn decrypt(
        &self,
        ciphertext: &str,
        subscription_id: &str,
    ) -> Result<String, SecretBoxError> {
        let mut parts = ciphertext.splitn(3, ':');
        let (Some(CIPHERTEXT_VERSION), Some(id), Some(encoded)) =
            (parts.next(), parts.next(), parts.next())
        else {
            return Err(SecretBoxError);
        };
        let key = if self.current.0 == id {
            &self.current.1
        } else {
            match &self.previous {
                Some((previous_id, key)) if previous_id == id => key,
                _ => return Err(SecretBoxError),
            }
        };
        let payload = URL_SAFE_NO_PAD
            .decode(encoded)
            .map_err(|_| SecretBoxError)?;
        if payload.len() < NONCE_LEN {
            return Err(SecretBoxError);
        }
        let (nonce, sealed) = payload.split_at(NONCE_LEN);
        let nonce = Nonce::try_assume_unique_for_key(nonce).map_err(|_| SecretBoxError)?;
        let mut sealed = sealed.to_vec();
        let plaintext = key
            .open_in_place(nonce, Aad::from(subscription_id.as_bytes()), &mut sealed)
            .map_err(|_| SecretBoxError)?;
        String::from_utf8(plaintext.to_vec()).map_err(|_| SecretBoxError)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Test vector published by the Standard Webhooks specification. The prefix is
    // added at runtime so secret scanners do not read the public vector as a leak.
    const SPEC_KEY: &str = "MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";
    const SPEC_ID: &str = "msg_p5jXN8AQM9LWM0D4loKWxJek";
    const SPEC_TIMESTAMP: i64 = 1_614_265_330;
    const SPEC_BODY: &str = r#"{"test": 2432232314}"#;
    const SPEC_SIGNATURE: &str = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=";

    #[test]
    fn signs_the_standard_webhooks_test_vector() {
        let Some(key) = signing_key(&format!("{SECRET_PREFIX}{SPEC_KEY}")) else {
            panic!("the spec secret must decode");
        };
        assert_eq!(
            sign(&key, SPEC_ID, SPEC_TIMESTAMP, SPEC_BODY.as_bytes()),
            SPEC_SIGNATURE
        );
        let Some(other) = signing_key(&generate_secret()) else {
            panic!("a generated secret must decode");
        };
        let header = signature_header(&[key, other], SPEC_ID, SPEC_TIMESTAMP, SPEC_BODY.as_bytes());
        assert!(header.starts_with(&format!("{SPEC_SIGNATURE} v1,")));
        assert_eq!(header.split(' ').count(), 2);
    }

    #[test]
    fn validates_secret_format_and_length() {
        assert!(signing_key(&generate_secret()).is_some());
        assert!(signing_key(&format!("whsec_{}", STANDARD.encode([1_u8; 24]))).is_some());
        assert!(signing_key(&format!("whsec_{}", STANDARD.encode([1_u8; 64]))).is_some());
        assert!(signing_key(&format!("whsec_{}", STANDARD.encode([1_u8; 23]))).is_none());
        assert!(signing_key(&format!("whsec_{}", STANDARD.encode([1_u8; 65]))).is_none());
        assert!(signing_key(&STANDARD.encode([1_u8; 32])).is_none());
        assert!(signing_key("whsec_not base64!").is_none());
    }

    #[test]
    fn encrypts_bound_to_the_subscription_and_rotates_keys() -> Result<(), SecretBoxError> {
        let old = SecretKey([1_u8; 32]);
        let new = SecretKey([2_u8; 32]);
        let before = SecretBox::new(&old, None)?;
        let sealed_old = before.encrypt("whsec_secret", "sub-1")?;
        assert!(!sealed_old.contains("whsec_secret"));
        assert_eq!(before.decrypt(&sealed_old, "sub-1")?, "whsec_secret");
        assert!(before.decrypt(&sealed_old, "sub-2").is_err());
        let rotated = SecretBox::new(&new, Some(&old))?;
        assert_eq!(rotated.decrypt(&sealed_old, "sub-1")?, "whsec_secret");
        let sealed_new = rotated.encrypt("whsec_secret", "sub-1")?;
        assert_ne!(sealed_new, sealed_old);
        assert!(before.decrypt(&sealed_new, "sub-1").is_err());
        assert!(rotated.decrypt("v1:00000000:AAAA", "sub-1").is_err());
        Ok(())
    }
}
