use std::sync::Arc;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::{DateTime, TimeDelta, Utc};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    api_models::ClientKind,
    error::ApiError,
    signing::{JsonWebKeySet, TokenSigner},
};

const ACCESS_TOKEN_SECONDS: i64 = 15 * 60;
const RELAY_GRANT_SECONDS: i64 = 120;

pub struct RelayGrantInput<'a> {
    pub account_id: Uuid,
    pub runtime_id: &'a str,
    pub client_id: &'a str,
    pub role: &'a str,
    pub key_version: i32,
    pub client_public_key: &'a str,
    pub runtime_public_key: &'a str,
}

#[derive(Clone)]
pub struct TokenService {
    signer: Arc<dyn TokenSigner>,
    issuer: String,
    audience: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct AccessClaims {
    pub iss: String,
    pub sub: String,
    pub aud: String,
    pub exp: i64,
    pub iat: i64,
    pub nbf: i64,
    pub jti: String,
    pub sid: String,
    pub client_id: String,
    pub client_kind: String,
    pub auth_time: i64,
    pub scope: String,
}

#[derive(Serialize)]
struct TokenHeader<'a> {
    alg: &'static str,
    kid: &'a str,
    typ: &'static str,
}

#[derive(Deserialize)]
struct ParsedHeader {
    alg: String,
    kid: String,
    typ: String,
}

impl TokenService {
    pub fn new(signer: Arc<dyn TokenSigner>, issuer: String, audience: String) -> Self {
        Self {
            signer,
            issuer,
            audience,
        }
    }

    pub fn jwks(&self) -> JsonWebKeySet {
        JsonWebKeySet {
            keys: self.signer.public_keys(),
        }
    }

    pub async fn issue(
        &self,
        account_id: Uuid,
        family_id: Uuid,
        client_id: &str,
        client_kind: ClientKind,
        authenticated_at: DateTime<Utc>,
    ) -> Result<String, ApiError> {
        let now = Utc::now();
        let claims = AccessClaims {
            iss: self.issuer.clone(),
            sub: account_id.to_string(),
            aud: self.audience.clone(),
            exp: (now + TimeDelta::seconds(ACCESS_TOKEN_SECONDS)).timestamp(),
            iat: now.timestamp(),
            nbf: (now - TimeDelta::seconds(5)).timestamp(),
            jti: Uuid::now_v7().to_string(),
            sid: family_id.to_string(),
            client_id: client_id.to_owned(),
            client_kind: client_kind.as_str().to_owned(),
            auth_time: authenticated_at.timestamp(),
            scope: client_kind.scopes().join(" "),
        };
        let header = TokenHeader {
            alg: "EdDSA",
            kid: self.signer.key_id(),
            typ: "at+jwt",
        };
        let encoded_header = URL_SAFE_NO_PAD.encode(
            serde_json::to_vec(&header)
                .map_err(|error| ApiError::internal(anyhow::Error::from(error)))?,
        );
        let encoded_claims = URL_SAFE_NO_PAD.encode(
            serde_json::to_vec(&claims)
                .map_err(|error| ApiError::internal(anyhow::Error::from(error)))?,
        );
        let signing_input = format!("{encoded_header}.{encoded_claims}");
        let signature = self
            .signer
            .sign(signing_input.as_bytes())
            .await
            .map_err(ApiError::internal)?;
        Ok(format!(
            "{signing_input}.{}",
            URL_SAFE_NO_PAD.encode(signature)
        ))
    }

    pub async fn issue_relay_grant(&self, input: RelayGrantInput<'_>) -> Result<String, ApiError> {
        let now = Utc::now();
        let claims = RelayGrantClaims {
            iss: self.issuer.clone(),
            sub: input.account_id.to_string(),
            aud: "alera-relay".to_owned(),
            exp: (now + TimeDelta::seconds(RELAY_GRANT_SECONDS)).timestamp(),
            iat: now.timestamp(),
            nbf: (now - TimeDelta::seconds(5)).timestamp(),
            jti: Uuid::now_v7().to_string(),
            account_id: input.account_id,
            runtime_id: input.runtime_id.to_owned(),
            client_id: input.client_id.to_owned(),
            role: input.role.to_owned(),
            key_version: input.key_version,
            client_public_key: input.client_public_key.to_owned(),
            runtime_public_key: input.runtime_public_key.to_owned(),
        };
        let header = TokenHeader {
            alg: "EdDSA",
            kid: self.signer.key_id(),
            typ: "relay+jwt",
        };
        let encoded_header = URL_SAFE_NO_PAD.encode(
            serde_json::to_vec(&header)
                .map_err(|error| ApiError::internal(anyhow::Error::from(error)))?,
        );
        let encoded_claims = URL_SAFE_NO_PAD.encode(
            serde_json::to_vec(&claims)
                .map_err(|error| ApiError::internal(anyhow::Error::from(error)))?,
        );
        let signing_input = format!("{encoded_header}.{encoded_claims}");
        let signature = self
            .signer
            .sign(signing_input.as_bytes())
            .await
            .map_err(ApiError::internal)?;
        Ok(format!(
            "{signing_input}.{}",
            URL_SAFE_NO_PAD.encode(signature)
        ))
    }

    pub fn verify(&self, token: &str) -> Result<AccessClaims, ApiError> {
        let mut segments = token.split('.');
        let header_segment = segments.next();
        let claims_segment = segments.next();
        let signature_segment = segments.next();
        if header_segment.is_none()
            || claims_segment.is_none()
            || signature_segment.is_none()
            || segments.next().is_some()
        {
            return Err(invalid_token());
        }
        let header_segment = header_segment.unwrap_or_default();
        let claims_segment = claims_segment.unwrap_or_default();
        let signature_segment = signature_segment.unwrap_or_default();
        let header: ParsedHeader = decode_json(header_segment)?;
        if header.alg != "EdDSA" || header.typ != "at+jwt" {
            return Err(invalid_token());
        }
        let key = self
            .signer
            .public_keys()
            .into_iter()
            .find(|key| key.kid == header.kid)
            .ok_or_else(invalid_token)?;
        let public_bytes: [u8; 32] = URL_SAFE_NO_PAD
            .decode(key.x)
            .map_err(|_| invalid_token())?
            .try_into()
            .map_err(|_| invalid_token())?;
        let verifying_key = VerifyingKey::from_bytes(&public_bytes).map_err(|_| invalid_token())?;
        let signature_bytes: [u8; 64] = URL_SAFE_NO_PAD
            .decode(signature_segment)
            .map_err(|_| invalid_token())?
            .try_into()
            .map_err(|_| invalid_token())?;
        let signature = Signature::from_bytes(&signature_bytes);
        verifying_key
            .verify(
                format!("{header_segment}.{claims_segment}").as_bytes(),
                &signature,
            )
            .map_err(|_| invalid_token())?;

        let claims: AccessClaims = decode_json(claims_segment)?;
        let now = Utc::now().timestamp();
        if claims.iss != self.issuer
            || claims.aud != self.audience
            || claims.exp <= now
            || claims.nbf > now + 30
            || claims.iat > now + 30
        {
            return Err(invalid_token());
        }
        Ok(claims)
    }

    pub fn expires_in_seconds(&self) -> i64 {
        ACCESS_TOKEN_SECONDS
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayGrantClaims {
    pub iss: String,
    pub sub: String,
    pub aud: String,
    pub exp: i64,
    pub iat: i64,
    pub nbf: i64,
    pub jti: String,
    pub account_id: Uuid,
    pub runtime_id: String,
    pub client_id: String,
    pub role: String,
    pub key_version: i32,
    pub client_public_key: String,
    pub runtime_public_key: String,
}

fn decode_json<T: for<'de> Deserialize<'de>>(value: &str) -> Result<T, ApiError> {
    let decoded = URL_SAFE_NO_PAD.decode(value).map_err(|_| invalid_token())?;
    serde_json::from_slice(&decoded).map_err(|_| invalid_token())
}

fn invalid_token() -> ApiError {
    ApiError::unauthorized("invalid_token", "The access token is invalid or expired.")
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    use chrono::Utc;
    use uuid::Uuid;

    use crate::{api_models::ClientKind, signing::LocalEd25519Signer};

    use super::TokenService;

    #[tokio::test]
    async fn issues_and_verifies_scoped_access_token() {
        let signer = LocalEd25519Signer::from_seed_b64url(
            "test-key".to_owned(),
            &URL_SAFE_NO_PAD.encode([9_u8; 32]),
        );
        assert!(signer.is_ok());
        let signer = match signer {
            Ok(value) => value,
            Err(error) => panic!("unexpected signer error: {error}"),
        };
        let service = TokenService::new(
            Arc::new(signer),
            "https://issuer.example".to_owned(),
            "alera-cloud".to_owned(),
        );
        let account_id = Uuid::now_v7();
        let token = service
            .issue(
                account_id,
                Uuid::now_v7(),
                "runtime-1",
                ClientKind::Runtime,
                Utc::now(),
            )
            .await;
        assert!(token.is_ok());
        let claims = token.and_then(|value| service.verify(&value));
        assert!(claims.is_ok());
        let claims = match claims {
            Ok(value) => value,
            Err(error) => panic!("unexpected token error: {error}"),
        };
        assert_eq!(claims.sub, account_id.to_string());
        assert!(claims.scope.contains("push:send"));
    }
}
