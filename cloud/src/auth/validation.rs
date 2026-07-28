use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use rand::{rngs::OsRng, RngCore};
use sha2::{Digest, Sha256};

use crate::error::ApiError;

pub(super) fn validate_loopback_redirect(value: &str) -> Result<(), ApiError> {
    let url = url::Url::parse(value).map_err(|_| {
        ApiError::bad_request("invalid_redirect_uri", "The redirect URI is invalid.")
    })?;
    let valid_host = matches!(url.host_str(), Some("127.0.0.1" | "localhost"));
    let valid_path = url.path() == "/callback" || url.path().starts_with("/callback/");
    if url.scheme() != "http"
        || !valid_host
        || url.port().is_none()
        || !valid_path
        || url.query().is_some()
        || url.fragment().is_some()
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(ApiError::bad_request(
            "invalid_redirect_uri",
            "The redirect URI must be an exact loopback HTTP callback.",
        ));
    }
    Ok(())
}

pub(super) fn validate_code_challenge(value: &str) -> Result<(), ApiError> {
    if value.len() != 43
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"-_".contains(&byte))
    {
        return Err(ApiError::bad_request(
            "invalid_code_challenge",
            "The PKCE code challenge is invalid.",
        ));
    }
    Ok(())
}

pub(super) fn validate_code_verifier(value: &str) -> Result<(), ApiError> {
    if !(43..=128).contains(&value.len())
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"-._~".contains(&byte))
    {
        return Err(ApiError::bad_request(
            "invalid_code_verifier",
            "The PKCE code verifier is invalid.",
        ));
    }
    Ok(())
}

pub(super) fn validate_identifier(value: &str, field: &str) -> Result<(), ApiError> {
    if value.is_empty() || value.len() > 128 || value.chars().any(char::is_control) {
        return Err(ApiError::bad_request(
            "invalid_identifier",
            format!("{field} is invalid."),
        ));
    }
    Ok(())
}

pub(super) fn validate_label(value: &str, field: &str) -> Result<(), ApiError> {
    if value.trim().is_empty() || value.len() > 160 || value.chars().any(char::is_control) {
        return Err(ApiError::bad_request(
            "invalid_label",
            format!("{field} is invalid."),
        ));
    }
    Ok(())
}

pub(super) fn validate_short_secret(value: &str, code: &'static str) -> Result<(), ApiError> {
    if value.len() < 16 || value.len() > 2048 || value.chars().any(char::is_control) {
        return Err(ApiError::bad_request(
            code,
            "The authorization value is invalid.",
        ));
    }
    Ok(())
}

pub(super) fn pkce_challenge(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

pub(super) fn random_secret(prefix: &str) -> String {
    let mut bytes = [0_u8; 32];
    OsRng.fill_bytes(&mut bytes);
    format!("{prefix}{}", URL_SAFE_NO_PAD.encode(bytes))
}

pub(super) fn hash_secret(value: &str) -> Vec<u8> {
    Sha256::digest(value.as_bytes()).to_vec()
}

#[cfg(test)]
mod tests {
    use super::{
        pkce_challenge, validate_code_challenge, validate_code_verifier, validate_loopback_redirect,
    };

    #[test]
    fn accepts_only_loopback_callback_redirects() {
        assert!(validate_loopback_redirect("http://127.0.0.1:43121/callback/google").is_ok());
        assert!(validate_loopback_redirect("http://localhost:43121/callback").is_ok());
        assert!(validate_loopback_redirect("https://127.0.0.1:43121/callback").is_err());
        assert!(validate_loopback_redirect("http://example.com:43121/callback").is_err());
        assert!(validate_loopback_redirect("http://127.0.0.1:43121/other").is_err());
    }

    #[test]
    fn verifies_pkce_shape_and_challenge() {
        let verifier = "a".repeat(43);
        let challenge = pkce_challenge(&verifier);
        assert!(validate_code_verifier(&verifier).is_ok());
        assert!(validate_code_challenge(&challenge).is_ok());
        assert_eq!(challenge.len(), 43);
    }
}
