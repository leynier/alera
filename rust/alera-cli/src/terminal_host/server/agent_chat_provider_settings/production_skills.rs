//! Skill discovery before a chat has a session, for the composer's `$` menu.
//! Each adapter crate reads its own sources the way T3 Code's provider probes
//! do; this module only builds their launch configuration and caches answers.

use super::super::provider_factory::ProviderInstanceConfig;
use super::inspection::{probe_launch, resolve_instance};
use super::{build_config, hydrated_environment, opencode_generation, ProductionConfig};
use alera_provider_protocol::ProviderSkill;
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::time::{Duration, Instant};

/// T3 Code's `PROVIDER_WORKSPACE_SNAPSHOT_TTL_MS`: a spawned probe (Codex,
/// Grok, OpenCode) is too slow to repeat for every `$` typed.
const CACHE_TTL: Duration = Duration::from_secs(5 * 60);
const CACHE_LIMIT: usize = 200;
/// Above every adapter's own deadline (OpenCode's is the longest, 20 s).
const DISCOVERY_DEADLINE: Duration = Duration::from_secs(25);

type SkillCache = HashMap<String, (Instant, Vec<ProviderSkill>)>;

fn skill_cache() -> &'static tokio::sync::Mutex<SkillCache> {
    static CACHE: std::sync::OnceLock<tokio::sync::Mutex<SkillCache>> = std::sync::OnceLock::new();
    CACHE.get_or_init(Default::default)
}

fn cache_key(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
    cwd: &Option<PathBuf>,
) -> String {
    alera_core::runtime::agent_chat_command_digest(&serde_json::json!({
        "provider": provider,
        "instance": instance,
        "secretRefs": instance.map(|instance| &instance.secret_refs),
        "cwd": cwd,
    }))
}

/// Whether [provider] can list skills without a live session.
pub(crate) fn discovers_skills(provider: &str) -> bool {
    matches!(
        provider,
        "codex" | "claudeAgent" | "cursor" | "grok" | "antigravity" | "opencode"
    )
}

pub(super) async fn skills(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
    cwd: Option<PathBuf>,
    refresh: bool,
) -> Option<Result<Vec<ProviderSkill>, String>> {
    if !discovers_skills(provider) {
        return None;
    }
    let key = cache_key(provider, instance, &cwd);
    if !refresh {
        let cache = skill_cache().lock().await;
        if let Some((time, skills)) = cache.get(&key) {
            if time.elapsed() < CACHE_TTL {
                return Some(Ok(skills.clone()));
            }
        }
    }
    let result =
        match tokio::time::timeout(DISCOVERY_DEADLINE, discover(provider, instance, cwd)).await {
            Ok(result) => result,
            Err(_) => Err("Skill discovery timed out.".into()),
        };
    let mut cache = skill_cache().lock().await;
    match &result {
        Ok(skills) => {
            cache.retain(|_, (time, _)| time.elapsed() < CACHE_TTL);
            if cache.len() >= CACHE_LIMIT {
                cache.clear();
            }
            cache.insert(key, (Instant::now(), skills.clone()));
        }
        // A failed probe must not leave an older answer that looks current.
        Err(_) => {
            cache.remove(&key);
        }
    }
    Some(result)
}

async fn discover(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
    cwd: Option<PathBuf>,
) -> Result<Vec<ProviderSkill>, String> {
    let instance = resolve_instance(instance)
        .await
        .map_err(|_| "Provider credentials are unavailable.")?;
    let environment = hydrated_environment(instance.as_ref(), &BTreeMap::new())
        .await
        .map_err(|_| "Provider environment is unavailable.")?;
    let launch = probe_launch(provider, instance.as_ref(), cwd.clone());
    let config = build_config(&launch, &environment)
        .map_err(|_| "Provider launch configuration is invalid.")?;
    match config {
        ProductionConfig::Codex(config) => alera_provider_codex::probe_skills(*config)
            .await
            .map_err(|_| "Codex skill discovery failed.".into()),
        ProductionConfig::Claude(config) => {
            blocking(move || Ok(alera_provider_claude::discover_skills(&config))).await
        }
        ProductionConfig::Cursor(config, _) => {
            let home = alera_provider_cursor::skill_home_directory()
                .ok_or("Cursor skill discovery needs a home directory.")?;
            blocking(move || alera_provider_cursor::discover_skills(config.cwd.as_deref(), &home))
                .await
        }
        ProductionConfig::Grok(config) => alera_provider_grok::discover_skills(&config).await,
        ProductionConfig::Antigravity(config) => {
            blocking(move || alera_provider_antigravity::discover_skills(&config)).await
        }
        ProductionConfig::OpenCode(mut config) => {
            opencode_generation::resolve(&launch, &mut config)
                .await
                .map_err(|_| "OpenCode protocol discovery failed.")?;
            alera_provider_opencode::discover_skills(&config).await
        }
        _ => Ok(Vec::new()),
    }
}

/// Folder scans read many small files; keep them off the async workers.
async fn blocking(
    scan: impl FnOnce() -> Result<Vec<ProviderSkill>, String> + Send + 'static,
) -> Result<Vec<ProviderSkill>, String> {
    tokio::task::spawn_blocking(scan)
        .await
        .map_err(|_| "Skill discovery stopped unexpectedly.".to_owned())?
}
