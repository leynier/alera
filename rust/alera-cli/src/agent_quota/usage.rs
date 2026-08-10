mod aggregation;
mod pricing;
mod transcripts;

#[cfg(test)]
mod tests;

use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use chrono::{NaiveDate, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use self::aggregation::UsageAggregator;
use self::pricing::{load_rates, PricingState, RateTable};
use self::transcripts::{
    might_carry_usage, parse_claude_line, parse_codex_line, CodexScanState, UsageRecord,
};
use super::{home_dir, shell_environment_value, ClaudeProfileRequest};

const MAX_WINDOW_DAYS: i64 = 90;
const MTIME_SLACK_MILLIS: i64 = 36 * 60 * 60 * 1000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(rename_all = "camelCase")]
enum UsageProvider {
    Claude,
    Codex,
}

impl UsageProvider {
    fn as_str(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
        }
    }
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct UsageTokenTotals {
    uncached_input_tokens: u64,
    cached_input_tokens: u64,
    cache_creation_tokens: u64,
    output_tokens: u64,
    reasoning_tokens: u64,
}

impl UsageTokenTotals {
    fn add(&mut self, other: &Self) {
        self.uncached_input_tokens += other.uncached_input_tokens;
        self.cached_input_tokens += other.cached_input_tokens;
        self.cache_creation_tokens += other.cache_creation_tokens;
        self.output_tokens += other.output_tokens;
        self.reasoning_tokens += other.reasoning_tokens;
    }

    fn total(&self) -> u64 {
        self.uncached_input_tokens
            + self.cached_input_tokens
            + self.cache_creation_tokens
            + self.output_tokens
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
enum UsageCostSource {
    ProviderReported,
    ModelPriced,
    Unpriced,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct UsageBucket {
    day: String,
    provider: UsageProvider,
    account_id: String,
    display_name: String,
    model: String,
    totals: UsageTokenTotals,
    cost_usd: f64,
    cache_savings_usd: f64,
    cost_source: UsageCostSource,
    records: u64,
    unpriced_records: u64,
    sessions: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct UsageRequest {
    since_day: String,
    until_day: String,
    #[serde(default = "usage_default_true")]
    claude_default_enabled: bool,
    #[serde(default)]
    claude_profiles: Vec<ClaudeProfileRequest>,
}

#[derive(Debug, Clone)]
struct UsageSourceConfig {
    provider: UsageProvider,
    account_id: String,
    display_name: String,
    directory: PathBuf,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct UsageSource {
    provider: UsageProvider,
    account_id: String,
    display_name: String,
    status: &'static str,
    scanned_files: usize,
    skipped_files: usize,
    distinct_sessions: usize,
    message: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct UsageSnapshot {
    read_at: i64,
    since_day: String,
    until_day: String,
    buckets: Vec<UsageBucket>,
    sources: Vec<UsageSource>,
    pricing: PricingState,
    scan_duration_ms: u64,
}

#[derive(Clone)]
struct CachedFile {
    size: u64,
    modified_millis: u128,
    provider: UsageProvider,
    records: Vec<UsageRecord>,
}

static SCAN_CACHE: OnceLock<Mutex<HashMap<PathBuf, CachedFile>>> = OnceLock::new();

pub(crate) async fn fetch_agent_usage(payload: Value) -> Result<Value> {
    let request: UsageRequest =
        serde_json::from_value(payload).context("Invalid agent usage request")?;
    let since = parse_day(&request.since_day, "sinceDay")?;
    let until = parse_day(&request.until_day, "untilDay")?;
    let window_days = until.signed_duration_since(since).num_days() + 1;
    if !(1..=MAX_WINDOW_DAYS).contains(&window_days) {
        return Err(anyhow!("Usage window must contain between 1 and 90 days"));
    }
    let sources = resolve_sources(&request).await?;
    let (rates, pricing) = load_rates().await;
    let since_day = request.since_day;
    let until_day = request.until_day;
    let started = Instant::now();
    let mut snapshot = tokio::task::spawn_blocking(move || {
        scan_sources(&since_day, &until_day, since, sources, &rates, pricing)
    })
    .await
    .map_err(|error| anyhow!("Usage scan task failed: {error}"))??;
    snapshot.scan_duration_ms = started.elapsed().as_millis() as u64;
    Ok(json!(snapshot))
}

async fn resolve_sources(request: &UsageRequest) -> Result<Vec<UsageSourceConfig>> {
    let home = home_dir().ok_or_else(|| anyhow!("Home directory is unavailable"))?;
    let mut sources = Vec::new();
    if request.claude_default_enabled {
        sources.push(UsageSourceConfig {
            provider: UsageProvider::Claude,
            account_id: "default".to_string(),
            display_name: "Default".to_string(),
            directory: home.join(".claude").join("projects"),
        });
    }
    let ccs_root = shell_environment_value("CCS_DIR")
        .await
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".ccs"));
    for profile in &request.claude_profiles {
        sources.push(UsageSourceConfig {
            provider: UsageProvider::Claude,
            account_id: profile.profile.clone(),
            display_name: profile.alias.clone(),
            directory: ccs_root
                .join("instances")
                .join(&profile.profile)
                .join("projects"),
        });
    }
    let codex_home = shell_environment_value("CODEX_HOME")
        .await
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".codex"));
    sources.push(UsageSourceConfig {
        provider: UsageProvider::Codex,
        account_id: "default".to_string(),
        display_name: "Default".to_string(),
        directory: codex_home.join("sessions"),
    });
    Ok(sources)
}

fn scan_sources(
    since_day: &str,
    until_day: &str,
    since: NaiveDate,
    sources: Vec<UsageSourceConfig>,
    rates: &RateTable,
    pricing: PricingState,
) -> Result<UsageSnapshot> {
    let since_millis = Utc
        .from_utc_datetime(
            &since
                .and_hms_opt(0, 0, 0)
                .ok_or_else(|| anyhow!("Invalid usage window start"))?,
        )
        .timestamp_millis()
        - MTIME_SLACK_MILLIS;
    let mut aggregator = UsageAggregator::new(since_day, until_day, rates);
    let mut source_results = Vec::new();
    let mut live_paths = HashSet::new();
    for source in sources {
        source_results.push(scan_source(
            &source,
            since_millis,
            &mut aggregator,
            &mut live_paths,
        ));
    }
    if let Ok(mut cache) = scan_cache().lock() {
        cache.retain(|path, _| live_paths.contains(path));
    }
    Ok(UsageSnapshot {
        read_at: now_millis(),
        since_day: since_day.to_string(),
        until_day: until_day.to_string(),
        buckets: aggregator.finish(),
        sources: source_results,
        pricing,
        scan_duration_ms: 0,
    })
}

fn scan_source(
    source: &UsageSourceConfig,
    since_millis: i64,
    aggregator: &mut UsageAggregator<'_>,
    live_paths: &mut HashSet<PathBuf>,
) -> UsageSource {
    if !source.directory.is_dir() {
        return source_result(source, "missing", 0, 0, 0, Some("No transcript directory."));
    }
    let (files, walk_failed) = list_transcript_files(&source.directory, since_millis);
    let mut scanned_files = 0;
    let mut skipped_files = 0;
    let mut sessions = HashSet::new();
    let mut read_failed = false;
    for path in files {
        live_paths.insert(path.clone());
        let Some(records) = read_file_records(&path, source.provider) else {
            skipped_files += 1;
            read_failed = true;
            continue;
        };
        if records.is_empty() {
            skipped_files += 1;
            continue;
        }
        scanned_files += 1;
        for record in records {
            let session_id = record.session_id.clone();
            if aggregator.add(&source.account_id, &source.display_name, record)
                && !session_id.is_empty()
            {
                sessions.insert(session_id);
            }
        }
    }
    let partial = walk_failed || read_failed;
    source_result(
        source,
        if partial { "partial" } else { "ok" },
        scanned_files,
        skipped_files,
        sessions.len(),
        partial.then_some("Some transcript files could not be read."),
    )
}

fn source_result(
    source: &UsageSourceConfig,
    status: &'static str,
    scanned_files: usize,
    skipped_files: usize,
    distinct_sessions: usize,
    message: Option<&str>,
) -> UsageSource {
    UsageSource {
        provider: source.provider,
        account_id: source.account_id.clone(),
        display_name: source.display_name.clone(),
        status,
        scanned_files,
        skipped_files,
        distinct_sessions,
        message: message.map(str::to_string),
    }
}

fn list_transcript_files(root: &Path, since_millis: i64) -> (Vec<PathBuf>, bool) {
    let mut pending = vec![root.to_path_buf()];
    let mut files = Vec::new();
    let mut failed = false;
    while let Some(directory) = pending.pop() {
        let entries = match std::fs::read_dir(directory) {
            Ok(entries) => entries,
            Err(_) => {
                failed = true;
                continue;
            }
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(file_type) = entry.file_type() else {
                failed = true;
                continue;
            };
            if file_type.is_dir() {
                pending.push(path);
                continue;
            }
            if !file_type.is_file()
                || path.extension().and_then(|value| value.to_str()) != Some("jsonl")
            {
                continue;
            }
            let modified = entry
                .metadata()
                .ok()
                .and_then(|metadata| metadata.modified().ok())
                .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
                .map(|duration| duration.as_millis() as i64);
            if modified.is_none_or(|modified| modified >= since_millis) {
                files.push(path);
            }
        }
    }
    files.sort();
    (files, failed)
}

fn read_file_records(path: &Path, provider: UsageProvider) -> Option<Vec<UsageRecord>> {
    let metadata = path.metadata().ok()?;
    let modified_millis = metadata
        .modified()
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_millis();
    if let Ok(cache) = scan_cache().lock() {
        if let Some(cached) = cache.get(path).filter(|cached| {
            cached.size == metadata.len()
                && cached.modified_millis == modified_millis
                && cached.provider == provider
        }) {
            return Some(cached.records.clone());
        }
    }
    let file = File::open(path).ok()?;
    let mut records = Vec::new();
    let mut codex_state = CodexScanState::default();
    for line in BufReader::new(file).lines() {
        let line = line.ok()?;
        if !might_carry_usage(&line, provider) {
            continue;
        }
        let record = match provider {
            UsageProvider::Claude => parse_claude_line(&line),
            UsageProvider::Codex => parse_codex_line(&line, &mut codex_state),
        };
        if let Some(record) = record {
            records.push(record);
        }
    }
    if let Ok(mut cache) = scan_cache().lock() {
        cache.insert(
            path.to_path_buf(),
            CachedFile {
                size: metadata.len(),
                modified_millis,
                provider,
                records: records.clone(),
            },
        );
    }
    Some(records)
}

fn scan_cache() -> &'static Mutex<HashMap<PathBuf, CachedFile>> {
    SCAN_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn parse_day(value: &str, name: &str) -> Result<NaiveDate> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .with_context(|| format!("{name} must use YYYY-MM-DD"))
}

fn usage_default_true() -> bool {
    true
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}
