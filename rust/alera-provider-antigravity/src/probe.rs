//! Discovers the models an Antigravity account offers from a short-lived ACP
//! session, since the runtime has no session-free listing.

use crate::models::{models_from_session, thinking_from_options, AntigravityModel};
use crate::session_files::{profile_root, remove_session_files};
use crate::{AntigravityProvider, AntigravityProviderConfig};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{Provider, ProviderError, SessionStartInput};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const PROBE_REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

/// A new private working directory, so the probe's session files are
/// provably its own.
pub fn probe_cwd() -> std::io::Result<PathBuf> {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_nanos());
    let directory = std::env::temp_dir().join(format!(
        "alera-antigravity-probe-{}-{nanos}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&directory)?;
    Ok(directory)
}

/// Spawns the configured runtime with no model in a private working
/// directory and lists its models, then removes what the session left.
pub async fn discover_models(
    mut config: AntigravityProviderConfig,
) -> Result<Vec<AntigravityModel>, ProviderError> {
    let cwd = probe_cwd().map_err(|error| ProviderError::Protocol(error.to_string()))?;
    config.model = None;
    config.custom_models.clear();
    config.cwd = Some(cwd.clone());
    config.request_timeout = config.request_timeout.min(PROBE_REQUEST_TIMEOUT);
    let root = profile_root(&config);
    let result = match AntigravityProvider::spawn(config).await {
        Ok(mut provider) => probe_models(&mut provider, &cwd).await,
        Err(error) => Err(error),
    };
    if let (Some(root), Ok((_, Some(session)))) = (&root, &result) {
        remove_session_files(root, session, &cwd);
    }
    let _ = std::fs::remove_dir_all(&cwd);
    result.map(|(models, _)| models)
}

/// Lists the models of a session started in `cwd`, and its native session
/// id, then closes the agent. When the runtime reports thinking as its own option (1.4), each model
/// is selected in turn to read its levels, ending on the current one again.
pub async fn probe_models<T: JsonTransport>(
    provider: &mut AntigravityProvider<T>,
    cwd: &Path,
) -> Result<(Vec<AntigravityModel>, Option<String>), ProviderError> {
    let mut input = SessionStartInput::new("antigravity-model-probe");
    input.cwd = Some(cwd.to_owned());
    let listed = async {
        let session = provider.start_session(input).await?;
        let inner = provider.inner_mut();
        let choices = inner.session_model_choices();
        let current = inner.session_current_model();
        let mut thinking = BTreeMap::new();
        let current_thinking = thinking_from_options(inner.session_config_options());
        let walk = !current_thinking.levels.is_empty();
        if let Some(current) = &current {
            thinking.insert(current.clone(), current_thinking);
        }
        if walk {
            for (id, _) in &choices {
                if Some(id) == current.as_ref() || thinking.contains_key(id) {
                    continue;
                }
                let levels = match inner.select_model(id).await {
                    Ok(()) => thinking_from_options(inner.session_config_options()),
                    Err(_) => Default::default(),
                };
                thinking.insert(id.clone(), levels);
            }
            if let Some(current) = &current {
                let _ = inner.select_model(current).await;
            }
        }
        let models = models_from_session(&choices, current.as_deref(), &thinking);
        Ok::<_, ProviderError>((models, Some(session.native_thread_id)))
    }
    .await;
    let _ = provider.close().await;
    listed
}
