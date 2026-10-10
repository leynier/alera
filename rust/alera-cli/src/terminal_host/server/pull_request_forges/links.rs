//! The workspace-to-review link for every forge. Writes the same
//! `LinkedReview` records the desktop keeps (`linked_review.dart`), with the
//! forge's own provider name.

use alera_core::runtime::{LinkedReview, RuntimeStore, Workspace};
use chrono::Utc;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::identity::ForgeKind;
use super::provider::{CreateInput, Created, ForgeProvider};

pub(crate) async fn save_link(
    store: &RuntimeStore,
    workspace_id: &str,
    kind: ForgeKind,
    number: i64,
    url: Option<String>,
    dismissed: bool,
) -> HostResult<()> {
    store
        .upsert_linked_review(LinkedReview {
            workspace_id: workspace_id.to_string(),
            dismissed,
            provider: Some(kind.wire().to_string()),
            number: Some(number),
            url,
            linked_at: Utc::now(),
        })
        .await
        .map(|_| ())
        .map_err(|error| HostError::state(error.to_string()))
}

/// Creates the review and links it to [workspace], like the desktop does
/// after it creates one.
pub(crate) async fn create_and_link(
    store: &RuntimeStore,
    workspace: &Workspace,
    forge: &dyn ForgeProvider,
    input: &CreateInput,
) -> HostResult<Created> {
    let created = forge.create(input).await?;
    if created.number <= 0 {
        return Ok(created);
    }
    save_link(
        store,
        &workspace.id,
        forge.kind(),
        created.number,
        created.url.clone(),
        false,
    )
    .await?;
    Ok(created)
}
