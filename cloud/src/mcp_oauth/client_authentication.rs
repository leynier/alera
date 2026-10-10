use jsonwebtoken::Algorithm;
use url::Url;

pub const METHOD_NONE: &str = "none";
pub const METHOD_PRIVATE_KEY_JWT: &str = "private_key_jwt";

/// Signing algorithms accepted for `private_key_jwt` client assertions. HMAC and `none`
/// are absent on purpose: a public JWKS can only verify asymmetric signatures.
pub const ALLOWED_ASSERTION_ALGS: &[Algorithm] =
    &[Algorithm::RS256, Algorithm::PS256, Algorithm::ES256];

/// How a client authenticates at the token endpoint. Each client has exactly one method,
/// and the token endpoint enforces that method rather than accepting either.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ClientAuthentication {
    None,
    PrivateKeyJwt {
        jwks_uri: Url,
        signing_alg: Option<Algorithm>,
    },
}

impl ClientAuthentication {
    pub fn method(&self) -> &'static str {
        match self {
            Self::None => METHOD_NONE,
            Self::PrivateKeyJwt { .. } => METHOD_PRIVATE_KEY_JWT,
        }
    }

    pub fn jwks_uri(&self) -> Option<&str> {
        match self {
            Self::None => None,
            Self::PrivateKeyJwt { jwks_uri, .. } => Some(jwks_uri.as_str()),
        }
    }

    pub fn signing_alg(&self) -> Option<&'static str> {
        match self {
            Self::PrivateKeyJwt {
                signing_alg: Some(alg),
                ..
            } => algorithm_name(*alg),
            _ => None,
        }
    }

    /// Rebuilds the method stored in `mcp_clients`. Returns `None` for a row that does not
    /// describe a usable method, which callers must treat as an unauthenticated client.
    pub fn from_columns(
        method: &str,
        jwks_uri: Option<&str>,
        signing_alg: Option<&str>,
    ) -> Option<Self> {
        match method {
            METHOD_NONE => Some(Self::None),
            METHOD_PRIVATE_KEY_JWT => private_key_jwt(jwks_uri, signing_alg),
            _ => None,
        }
    }
}

pub fn algorithm_name(alg: Algorithm) -> Option<&'static str> {
    match alg {
        Algorithm::RS256 => Some("RS256"),
        Algorithm::PS256 => Some("PS256"),
        Algorithm::ES256 => Some("ES256"),
        _ => None,
    }
}

pub fn allowed_algorithm(value: &str) -> Option<Algorithm> {
    ALLOWED_ASSERTION_ALGS
        .iter()
        .copied()
        .find(|alg| algorithm_name(*alg) == Some(value))
}

/// Chooses the method for a Client ID Metadata Document. The declared method wins when
/// Alera supports it; otherwise a client that also lists `none` is treated as public.
pub fn select(
    declared: Option<&str>,
    supported: &[String],
    jwks_uri: Option<&str>,
    signing_alg: Option<&str>,
) -> Result<ClientAuthentication, &'static str> {
    match declared {
        None | Some(METHOD_NONE) => return Ok(ClientAuthentication::None),
        Some(METHOD_PRIVATE_KEY_JWT) => {
            if let Some(authentication) = private_key_jwt(jwks_uri, signing_alg) {
                return Ok(authentication);
            }
        }
        Some(_) => {}
    }
    if supported.iter().any(|method| method == METHOD_NONE) {
        Ok(ClientAuthentication::None)
    } else {
        Err("Alera supports public clients and private_key_jwt clients only.")
    }
}

fn private_key_jwt(
    jwks_uri: Option<&str>,
    signing_alg: Option<&str>,
) -> Option<ClientAuthentication> {
    let jwks_uri = Url::parse(jwks_uri?).ok()?;
    if jwks_uri.scheme() != "https"
        || jwks_uri.host_str().is_none_or(str::is_empty)
        || jwks_uri.fragment().is_some()
        || !jwks_uri.username().is_empty()
        || jwks_uri.password().is_some()
    {
        return None;
    }
    let signing_alg = match signing_alg {
        None => None,
        Some(value) => Some(allowed_algorithm(value)?),
    };
    Some(ClientAuthentication::PrivateKeyJwt {
        jwks_uri,
        signing_alg,
    })
}

#[cfg(test)]
mod tests {
    use jsonwebtoken::Algorithm;

    use super::{select, ClientAuthentication};
    use crate::mcp_oauth::clients::parse_metadata_document;

    const JWKS: &str = "https://client.example/jwks.json";

    fn supported(methods: &[&str]) -> Vec<String> {
        methods.iter().map(|method| (*method).to_owned()).collect()
    }

    #[test]
    fn public_clients_stay_public() {
        assert_eq!(
            select(None, &[], None, None),
            Ok(ClientAuthentication::None)
        );
        assert_eq!(
            select(Some("none"), &[], Some(JWKS), None),
            Ok(ClientAuthentication::None)
        );
    }

    #[test]
    fn private_key_jwt_with_jwks_uri_is_selected() {
        let Ok(ClientAuthentication::PrivateKeyJwt {
            jwks_uri,
            signing_alg,
        }) = select(
            Some("private_key_jwt"),
            &supported(&["none", "private_key_jwt"]),
            Some(JWKS),
            Some("RS256"),
        )
        else {
            panic!("private_key_jwt must be selected");
        };
        assert_eq!(jwks_uri.as_str(), JWKS);
        assert_eq!(signing_alg, Some(Algorithm::RS256));
    }

    #[test]
    fn unusable_declared_methods_fall_back_to_none_when_listed() {
        let both = supported(&["none", "private_key_jwt"]);
        for (declared, jwks_uri, alg) in [
            ("private_key_jwt", None, None),
            (
                "private_key_jwt",
                Some("http://client.example/jwks.json"),
                None,
            ),
            ("private_key_jwt", Some(JWKS), Some("HS256")),
            ("client_secret_basic", Some(JWKS), None),
        ] {
            assert_eq!(
                select(Some(declared), &both, jwks_uri, alg),
                Ok(ClientAuthentication::None),
                "{declared} {jwks_uri:?} {alg:?}"
            );
        }
    }

    #[test]
    fn unusable_declared_methods_without_none_are_refused() {
        assert!(select(Some("client_secret_basic"), &[], None, None).is_err());
        assert!(select(
            Some("private_key_jwt"),
            &supported(&["private_key_jwt"]),
            None,
            None
        )
        .is_err());
        assert!(select(
            Some("private_key_jwt"),
            &supported(&["private_key_jwt"]),
            Some(JWKS),
            Some("none")
        )
        .is_err());
    }

    #[test]
    fn stored_columns_round_trip() {
        let Ok(stored) = select(Some("private_key_jwt"), &[], Some(JWKS), Some("ES256")) else {
            panic!("private_key_jwt must be selected");
        };
        assert_eq!(
            ClientAuthentication::from_columns(
                stored.method(),
                stored.jwks_uri(),
                stored.signing_alg()
            ),
            Some(stored)
        );
        assert_eq!(
            ClientAuthentication::from_columns("none", None, None),
            Some(ClientAuthentication::None)
        );
        assert_eq!(
            ClientAuthentication::from_columns("private_key_jwt", None, None),
            None
        );
        assert_eq!(
            ClientAuthentication::from_columns("other", None, None),
            None
        );
    }

    #[test]
    fn chatgpt_metadata_document_uses_private_key_jwt() {
        let id = "https://chatgpt.com/oauth/client.json";
        let document = r#"{"client_id":"https://chatgpt.com/oauth/client.json","client_uri":"https://chatgpt.com/","redirect_uris":["https://chatgpt.com/connector_platform_oauth_redirect"],"token_endpoint_auth_method":"private_key_jwt","token_endpoint_auth_methods_supported":["none","private_key_jwt"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"client_name":"ChatGPT","logo_uri":"https://persistent.oaistatic.com/sonic/misc/openai-logo.png","token_endpoint_auth_signing_alg":"RS256","jwks_uri":"https://chatgpt.com/oauth/jwks.json"}"#;
        let Ok((record, _)) = parse_metadata_document(id, document.as_bytes()) else {
            panic!("the ChatGPT metadata document must be accepted");
        };
        assert_eq!(record.name, "ChatGPT");
        assert_eq!(record.authentication.method(), "private_key_jwt");
        assert_eq!(
            record.authentication.jwks_uri(),
            Some("https://chatgpt.com/oauth/jwks.json")
        );
        assert_eq!(record.authentication.signing_alg(), Some("RS256"));
    }

    #[test]
    fn confidential_only_metadata_documents_are_refused() {
        let id = "https://client.example/metadata.json";
        let document = format!(
            r#"{{"client_id":"{id}","redirect_uris":["https://client.example/cb"],"token_endpoint_auth_method":"client_secret_basic"}}"#
        );
        assert!(parse_metadata_document(id, document.as_bytes()).is_err());
        let fallback = format!(
            r#"{{"client_id":"{id}","redirect_uris":["https://client.example/cb"],"token_endpoint_auth_method":"client_secret_basic","token_endpoint_auth_methods_supported":["client_secret_basic","none"]}}"#
        );
        let Ok((record, _)) = parse_metadata_document(id, fallback.as_bytes()) else {
            panic!("a client that lists none must fall back to a public client");
        };
        assert_eq!(record.authentication.method(), "none");
    }
}
