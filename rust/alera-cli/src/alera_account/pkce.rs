use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use sha2::{Digest as _, Sha256};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub(crate) struct Pkce {
    pub(crate) verifier: String,
    pub(crate) challenge: String,
}

impl Pkce {
    pub(crate) fn generate() -> Self {
        let verifier = format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple());
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        Self {
            verifier,
            challenge,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Pkce;

    #[test]
    fn generated_pair_uses_s256_and_valid_lengths() {
        let pkce = Pkce::generate();
        assert!((43..=128).contains(&pkce.verifier.len()));
        assert_eq!(pkce.challenge.len(), 43);
        assert!(!pkce.challenge.contains('='));
    }
}
