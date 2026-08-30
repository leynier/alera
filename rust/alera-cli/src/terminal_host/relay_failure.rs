use crate::terminal_host::alera_account::CloudRequestError;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Error;

#[derive(Debug, thiserror::Error)]
#[error("relay protocol or authorization was rejected")]
pub(super) struct RelayRejected;

#[derive(Debug, thiserror::Error)]
#[error("a newer runtime replaced this relay connection")]
pub(super) struct RelayReplaced;

pub(super) fn retry_policy(error: &anyhow::Error) -> (&'static str, bool, Option<Duration>) {
    if let Some(cloud) = error.downcast_ref::<CloudRequestError>() {
        return (
            if cloud.is_permanent_authorization_failure() {
                "authorization_failed"
            } else {
                "cloud_unavailable"
            },
            !cloud.is_permanent_failure(),
            cloud.retry_after(),
        );
    }
    if error.is::<RelayReplaced>() {
        return ("connection_replaced", false, None);
    }
    if error.is::<RelayRejected>() {
        return ("protocol_rejected", false, None);
    }
    if let Some(Error::Http(response)) = error.downcast_ref::<Error>() {
        let status = response.status();
        let permanent =
            status.is_client_error() && status.as_u16() != 408 && status.as_u16() != 429;
        return (
            if permanent {
                "authorization_failed"
            } else {
                "transport_unavailable"
            },
            !permanent,
            None,
        );
    }
    if matches!(
        error.downcast_ref::<Error>(),
        Some(Error::Url(_) | Error::Utf8(_))
    ) {
        return ("protocol_incompatible", false, None);
    }
    ("transport_unavailable", true, None)
}
