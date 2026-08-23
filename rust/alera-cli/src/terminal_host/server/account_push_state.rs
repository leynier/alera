use std::sync::Arc;
use std::time::Instant;

use alera_core::runtime::RuntimeStore;
use anyhow::Result;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::terminal_host::alera_account::AleraAccountService;
use crate::terminal_host::push_notifications::{PushDamper, PushEvent};

pub(super) struct AccountPushState {
    pub(super) service: Arc<AleraAccountService>,
    pub(super) sign_in_cancel: Option<oneshot::Sender<()>>,
    pub(super) cloud_jobs: usize,
    pub(super) subscription_sync_in_flight: bool,
    pub(super) subscription_sync_waiters: Vec<(u64, i64)>,
    pub(super) push_enabled: bool,
    pub(super) active_subscriptions: usize,
    pub(super) damper: PushDamper,
    pub(super) pending_events: Vec<PushEvent>,
    pub(super) batch_started: Option<Instant>,
    pub(super) flush_generation: u64,
    pub(super) relay_task: Option<JoinHandle<()>>,
    pub(super) relay_stop: Option<oneshot::Sender<()>>,
}

impl AccountPushState {
    pub(super) async fn new(runtime_dir: std::path::PathBuf, store: RuntimeStore) -> Result<Self> {
        let service = Arc::new(AleraAccountService::new(runtime_dir, store.clone()).await?);
        let enabled = store
            .mobile_push_settings()
            .await
            .map(|settings| settings.enabled)
            .unwrap_or(false);
        let active_subscriptions = if enabled {
            service
                .local_account()
                .await?
                .map(|account| account.push_subscription_count.max(0) as usize)
                .unwrap_or_default()
        } else {
            0
        };
        Ok(Self {
            service,
            sign_in_cancel: None,
            cloud_jobs: 0,
            subscription_sync_in_flight: false,
            subscription_sync_waiters: Vec::new(),
            push_enabled: enabled,
            active_subscriptions,
            damper: PushDamper::default(),
            pending_events: Vec::new(),
            batch_started: None,
            flush_generation: 0,
            relay_task: None,
            relay_stop: None,
        })
    }
}
