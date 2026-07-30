use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ApiError {
    #[error("{message}")]
    Request {
        status: StatusCode,
        code: &'static str,
        message: String,
    },
    #[error("database operation failed")]
    Database(#[from] sqlx::Error),
    #[error("upstream service failed")]
    Upstream(#[source] anyhow::Error),
    #[error("internal service error")]
    Internal(#[source] anyhow::Error),
}

#[derive(Serialize)]
struct ErrorEnvelope {
    error: ErrorBody,
}

#[derive(Serialize)]
struct ErrorBody {
    code: &'static str,
    message: String,
}

impl ApiError {
    pub fn bad_request(code: &'static str, message: impl Into<String>) -> Self {
        Self::Request {
            status: StatusCode::BAD_REQUEST,
            code,
            message: message.into(),
        }
    }

    pub fn unauthorized(code: &'static str, message: impl Into<String>) -> Self {
        Self::Request {
            status: StatusCode::UNAUTHORIZED,
            code,
            message: message.into(),
        }
    }

    pub fn forbidden(code: &'static str, message: impl Into<String>) -> Self {
        Self::Request {
            status: StatusCode::FORBIDDEN,
            code,
            message: message.into(),
        }
    }

    pub fn not_found(code: &'static str, message: impl Into<String>) -> Self {
        Self::Request {
            status: StatusCode::NOT_FOUND,
            code,
            message: message.into(),
        }
    }

    pub fn conflict(code: &'static str, message: impl Into<String>) -> Self {
        Self::Request {
            status: StatusCode::CONFLICT,
            code,
            message: message.into(),
        }
    }

    pub fn too_many(code: &'static str, message: impl Into<String>) -> Self {
        Self::Request {
            status: StatusCode::TOO_MANY_REQUESTS,
            code,
            message: message.into(),
        }
    }

    pub fn unavailable(code: &'static str, message: impl Into<String>) -> Self {
        Self::Request {
            status: StatusCode::SERVICE_UNAVAILABLE,
            code,
            message: message.into(),
        }
    }

    pub fn upstream(error: impl Into<anyhow::Error>) -> Self {
        Self::Upstream(error.into())
    }

    pub fn internal(error: impl Into<anyhow::Error>) -> Self {
        Self::Internal(error.into())
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            Self::Request {
                status,
                code,
                message,
            } => (status, code, message),
            Self::Database(error) => {
                tracing::error!(error = %error, "database operation failed");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "database_error",
                    "The service could not complete the request.".to_owned(),
                )
            }
            Self::Upstream(error) => {
                tracing::warn!(error = %error, "upstream service failed");
                (
                    StatusCode::BAD_GATEWAY,
                    "upstream_error",
                    "An identity or delivery provider could not complete the request.".to_owned(),
                )
            }
            Self::Internal(error) => {
                tracing::error!(error = %error, "internal service error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal_error",
                    "The service could not complete the request.".to_owned(),
                )
            }
        };

        (
            status,
            Json(ErrorEnvelope {
                error: ErrorBody { code, message },
            }),
        )
            .into_response()
    }
}
