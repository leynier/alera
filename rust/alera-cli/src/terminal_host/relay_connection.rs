use std::time::Duration;

use tokio_tungstenite::tungstenite::{
    client::IntoClientRequest,
    http::{header, HeaderValue, Request},
};

const RETRY_DELAYS: [Duration; 6] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(4),
    Duration::from_secs(8),
    Duration::from_secs(16),
    Duration::from_secs(30),
];

#[derive(Default)]
pub(super) struct RelayRetryBackoff {
    index: usize,
}

impl RelayRetryBackoff {
    pub(super) fn next_delay(&mut self) -> Duration {
        let delay = RETRY_DELAYS[self.index];
        self.index = (self.index + 1).min(RETRY_DELAYS.len() - 1);
        delay
    }

    pub(super) fn reset(&mut self) {
        self.index = 0;
    }
}

pub(super) fn relay_request(relay_url: &str, grant: &str) -> anyhow::Result<Request<()>> {
    let mut request = relay_url.into_client_request()?;
    request.headers_mut().insert(
        header::AUTHORIZATION,
        HeaderValue::from_str(&format!("Bearer {grant}"))?,
    );
    request.headers_mut().insert(
        header::ORIGIN,
        HeaderValue::from_static("https://app.alera.build"),
    );
    Ok(request)
}
