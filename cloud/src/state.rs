use std::sync::Arc;

use sqlx::PgPool;

use crate::{
    api_models::ProviderKind,
    config::{AppConfig, FcmConfig, SigningConfig},
    fcm::{DisabledFcmSender, FcmSender, HttpFcmSender},
    google_credentials::MetadataAccessTokenProvider,
    mcp_oauth::cimd::{ClientMetadataFetcher, HttpClientMetadataFetcher},
    oauth::{HttpOAuthProvider, OAuthProvider, OAuthProviderRegistry},
    signing::{GoogleKmsSigner, LocalEd25519Signer, TokenSigner},
};

use crate::auth::TokenService;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub config: Arc<AppConfig>,
    pub oauth: OAuthProviderRegistry,
    /// Providers for the browser leg of MCP and device sign-in, using the web callback.
    pub web_oauth: OAuthProviderRegistry,
    pub tokens: TokenService,
    pub fcm: Arc<dyn FcmSender>,
    pub client_metadata: Arc<dyn ClientMetadataFetcher>,
}

impl AppState {
    pub fn from_dependencies(
        pool: PgPool,
        config: AppConfig,
        oauth: OAuthProviderRegistry,
        signer: Arc<dyn TokenSigner>,
        fcm: Arc<dyn FcmSender>,
    ) -> Self {
        let tokens = TokenService::new(signer, config.issuer.clone(), config.audience.clone())
            .with_mcp_resource(config.mcp.resource.clone());
        Self {
            pool,
            config: Arc::new(config),
            web_oauth: oauth.clone(),
            oauth,
            tokens,
            fcm,
            client_metadata: Arc::new(HttpClientMetadataFetcher::default()),
        }
    }

    pub fn with_web_oauth(mut self, web_oauth: OAuthProviderRegistry) -> Self {
        self.web_oauth = web_oauth;
        self
    }

    pub fn with_client_metadata(mut self, fetcher: Arc<dyn ClientMetadataFetcher>) -> Self {
        self.client_metadata = fetcher;
        self
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
        let web_google: Arc<dyn OAuthProvider> = Arc::new(HttpOAuthProvider::new(
            ProviderKind::Google,
            config.mcp.web_google.clone(),
            config.http_timeout,
        )?);
        let web_github: Arc<dyn OAuthProvider> = Arc::new(HttpOAuthProvider::new(
            ProviderKind::Github,
            config.mcp.web_github.clone(),
            config.http_timeout,
        )?);
        let web_oauth = OAuthProviderRegistry::new(vec![web_google, web_github]);

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
        Ok(Self::from_dependencies(pool, config, oauth, signer, fcm).with_web_oauth(web_oauth))
    }
}
