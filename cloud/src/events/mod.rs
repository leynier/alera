//! Runtime domain events delivered to generic webhooks and OpenAI MCP Events
//! subscriptions. See `docs/remote-mcp.md` (Events).

pub mod callback;
pub mod catalog;
pub mod cursor;
pub mod delivery;
pub mod fanout;
pub mod ingest;
pub mod mcp_subscriptions;
pub mod models;
pub mod secrets;
pub mod webhooks;
pub mod wire;
pub mod worker;

use std::sync::Arc;

use axum::{
    extract::DefaultBodyLimit,
    routing::{delete, get, post},
    Router,
};
use tokio::sync::Notify;

use crate::{config::EventsConfig, state::AppState};

use self::{callback::CallbackClient, secrets::SecretBox};

/// Shared event delivery dependencies.
#[derive(Clone)]
pub struct EventsContext {
    /// `None` when `ALERA_WEBHOOK_SECRET_KEY` is unset: nothing can be created or sent.
    pub secrets: Option<Arc<SecretBox>>,
    pub callbacks: CallbackClient,
    /// Wakes the delivery loop when new deliveries are queued.
    pub wake: Arc<Notify>,
}

impl EventsContext {
    pub fn from_config(config: &EventsConfig) -> Self {
        let secrets = config.secret_key.as_ref().and_then(|key| {
            match SecretBox::new(key, config.previous_secret_key.as_ref()) {
                Ok(secrets) => Some(Arc::new(secrets)),
                Err(error) => {
                    tracing::error!(error = %error, "webhook secret key is unusable");
                    None
                }
            }
        });
        Self {
            secrets,
            callbacks: CallbackClient::new(config.callbacks),
            wake: Arc::new(Notify::new()),
        }
    }
}

/// Routes for runtimes (events and webhooks), the edge (MCP Events), and the pump.
pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/v1/runtime/domain-events",
            post(ingest::post_domain_events).layer(DefaultBodyLimit::max(512 * 1024)),
        )
        .route(
            "/v1/runtime/event-subscriptions",
            get(ingest::get_event_subscriptions),
        )
        .route(
            "/v1/webhooks",
            get(webhooks::list_webhooks).post(webhooks::create_webhook),
        )
        .route("/v1/webhooks/{id}", delete(webhooks::delete_webhook))
        .route("/v1/webhooks/{id}/test", post(webhooks::test_webhook))
        .route(
            "/v1/mcp/event-subscriptions",
            post(mcp_subscriptions::subscribe),
        )
        .route(
            "/v1/mcp/event-subscriptions/unsubscribe",
            post(mcp_subscriptions::unsubscribe),
        )
        .route(
            "/v1/mcp/event-subscriptions/{id}",
            delete(mcp_subscriptions::delete_subscription),
        )
        .route("/v1/internal/event-deliveries/pump", post(worker::pump))
}
