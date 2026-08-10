use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::Value;
use tokio::sync::Mutex;

use super::{UsageCostSource, UsageTokenTotals};

const LITELLM_RATES_URL: &str =
    "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";
const RATES_TTL: Duration = Duration::from_secs(24 * 60 * 60);

#[derive(Debug, Clone)]
pub(super) struct ModelRate {
    input: f64,
    output: f64,
    cache_read: f64,
    cache_creation: f64,
}

pub(super) type RateTable = HashMap<String, ModelRate>;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct PricingState {
    pub status: &'static str,
    pub source: &'static str,
    pub known_models: usize,
}

struct CachedRates {
    fetched_at: Instant,
    table: RateTable,
}

static RATE_CACHE: OnceLock<Mutex<Option<CachedRates>>> = OnceLock::new();

pub(super) async fn load_rates() -> (RateTable, PricingState) {
    let cache = RATE_CACHE.get_or_init(|| Mutex::new(None));
    {
        let guard = cache.lock().await;
        if let Some(cached) = guard
            .as_ref()
            .filter(|cached| cached.fetched_at.elapsed() < RATES_TTL)
        {
            return (
                cached.table.clone(),
                pricing_state("fresh", cached.table.len()),
            );
        }
    }
    let fetched = reqwest::Client::new()
        .get(LITELLM_RATES_URL)
        .timeout(Duration::from_secs(10))
        .send()
        .await
        .ok()
        .filter(|response| response.status().is_success());
    if let Some(document) = match fetched {
        Some(response) => response.json::<Value>().await.ok(),
        None => None,
    } {
        let table = parse_rate_table(&document);
        if !table.is_empty() {
            *cache.lock().await = Some(CachedRates {
                fetched_at: Instant::now(),
                table: table.clone(),
            });
            return (table.clone(), pricing_state("fresh", table.len()));
        }
    }
    let guard = cache.lock().await;
    if let Some(cached) = guard.as_ref() {
        return (
            cached.table.clone(),
            pricing_state("cached", cached.table.len()),
        );
    }
    (HashMap::new(), pricing_state("unavailable", 0))
}

fn pricing_state(status: &'static str, known_models: usize) -> PricingState {
    PricingState {
        status,
        source: LITELLM_RATES_URL,
        known_models,
    }
}

pub(super) fn parse_rate_table(document: &Value) -> RateTable {
    let mut table = HashMap::new();
    let Some(entries) = document.as_object() else {
        return table;
    };
    for (name, value) in entries {
        let Some(input) = finite(value.get("input_cost_per_token")) else {
            continue;
        };
        let Some(output) = finite(value.get("output_cost_per_token")) else {
            continue;
        };
        table.insert(
            normalize_model(name),
            ModelRate {
                input,
                output,
                cache_read: finite(value.get("cache_read_input_token_cost")).unwrap_or(input),
                cache_creation: finite(value.get("cache_creation_input_token_cost"))
                    .unwrap_or(input),
            },
        );
    }
    table
}

pub(super) fn price_usage(
    table: &RateTable,
    model: &str,
    totals: &UsageTokenTotals,
    reported: Option<f64>,
) -> (f64, f64, UsageCostSource) {
    if let Some(cost) = reported.filter(|value| value.is_finite() && *value >= 0.0) {
        let savings = lookup_rate(table, model)
            .map(|rate| totals.cached_input_tokens as f64 * (rate.input - rate.cache_read).max(0.0))
            .unwrap_or_default();
        return (cost, savings, UsageCostSource::ProviderReported);
    }
    let Some(rate) = lookup_rate(table, model) else {
        return (0.0, 0.0, UsageCostSource::Unpriced);
    };
    let cost = totals.uncached_input_tokens as f64 * rate.input
        + totals.cached_input_tokens as f64 * rate.cache_read
        + totals.cache_creation_tokens as f64 * rate.cache_creation
        + totals.output_tokens as f64 * rate.output;
    let savings = totals.cached_input_tokens as f64 * (rate.input - rate.cache_read).max(0.0);
    (cost, savings, UsageCostSource::ModelPriced)
}

fn lookup_rate<'a>(table: &'a RateTable, model: &str) -> Option<&'a ModelRate> {
    let normalized = normalize_model(model);
    if matches!(
        normalized.as_str(),
        "" | "<synthetic>" | "synthetic" | "opus" | "sonnet" | "haiku" | "fable"
    ) {
        return None;
    }
    table.get(&normalized)
}

fn normalize_model(value: &str) -> String {
    value
        .trim()
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase()
}

fn finite(value: Option<&Value>) -> Option<f64> {
    value
        .and_then(Value::as_f64)
        .filter(|value| value.is_finite())
}
