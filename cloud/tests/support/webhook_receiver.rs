//! A loopback HTTP receiver for webhook contract tests. `/echo` answers verification
//! challenges; `/noecho` never does. Queued statuses answer event deliveries in order.

use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
};

use axum::{
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode, Uri},
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use serde_json::{json, Value};

#[derive(Clone, Debug)]
pub struct Received {
    pub path: String,
    pub headers: HeaderMap,
    pub body: Vec<u8>,
}

impl Received {
    pub fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or(Value::Null)
    }

    pub fn header(&self, name: &str) -> String {
        self.headers
            .get(name)
            .and_then(|value| value.to_str().ok())
            .unwrap_or_default()
            .to_owned()
    }
}

#[derive(Clone, Default)]
struct Shared {
    received: Arc<Mutex<Vec<Received>>>,
    statuses: Arc<Mutex<VecDeque<u16>>>,
}

pub struct Receiver {
    pub base: String,
    shared: Shared,
    task: tokio::task::JoinHandle<()>,
}

impl Receiver {
    pub async fn start() -> anyhow::Result<Self> {
        let shared = Shared::default();
        let app = Router::new()
            .route("/{*path}", post(receive))
            .with_state(shared.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let base = format!("http://{}", listener.local_addr()?);
        let task = tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });
        Ok(Self { base, shared, task })
    }

    pub fn url(&self, path: &str) -> String {
        format!("{}{path}", self.base)
    }

    /// Answers the next event deliveries with these statuses, then 200.
    pub fn respond_with(&self, statuses: &[u16]) {
        if let Ok(mut queue) = self.shared.statuses.lock() {
            queue.extend(statuses);
        }
    }

    pub fn received(&self) -> Vec<Received> {
        self.shared
            .received
            .lock()
            .map(|items| items.clone())
            .unwrap_or_default()
    }

    /// Event deliveries only, without verification challenges.
    pub fn events(&self) -> Vec<Received> {
        self.received()
            .into_iter()
            .filter(|item| item.json()["type"] != "verification")
            .collect()
    }

    pub fn challenges(&self) -> usize {
        self.received().len() - self.events().len()
    }
}

impl Drop for Receiver {
    fn drop(&mut self) {
        self.task.abort();
    }
}

async fn receive(
    State(shared): State<Shared>,
    uri: Uri,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    let item = Received {
        path: uri.path().to_owned(),
        headers,
        body: body.to_vec(),
    };
    let value = item.json();
    if let Ok(mut received) = shared.received.lock() {
        received.push(item.clone());
    }
    if value["type"] == "verification" {
        return if item.path == "/echo" {
            Json(json!({"challenge": value["challenge"]})).into_response()
        } else {
            Json(json!({"ok": true})).into_response()
        };
    }
    let status = shared
        .statuses
        .lock()
        .ok()
        .and_then(|mut queue| queue.pop_front())
        .unwrap_or(200);
    StatusCode::from_u16(status)
        .unwrap_or(StatusCode::OK)
        .into_response()
}
