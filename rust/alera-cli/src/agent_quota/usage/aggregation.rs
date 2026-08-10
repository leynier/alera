use std::collections::{BTreeMap, HashSet};

use chrono::{Local, TimeZone};

use super::pricing::{price_usage, RateTable};
use super::transcripts::UsageRecord;
use super::{UsageBucket, UsageCostSource, UsageProvider, UsageTokenTotals};

#[derive(Default)]
struct MutableBucket {
    totals: UsageTokenTotals,
    cost_usd: f64,
    cache_savings_usd: f64,
    records: u64,
    unpriced_records: u64,
    provider_reported_records: u64,
    sessions: HashSet<String>,
}

pub(super) struct UsageAggregator<'a> {
    since_day: &'a str,
    until_day: &'a str,
    rates: &'a RateTable,
    seen: HashSet<String>,
    buckets: BTreeMap<(String, UsageProvider, String, String, String), MutableBucket>,
}

impl<'a> UsageAggregator<'a> {
    pub fn new(since_day: &'a str, until_day: &'a str, rates: &'a RateTable) -> Self {
        Self {
            since_day,
            until_day,
            rates,
            seen: HashSet::new(),
            buckets: BTreeMap::new(),
        }
    }

    pub fn add(&mut self, account_id: &str, display_name: &str, record: UsageRecord) -> bool {
        if let Some(dedupe_key) = &record.dedupe_key {
            let key = format!("{}:{account_id}:{dedupe_key}", record.provider.as_str());
            if !self.seen.insert(key) {
                return false;
            }
        }
        let Some(timestamp) = Local.timestamp_millis_opt(record.timestamp_ms).single() else {
            return false;
        };
        let day = timestamp.date_naive().format("%Y-%m-%d").to_string();
        if day.as_str() < self.since_day || day.as_str() > self.until_day {
            return false;
        }
        let (cost_usd, cache_savings_usd, cost_source) = price_usage(
            self.rates,
            &record.model,
            &record.totals,
            record.reported_cost_usd,
        );
        let key = (
            day,
            record.provider,
            account_id.to_string(),
            display_name.to_string(),
            record.model,
        );
        let bucket = self.buckets.entry(key).or_default();
        bucket.totals.add(&record.totals);
        bucket.cost_usd += cost_usd;
        bucket.cache_savings_usd += cache_savings_usd;
        bucket.records += 1;
        if cost_source == UsageCostSource::Unpriced {
            bucket.unpriced_records += 1;
        }
        if cost_source == UsageCostSource::ProviderReported {
            bucket.provider_reported_records += 1;
        }
        if !record.session_id.is_empty() {
            bucket.sessions.insert(record.session_id);
        }
        true
    }

    pub fn finish(self) -> Vec<UsageBucket> {
        self.buckets
            .into_iter()
            .map(
                |((day, provider, account_id, display_name, model), bucket)| UsageBucket {
                    day,
                    provider,
                    account_id,
                    display_name,
                    model,
                    totals: bucket.totals,
                    cost_usd: bucket.cost_usd,
                    cache_savings_usd: bucket.cache_savings_usd,
                    cost_source: if bucket.unpriced_records == bucket.records {
                        UsageCostSource::Unpriced
                    } else if bucket.provider_reported_records == bucket.records {
                        UsageCostSource::ProviderReported
                    } else {
                        UsageCostSource::ModelPriced
                    },
                    records: bucket.records,
                    unpriced_records: bucket.unpriced_records,
                    sessions: bucket.sessions.len() as u64,
                },
            )
            .collect()
    }
}
