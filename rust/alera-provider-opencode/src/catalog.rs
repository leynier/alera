//! OpenCode's model catalog as T3 Code's driver reads it. A cold 2.x server
//! loads its catalog lazily: it lists nothing, then only part of it, for its
//! first moments, and a catalog read then would be cached as complete.

use opencode_agent_sdk::{Generation, HttpTransport, OpenCodeClient, OpenCodeError, OpenCodeModel};
use serde_json::{json, Value};
use std::time::Duration;

const SETTLE_INTERVAL: Duration = Duration::from_millis(250);
const SETTLE_TIMEOUT: Duration = Duration::from_secs(5);

/// The models the server lists. A 2.x catalog is read every 250 ms until
/// two non-empty reads agree; when that takes over 5 s, or a later read
/// fails, the latest non-empty read stands. A failed first read fails.
pub async fn settled_models<T: HttpTransport>(
    client: &mut OpenCodeClient<T>,
) -> Result<Vec<OpenCodeModel>, OpenCodeError> {
    if client.config().generation == Generation::Legacy1 {
        return client.list_models().await;
    }
    let mut latest = Vec::new();
    let settle = async {
        let mut previous = None;
        loop {
            let models = match client.list_models().await {
                Ok(models) => models,
                Err(error) if latest.is_empty() => return Err(error),
                Err(_) => return Ok(()),
            };
            let current = (!models.is_empty()).then(|| fingerprint(&models));
            if !models.is_empty() {
                latest = models;
            }
            if current.is_some() && current == previous {
                return Ok(());
            }
            previous = current;
            tokio::time::sleep(SETTLE_INTERVAL).await;
        }
    };
    match tokio::time::timeout(SETTLE_TIMEOUT, settle).await {
        Ok(Err(error)) => Err(error),
        _ => Ok(latest),
    }
}

/// What a read must repeat to settle: each model's identity, names and
/// variants, in any order.
fn fingerprint(models: &[OpenCodeModel]) -> Vec<String> {
    let mut entries: Vec<String> = models
        .iter()
        .map(|model| {
            let mut variants: Vec<&str> = match model.raw.get("variants") {
                Some(Value::Array(variants)) => variants
                    .iter()
                    .filter_map(|variant| variant.get("id").and_then(Value::as_str))
                    .collect(),
                Some(Value::Object(variants)) => variants.keys().map(String::as_str).collect(),
                _ => Vec::new(),
            };
            variants.sort_unstable();
            json!([
                model.provider_id,
                model.model_id,
                model.name,
                model.raw.get("providerName"),
                variants
            ])
            .to_string()
        })
        .collect();
    entries.sort_unstable();
    entries
}
