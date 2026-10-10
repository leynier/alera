use std::{env, net::SocketAddr, str::FromStr, time::Duration};

use anyhow::{bail, Context};
use url::Url;

#[derive(Clone, Debug)]
pub struct AppConfig {
    pub bind: SocketAddr,
    pub database_url: String,
    pub public_base_url: Url,
    pub relay_base_url: Url,
    pub issuer: String,
    pub audience: String,
    pub edge_origin_token: Option<String>,
    pub edge_previous_origin_token: Option<String>,
    pub allow_direct_origin: bool,
    pub signing: SigningConfig,
    pub google: OAuthProviderConfig,
    pub github: OAuthProviderConfig,
    pub fcm: FcmConfig,
    pub push_delivery_enabled: bool,
    pub tombstone_pepper: String,
    pub http_timeout: Duration,
    pub limits: LimitsConfig,
    pub mcp: McpConfig,
    pub events: EventsConfig,
}

/// Runtime domain events, generic webhooks, and MCP Events.
#[derive(Clone, Debug)]
pub struct EventsConfig {
    /// Encrypts webhook signing secrets at rest (`ALERA_WEBHOOK_SECRET_KEY`). Without it
    /// webhooks and MCP Events subscriptions cannot be created and nothing is delivered.
    pub secret_key: Option<SecretKey>,
    /// The key being rotated out (`ALERA_WEBHOOK_PREVIOUS_SECRET_KEY`); only decrypts.
    pub previous_secret_key: Option<SecretKey>,
    /// OpenAI MCP Events subscriptions (`ALERA_MCP_EVENTS_ENABLED`, default off).
    pub mcp_events_enabled: bool,
    /// Runs the background fan-out and delivery loop (`ALERA_EVENT_WORKER_ENABLED`).
    pub worker_enabled: bool,
    pub callbacks: CallbackPolicy,
}

impl Default for EventsConfig {
    fn default() -> Self {
        Self {
            secret_key: None,
            previous_secret_key: None,
            mcp_events_enabled: false,
            worker_enabled: true,
            callbacks: CallbackPolicy::default(),
        }
    }
}

/// Which callback URLs webhooks and MCP Events may target. Production keeps both off:
/// HTTPS on port 443 to public addresses only.
#[derive(Clone, Copy, Debug, Default)]
pub struct CallbackPolicy {
    /// Development only (`ALERA_WEBHOOK_ALLOW_ANY_PORT`): HTTPS on any port.
    pub allow_any_port: bool,
    /// Tests only, never read from the environment: plain HTTP and private addresses.
    pub allow_private_targets: bool,
}

/// A 32-byte AES-256-GCM key whose bytes never appear in `Debug` output.
#[derive(Clone)]
pub struct SecretKey(pub [u8; 32]);

impl std::fmt::Debug for SecretKey {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("SecretKey(redacted)")
    }
}

impl SecretKey {
    /// Parses standard or URL-safe base64, padded or not, that decodes to exactly 32 bytes.
    pub fn parse(value: &str) -> anyhow::Result<Self> {
        use base64::{
            engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
            Engine,
        };
        let trimmed = value.trim();
        let bytes = STANDARD
            .decode(trimmed)
            .or_else(|_| URL_SAFE_NO_PAD.decode(trimmed.trim_end_matches('=')))
            .context("the key is not base64")?;
        let key: [u8; 32] = bytes
            .try_into()
            .map_err(|_| anyhow::anyhow!("the key must decode to 32 bytes"))?;
        Ok(Self(key))
    }
}

#[derive(Clone, Debug)]
pub struct McpConfig {
    pub enabled: bool,
    pub resource: String,
    pub web_google: OAuthProviderConfig,
    pub web_github: OAuthProviderConfig,
}

impl McpConfig {
    /// Builds the default MCP settings, reusing the native provider credentials for the web leg.
    pub fn defaults(
        public_base_url: &Url,
        google: &OAuthProviderConfig,
        github: &OAuthProviderConfig,
    ) -> Self {
        Self {
            enabled: true,
            resource: format!("{}/v1/mcp", base_url_text(public_base_url)),
            web_google: google.clone(),
            web_github: github.clone(),
        }
    }
}

impl AppConfig {
    pub fn web_callback_url(&self) -> String {
        format!("{}/oauth/callback", base_url_text(&self.public_base_url))
    }

    pub fn public_url(&self, path: &str) -> String {
        format!("{}{path}", base_url_text(&self.public_base_url))
    }
}

pub fn base_url_text(url: &Url) -> &str {
    url.as_str().trim_end_matches('/')
}

#[derive(Clone, Debug)]
pub enum SigningConfig {
    Local {
        key_id: String,
        seed_b64url: String,
    },
    GoogleKms {
        key_id: String,
        sign_url: Url,
        public_key_b64url: String,
        previous_jwks_json: Option<String>,
        metadata_token_url: Url,
    },
}

#[derive(Clone, Debug)]
pub struct OAuthProviderConfig {
    pub client_id: String,
    pub client_secret: String,
    pub authorization_url: Url,
    pub token_url: Url,
    pub user_url: Url,
    pub emails_url: Option<Url>,
    pub jwks_url: Option<Url>,
}

#[derive(Clone, Debug)]
pub enum FcmConfig {
    Disabled,
    Http {
        project_id: String,
        metadata_token_url: Url,
    },
}

#[derive(Clone, Debug)]
pub struct LimitsConfig {
    pub max_runtimes_per_account: i64,
    pub max_mobile_devices_per_account: i64,
    pub push_daily: i32,
    pub push_hourly: i32,
    pub push_burst: i32,
}

impl AppConfig {
    pub fn from_env() -> anyhow::Result<Self> {
        let allow_direct_origin = optional_bool("ALERA_ALLOW_DIRECT_ORIGIN", false)?;
        let edge_origin_token = optional("ALERA_EDGE_ORIGIN_TOKEN");
        if !allow_direct_origin && edge_origin_token.as_deref().unwrap_or_default().is_empty() {
            bail!("ALERA_EDGE_ORIGIN_TOKEN is required when direct origin access is disabled");
        }

        let public_base_url = required_url("ALERA_PUBLIC_BASE_URL")?;
        let google = google_config()?;
        let github = github_config()?;
        let mcp = mcp_config(&public_base_url, &google, &github)?;
        let config = Self {
            bind: required("ALERA_BIND")?
                .parse()
                .context("invalid ALERA_BIND")?,
            database_url: required("DATABASE_URL")?,
            public_base_url,
            relay_base_url: env_url("ALERA_RELAY_BASE_URL", "wss://api.alera.build/v1/relay")?,
            issuer: required("ALERA_ISSUER")?,
            audience: required("ALERA_AUDIENCE")?,
            edge_origin_token,
            edge_previous_origin_token: optional("ALERA_EDGE_PREVIOUS_ORIGIN_TOKEN"),
            allow_direct_origin,
            signing: signing_config()?,
            google,
            github,
            fcm: fcm_config()?,
            push_delivery_enabled: optional_bool("ALERA_PUSH_DELIVERY_ENABLED", true)?,
            tombstone_pepper: required("ALERA_TOMBSTONE_PEPPER")?,
            http_timeout: Duration::from_secs(15),
            limits: LimitsConfig {
                max_runtimes_per_account: env_number("ALERA_MAX_RUNTIMES", 10)?,
                max_mobile_devices_per_account: env_number("ALERA_MAX_MOBILE_DEVICES", 5)?,
                push_daily: env_number("ALERA_PUSH_DAILY_LIMIT", 500)?,
                push_hourly: env_number("ALERA_PUSH_HOURLY_LIMIT", 60)?,
                push_burst: env_number("ALERA_PUSH_BURST_LIMIT", 10)?,
            },
            mcp,
            events: events_config()?,
        };
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> anyhow::Result<()> {
        if self.tombstone_pepper.len() < 32 {
            bail!("ALERA_TOMBSTONE_PEPPER must contain at least 32 characters");
        }
        if self.limits.max_runtimes_per_account <= 0
            || self.limits.max_mobile_devices_per_account <= 0
            || self.limits.push_daily <= 0
            || self.limits.push_hourly <= 0
            || self.limits.push_burst <= 0
        {
            bail!("account and push limits must be positive");
        }
        if self.limits.push_hourly > self.limits.push_daily
            || self.limits.push_burst > self.limits.push_hourly
        {
            bail!("push limits must satisfy burst <= hourly <= daily");
        }
        if self.mcp.resource == self.audience {
            bail!("ALERA_MCP_RESOURCE must differ from ALERA_AUDIENCE");
        }
        Url::parse(&self.mcp.resource).context("invalid ALERA_MCP_RESOURCE")?;
        Ok(())
    }
}

fn signing_config() -> anyhow::Result<SigningConfig> {
    match required("ALERA_SIGNING_MODE")?.as_str() {
        "local" => Ok(SigningConfig::Local {
            key_id: required("ALERA_SIGNING_KEY_ID")?,
            seed_b64url: required("ALERA_SIGNING_SEED_B64URL")?,
        }),
        "google-kms" => Ok(SigningConfig::GoogleKms {
            key_id: required("ALERA_SIGNING_KEY_ID")?,
            sign_url: required_url("ALERA_KMS_SIGN_URL")?,
            public_key_b64url: required("ALERA_KMS_PUBLIC_KEY_B64URL")?,
            previous_jwks_json: optional("ALERA_KMS_PREVIOUS_JWKS_JSON"),
            metadata_token_url: env_url(
                "ALERA_GOOGLE_METADATA_TOKEN_URL",
                "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
            )?,
        }),
        value => bail!("unsupported ALERA_SIGNING_MODE: {value}"),
    }
}

fn google_config() -> anyhow::Result<OAuthProviderConfig> {
    Ok(OAuthProviderConfig {
        client_id: required("ALERA_GOOGLE_CLIENT_ID")?,
        client_secret: required("ALERA_GOOGLE_CLIENT_SECRET")?,
        authorization_url: env_url(
            "ALERA_GOOGLE_AUTHORIZATION_URL",
            "https://accounts.google.com/o/oauth2/v2/auth",
        )?,
        token_url: env_url(
            "ALERA_GOOGLE_TOKEN_URL",
            "https://oauth2.googleapis.com/token",
        )?,
        user_url: env_url(
            "ALERA_GOOGLE_USER_URL",
            "https://openidconnect.googleapis.com/v1/userinfo",
        )?,
        emails_url: None,
        jwks_url: Some(env_url(
            "ALERA_GOOGLE_JWKS_URL",
            "https://www.googleapis.com/oauth2/v3/certs",
        )?),
    })
}

fn github_config() -> anyhow::Result<OAuthProviderConfig> {
    Ok(OAuthProviderConfig {
        client_id: required("ALERA_GITHUB_CLIENT_ID")?,
        client_secret: required("ALERA_GITHUB_CLIENT_SECRET")?,
        authorization_url: env_url(
            "ALERA_GITHUB_AUTHORIZATION_URL",
            "https://github.com/login/oauth/authorize",
        )?,
        token_url: env_url(
            "ALERA_GITHUB_TOKEN_URL",
            "https://github.com/login/oauth/access_token",
        )?,
        user_url: env_url("ALERA_GITHUB_USER_URL", "https://api.github.com/user")?,
        emails_url: Some(env_url(
            "ALERA_GITHUB_EMAILS_URL",
            "https://api.github.com/user/emails",
        )?),
        jwks_url: None,
    })
}

fn mcp_config(
    public_base_url: &Url,
    google: &OAuthProviderConfig,
    github: &OAuthProviderConfig,
) -> anyhow::Result<McpConfig> {
    let mut config = McpConfig::defaults(public_base_url, google, github);
    config.enabled = optional_bool("ALERA_MCP_ENABLED", true)?;
    if let Some(resource) = optional("ALERA_MCP_RESOURCE") {
        config.resource = resource;
    }
    config.web_google = web_credentials(google, "ALERA_WEB_GOOGLE")?;
    config.web_github = web_credentials(github, "ALERA_WEB_GITHUB")?;
    Ok(config)
}

fn web_credentials(
    native: &OAuthProviderConfig,
    prefix: &str,
) -> anyhow::Result<OAuthProviderConfig> {
    let client_id = optional(&format!("{prefix}_CLIENT_ID"));
    let client_secret = optional(&format!("{prefix}_CLIENT_SECRET"));
    let mut config = native.clone();
    match (client_id, client_secret) {
        (Some(id), Some(secret)) => {
            config.client_id = id;
            config.client_secret = secret;
        }
        (None, None) => {}
        _ => bail!("{prefix}_CLIENT_ID and {prefix}_CLIENT_SECRET must be set together"),
    }
    Ok(config)
}

fn events_config() -> anyhow::Result<EventsConfig> {
    let key = |name: &str| {
        optional(name)
            .map(|value| SecretKey::parse(&value).with_context(|| format!("invalid {name}")))
            .transpose()
    };
    Ok(EventsConfig {
        secret_key: key("ALERA_WEBHOOK_SECRET_KEY")?,
        previous_secret_key: key("ALERA_WEBHOOK_PREVIOUS_SECRET_KEY")?,
        mcp_events_enabled: optional_bool("ALERA_MCP_EVENTS_ENABLED", false)?,
        worker_enabled: optional_bool("ALERA_EVENT_WORKER_ENABLED", true)?,
        callbacks: CallbackPolicy {
            allow_any_port: optional_bool("ALERA_WEBHOOK_ALLOW_ANY_PORT", false)?,
            allow_private_targets: false,
        },
    })
}

fn fcm_config() -> anyhow::Result<FcmConfig> {
    match env::var("ALERA_FCM_MODE").unwrap_or_else(|_| "disabled".to_owned()).as_str() {
        "disabled" => Ok(FcmConfig::Disabled),
        "http" => Ok(FcmConfig::Http {
            project_id: required("ALERA_FCM_PROJECT_ID")?,
            metadata_token_url: env_url(
                "ALERA_GOOGLE_METADATA_TOKEN_URL",
                "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
            )?,
        }),
        value => bail!("unsupported ALERA_FCM_MODE: {value}"),
    }
}

fn required(name: &str) -> anyhow::Result<String> {
    env::var(name).with_context(|| format!("{name} is required"))
}

fn optional(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

fn required_url(name: &str) -> anyhow::Result<Url> {
    Url::parse(&required(name)?).with_context(|| format!("invalid {name}"))
}

fn env_url(name: &str, default: &str) -> anyhow::Result<Url> {
    Url::parse(&env::var(name).unwrap_or_else(|_| default.to_owned()))
        .with_context(|| format!("invalid {name}"))
}

fn optional_bool(name: &str, default: bool) -> anyhow::Result<bool> {
    match env::var(name) {
        Ok(value) => bool::from_str(&value).with_context(|| format!("invalid {name}")),
        Err(env::VarError::NotPresent) => Ok(default),
        Err(error) => Err(error).with_context(|| format!("invalid {name}")),
    }
}

fn env_number<T>(name: &str, default: T) -> anyhow::Result<T>
where
    T: FromStr + ToString,
    T::Err: std::error::Error + Send + Sync + 'static,
{
    env::var(name)
        .unwrap_or_else(|_| default.to_string())
        .parse()
        .with_context(|| format!("invalid {name}"))
}
