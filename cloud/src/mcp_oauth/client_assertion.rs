use chrono::{DateTime, TimeDelta, Utc};
use jsonwebtoken::{
    dangerous::insecure_decode,
    decode, decode_header,
    jwk::{Jwk, KeyAlgorithm},
    Algorithm, DecodingKey, Validation,
};
use serde::Deserialize;

use crate::{auth::validation::hash_secret, state::AppState};

use super::{
    cimd::ClientMetadataFetcher,
    client_authentication::{ClientAuthentication, ALLOWED_ASSERTION_ALGS},
    client_jwks::ClientJwksCache,
    clients::load_client_authentication,
    forms::FormFields,
    OAuthError,
};

pub const JWT_BEARER_ASSERTION_TYPE: &str =
    "urn:ietf:params:oauth:client-assertion-type:jwt-bearer";
const MAX_ASSERTION_LIFETIME_SECONDS: i64 = 300;
const LEEWAY_SECONDS: i64 = 30;
const MAX_ASSERTION_BYTES: usize = 8 * 1024;
const MAX_JTI_CHARS: usize = 255;

/// The client credentials a token request carries.
pub struct ClientCredentials<'a> {
    pub client_id: Option<&'a str>,
    pub assertion_type: Option<&'a str>,
    pub assertion: Option<&'a str>,
}

impl<'a> ClientCredentials<'a> {
    pub fn from_form(form: &'a FormFields) -> Result<Self, OAuthError> {
        let field = |name: &str| {
            form.get(name).map_err(|_| {
                OAuthError::invalid_request(format!("The {name} parameter is repeated."))
            })
        };
        let credentials = Self {
            client_id: field("client_id")?,
            assertion_type: field("client_assertion_type")?,
            assertion: field("client_assertion")?,
        };
        if credentials.assertion_type.is_some() != credentials.assertion.is_some() {
            return Err(OAuthError::invalid_request(
                "client_assertion and client_assertion_type must be sent together.",
            ));
        }
        Ok(credentials)
    }

    /// The client the request names: `client_id`, else the assertion subject, else the
    /// caller's fallback. The assertion is not trusted here; it only locates the client.
    fn client_id(&self, fallback: Option<&str>) -> Result<String, OAuthError> {
        let subject = self.assertion.and_then(assertion_subject);
        match (self.client_id, subject) {
            (Some(client_id), Some(subject)) if client_id != subject => Err(
                OAuthError::invalid_client("The client assertion names another client."),
            ),
            (Some(client_id), _) => Ok(client_id.to_owned()),
            (None, Some(subject)) => Ok(subject),
            (None, None) => fallback
                .map(ToOwned::to_owned)
                .ok_or_else(|| OAuthError::invalid_request("The client_id parameter is required.")),
        }
    }
}

#[derive(Deserialize)]
struct SubjectClaim {
    sub: Option<String>,
}

fn assertion_subject(assertion: &str) -> Option<String> {
    insecure_decode::<SubjectClaim>(assertion)
        .ok()
        .and_then(|data| data.claims.sub)
}

#[derive(Deserialize)]
#[serde(untagged)]
enum Audience {
    One(String),
    Many(Vec<String>),
}

impl Audience {
    fn contains_any(&self, accepted: &[&str]) -> bool {
        match self {
            Self::One(value) => accepted.contains(&value.as_str()),
            Self::Many(values) => values
                .iter()
                .any(|value| accepted.contains(&value.as_str())),
        }
    }
}

#[derive(Deserialize)]
struct AssertionClaims {
    aud: Audience,
    exp: i64,
    iat: Option<i64>,
    jti: Option<String>,
}

/// A verified assertion: its `jti` and expiry, which the caller records against replay.
#[derive(Debug)]
pub struct VerifiedAssertion {
    pub jti: String,
    pub expires_at: DateTime<Utc>,
}

/// What a `private_key_jwt` assertion is checked against.
pub struct AssertionPolicy<'a> {
    pub client_id: &'a str,
    pub authentication: &'a ClientAuthentication,
    pub audiences: &'a [&'a str],
    pub now: DateTime<Utc>,
}

/// Authenticates the client of a token request with the one method it registered and
/// returns its id. `fallback_client_id` names the client when the request does not.
pub async fn authenticate_client(
    state: &AppState,
    form: &FormFields,
    fallback_client_id: Option<&str>,
) -> Result<String, OAuthError> {
    let credentials = ClientCredentials::from_form(form)?;
    let client_id = credentials.client_id(fallback_client_id)?;
    let authentication = load_client_authentication(state, &client_id)
        .await?
        .ok_or_else(|| OAuthError::invalid_client("The client is not registered with Alera."))?;
    let assertion = match (&authentication, credentials.assertion) {
        (ClientAuthentication::None, None) => return Ok(client_id),
        (ClientAuthentication::None, Some(_)) => {
            return Err(OAuthError::invalid_client(
                "This client is registered as a public client.",
            ))
        }
        (ClientAuthentication::PrivateKeyJwt { .. }, None) => {
            return Err(OAuthError::invalid_client(
                "This client must authenticate with private_key_jwt.",
            ))
        }
        (ClientAuthentication::PrivateKeyJwt { .. }, Some(assertion)) => assertion,
    };
    if credentials.assertion_type != Some(JWT_BEARER_ASSERTION_TYPE) {
        return Err(OAuthError::invalid_client(
            "The client_assertion_type is not supported.",
        ));
    }
    let issuer = state.config.issuer.as_str();
    let token_endpoint = state.config.public_url("/oauth/token");
    let verified = verify_assertion(
        &state.client_jwks,
        state.client_metadata.as_ref(),
        assertion,
        &AssertionPolicy {
            client_id: &client_id,
            authentication: &authentication,
            audiences: &[issuer, token_endpoint.as_str()],
            now: Utc::now(),
        },
    )
    .await
    .map_err(OAuthError::invalid_client)?;
    let recorded = sqlx::query(
        r#"
        INSERT INTO mcp_client_assertions (client_id, jti_hash, expires_at)
        VALUES ($1, $2, $3)
        ON CONFLICT DO NOTHING
        "#,
    )
    .bind(&client_id)
    .bind(hash_secret(&verified.jti))
    .bind(verified.expires_at)
    .execute(&state.pool)
    .await?
    .rows_affected();
    if recorded == 0 {
        return Err(OAuthError::invalid_client(
            "The client assertion was already used.",
        ));
    }
    Ok(client_id)
}

/// Verifies an RFC 7523 client assertion. Errors are user-safe and never echo the
/// assertion.
pub async fn verify_assertion(
    jwks: &ClientJwksCache,
    fetcher: &dyn ClientMetadataFetcher,
    assertion: &str,
    policy: &AssertionPolicy<'_>,
) -> Result<VerifiedAssertion, &'static str> {
    let invalid = "The client assertion is invalid.";
    let ClientAuthentication::PrivateKeyJwt {
        jwks_uri,
        signing_alg,
    } = policy.authentication
    else {
        return Err("This client is registered as a public client.");
    };
    if assertion.len() > MAX_ASSERTION_BYTES {
        return Err(invalid);
    }
    let header = decode_header(assertion).map_err(|_| invalid)?;
    let alg = header.alg;
    if !ALLOWED_ASSERTION_ALGS.contains(&alg) || signing_alg.is_some_and(|declared| declared != alg)
    {
        return Err("The client assertion signing algorithm is not supported.");
    }
    let key = jwks
        .signing_key(fetcher, jwks_uri, header.kid.as_deref())
        .await?;
    if !key_allows(&key, alg) {
        return Err("The client assertion signing algorithm is not supported.");
    }
    let decoding_key = DecodingKey::from_jwk(&key).map_err(|_| invalid)?;
    let mut validation = Validation::new(alg);
    validation.leeway = LEEWAY_SECONDS as u64;
    validation.set_required_spec_claims(&["exp", "iss", "sub", "aud"]);
    validation.set_issuer(&[policy.client_id]);
    validation.sub = Some(policy.client_id.to_owned());
    // `nbf` stays optional, but a present one is honoured with the same clock skew.
    validation.validate_nbf = true;
    // The audience may be the issuer or the token endpoint, and may list other values.
    validation.validate_aud = false;
    let claims = decode::<AssertionClaims>(assertion, &decoding_key, &validation)
        .map_err(|error| {
            tracing::info!(reason = ?error.kind(), "client assertion rejected");
            invalid
        })?
        .claims;
    if !claims.aud.contains_any(policy.audiences) {
        return Err("The client assertion audience is not this authorization server.");
    }
    let now = policy.now.timestamp();
    if claims.exp > now + MAX_ASSERTION_LIFETIME_SECONDS + LEEWAY_SECONDS {
        return Err("The client assertion lifetime is too long.");
    }
    if claims.iat.is_some_and(|iat| iat > now + LEEWAY_SECONDS) {
        return Err("The client assertion was issued in the future.");
    }
    let jti = claims
        .jti
        .filter(|jti| !jti.is_empty() && jti.chars().count() <= MAX_JTI_CHARS)
        .ok_or("The client assertion must carry a jti.")?;
    let expires_at = DateTime::from_timestamp(claims.exp, 0).ok_or(invalid)?
        + TimeDelta::seconds(LEEWAY_SECONDS);
    Ok(VerifiedAssertion { jti, expires_at })
}

/// A key that names its algorithm may only verify that algorithm.
fn key_allows(key: &Jwk, alg: Algorithm) -> bool {
    match key.common.key_algorithm {
        None => true,
        Some(declared) => matches!(
            (declared, alg),
            (KeyAlgorithm::RS256, Algorithm::RS256)
                | (KeyAlgorithm::PS256, Algorithm::PS256)
                | (KeyAlgorithm::ES256, Algorithm::ES256)
        ),
    }
}

#[cfg(test)]
#[path = "client_assertion_tests.rs"]
mod tests;
