use std::sync::Arc;

use sqlx::PgPool;

use crate::{
    api_models::ProviderKind,
    config::{AppConfig, FcmConfig, SigningConfig},
    fcm::{DisabledFcmSender, FcmSender, HttpFcmSender},
    google_credentials::MetadataAccessTokenProvider,
    oauth::{HttpOAuthProvider, OAuthProvider, OAuthProviderRegistry},
    signing::{GoogleKmsSigner, LocalEd25519Signer, TokenSigner},
};

use crate::auth::TokenService;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub config: Arc<AppConfig>,
    pub oauth: OAuthProviderRegistry,
    pub tokens: TokenService,
    pub fcm: Arc<dyn FcmSender>,
}

impl AppState {
    pub fn from_dependencies(
        pool: PgPool,
        config: AppConfig,
        oauth: OAuthProviderRegistry,
        signer: Arc<dyn TokenSigner>,
        fcm: Arc<dyn FcmSender>,
    ) -> Self {
        let tokens = TokenService::new(signer, config.issuer.clone(), config.audience.clone());
        Self {
            pool,
            config: Arc::new(config),
            oauth,
            tokens,
            fcm,
        }
    }

    pub fn from_config(pool: PgPool, config: AppConfig) -> anyhow::Result<Self> {
        let google: Arc<dyn OAuthProvider> = Arc::new(HttpOAuthProvider::new(
            ProviderKind::Google,
            config.google.clone(),
            config.http_timeout,
        )?);
        let github: Arc<dyn OAuthProvider> = Arc::new(HttpOAuthProvider::new(
            ProviderKind::Github,
            config.github.clone(),
            config.http_timeout,
        )?);
        let oauth = OAuthProviderRegistry::new(vec![google, github]);

        let signer: Arc<dyn TokenSigner> = match &config.signing {
            SigningConfig::Local {
                key_id,
                seed_b64url,
            } => Arc::new(LocalEd25519Signer::from_seed_b64url(
                key_id.clone(),
                seed_b64url,
            )?),
            SigningConfig::GoogleKms {
                key_id,
                sign_url,
                public_key_b64url,
                previous_jwks_json,
                metadata_token_url,
            } => {
                let provider = Arc::new(MetadataAccessTokenProvider::new(
                    metadata_token_url.clone(),
                    config.http_timeout,
                )?);
                Arc::new(GoogleKmsSigner::new(
                    key_id.clone(),
                    sign_url.clone(),
                    public_key_b64url.clone(),
                    previous_jwks_json.as_deref(),
                    provider,
                    config.http_timeout,
                )?)
            }
        };
        let fcm: Arc<dyn FcmSender> = match &config.fcm {
            FcmConfig::Disabled => Arc::new(DisabledFcmSender),
            FcmConfig::Http {
                project_id,
                metadata_token_url,
            } => {
                let provider = Arc::new(MetadataAccessTokenProvider::new(
                    metadata_token_url.clone(),
                    config.http_timeout,
                )?);
                Arc::new(HttpFcmSender::new(
                    project_id,
                    provider,
                    config.http_timeout,
                )?)
            }
        };
        Ok(Self::from_dependencies(pool, config, oauth, signer, fcm))
    }
}
