use super::*;

pub(super) async fn account_push_for_test(
    dir: &tempfile::TempDir,
    runtime_store: &RuntimeStore,
) -> account_push_state::AccountPushState {
    account_push_state::AccountPushState::new(dir.path().to_path_buf(), runtime_store.clone())
        .await
        .unwrap()
}
