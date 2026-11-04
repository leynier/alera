//! Startup recovery is transactional in the core runtime store. The host
//! only translates its outcomes for callers and never starts a provider here.

use alera_core::runtime::RuntimeStore;

pub(crate) async fn recover_after_restart(store: &RuntimeStore) -> Result<Vec<String>, String> {
    store
        .recover_agent_chats()
        .await
        .map(|outcomes| {
            outcomes
                .into_iter()
                .map(|outcome| outcome.chat_id)
                .collect()
        })
        .map_err(|error| error.to_string())
}
