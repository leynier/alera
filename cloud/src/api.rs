use axum::{
    body::Body,
    extract::{DefaultBodyLimit, Request, State},
    http::{HeaderValue, StatusCode},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post, put},
    Json, Router,
};
use serde_json::json;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;
use tower_http::trace::TraceLayer;

use crate::{accounts, auth, error::ApiError, mobile, push, relay, runtimes, state::AppState};

pub fn router(state: AppState) -> Router {
    Router::new()
        .merge(
            Router::new()
                .route(
                    "/v1/configuration",
                    get(crate::configuration::head).post(crate::configuration::publish),
                )
                .route(
                    "/v1/configuration/history",
                    get(crate::configuration::history),
                )
                .route(
                    "/v1/configuration/revisions/{revision}",
                    get(crate::configuration::revision),
                )
                .layer(DefaultBodyLimit::max(1024 * 1024)),
        )
        .route("/health", get(health))
        .route("/.well-known/jwks.json", get(auth::jwks))
        .route("/v1/auth/transactions", post(auth::create_transaction))
        .route("/v1/auth/exchange", post(auth::exchange))
        .route("/v1/auth/refresh", post(auth::refresh))
        .route("/v1/auth/revoke", post(auth::revoke))
        .route(
            "/v1/account",
            get(accounts::get_account).delete(accounts::delete_account),
        )
        .route("/v1/account/link", post(accounts::link_account))
        .route("/v1/runtime/transfer", post(runtimes::transfer_runtime))
        .route("/v1/runtime/events", post(push::post_runtime_event))
        .route(
            "/v1/runtime/subscriptions",
            get(push::get_runtime_subscriptions),
        )
        .route("/v1/mobile/enrollments", post(mobile::create_enrollment))
        .route(
            "/v1/mobile/enrollments/redeem",
            post(mobile::redeem_enrollment),
        )
        .route(
            "/v1/mobile/push-token",
            put(mobile::put_push_token).delete(mobile::delete_push_token),
        )
        .route(
            "/v1/mobile/subscriptions/{runtime_id}",
            put(mobile::put_subscription).delete(mobile::delete_subscription),
        )
        .route("/v1/relay/identity", post(relay::register_identity))
        .route("/v1/relay/grants", post(relay::create_grant))
        .route("/v1/mobile/runtimes", get(relay::discover_runtimes))
        .merge(crate::mcp_oauth::router(state.config.mcp.enabled))
        .merge(crate::events::router())
        .layer(DefaultBodyLimit::max(64 * 1024))
        .layer(TraceLayer::new_for_http().make_span_with(request_span))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            require_edge_origin,
        ))
        .with_state(state)
}

/// Records the path only: OAuth callbacks and device pages carry authorization
/// codes, state, and user codes in the query string, which must never be logged.
fn request_span(request: &Request<Body>) -> tracing::Span {
    tracing::debug_span!(
        "request",
        method = %request.method(),
        path = %request.uri().path(),
        version = ?request.version(),
    )
}

async fn health() -> impl IntoResponse {
    (StatusCode::OK, Json(json!({"status": "ok"})))
}

async fn require_edge_origin(
    State(state): State<AppState>,
    request: Request<Body>,
    next: Next,
) -> Result<Response, ApiError> {
    if request.uri().path() == "/health" || state.config.allow_direct_origin {
        return Ok(next.run(request).await);
    }
    let provided = request
        .headers()
        .get("x-alera-origin-auth")
        .and_then(header_text);
    let valid = provided.is_some_and(|provided| {
        token_matches(
            provided,
            state.config.edge_origin_token.as_deref(),
            state.config.edge_previous_origin_token.as_deref(),
        )
    });
    if !valid {
        return Err(ApiError::unauthorized(
            "invalid_origin",
            "The request did not arrive through the Alera edge.",
        ));
    }
    Ok(next.run(request).await)
}

fn header_text(value: &HeaderValue) -> Option<&str> {
    value.to_str().ok().filter(|value| !value.is_empty())
}

fn token_matches(provided: &str, current: Option<&str>, previous: Option<&str>) -> bool {
    let provided_hash = Sha256::digest(provided.as_bytes());
    let current_match = current
        .map(|value| Sha256::digest(value.as_bytes()).ct_eq(&provided_hash))
        .map(bool::from)
        .unwrap_or(false);
    let previous_match = previous
        .map(|value| Sha256::digest(value.as_bytes()).ct_eq(&provided_hash))
        .map(bool::from)
        .unwrap_or(false);
    current_match | previous_match
}

#[cfg(test)]
mod tests {
    use super::{request_span, token_matches};

    #[derive(Clone, Default)]
    struct Captured(std::sync::Arc<std::sync::Mutex<Vec<u8>>>);

    impl std::io::Write for Captured {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            if let Ok(mut buffer) = self.0.lock() {
                buffer.extend_from_slice(bytes);
            }
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn request_spans_leave_out_the_query_string() {
        let captured = Captured::default();
        let writer = captured.clone();
        let subscriber = tracing_subscriber::fmt()
            .with_max_level(tracing::Level::DEBUG)
            .with_ansi(false)
            .with_writer(move || writer.clone())
            .finish();
        tracing::subscriber::with_default(subscriber, || {
            let request = axum::http::Request::builder()
                .uri("/oauth/callback?code=secret-code&state=secret-state")
                .body(axum::body::Body::empty())
                .unwrap_or_default();
            let span = request_span(&request);
            let _entered = span.enter();
            tracing::debug!("handled");
        });
        let output = captured
            .0
            .lock()
            .map(|buffer| String::from_utf8_lossy(&buffer).into_owned())
            .unwrap_or_default();
        assert!(output.contains("/oauth/callback"), "{output}");
        assert!(!output.contains("secret-code"), "{output}");
        assert!(!output.contains("secret-state"), "{output}");
    }

    #[test]
    fn accepts_current_or_previous_edge_secret() {
        assert!(token_matches("new", Some("new"), Some("old")));
        assert!(token_matches("old", Some("new"), Some("old")));
        assert!(!token_matches("other", Some("new"), Some("old")));
    }
}
