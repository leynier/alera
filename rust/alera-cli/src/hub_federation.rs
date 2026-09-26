//! How the CLI reads hub-owned state from inside a remote terminal.
//!
//! On a satellite the store holds copies of only the workspaces a hub asked it
//! to serve, so listing from it would show a fraction of the truth as if it
//! were everything. A runtime that has ever mirrored a hub workspace is marked
//! as a satellite, and its CLI forwards listings to the hub over the host link
//! (`hub.forward`). With no hub linked the command fails and says why, instead
//! of quietly answering from the copies.

use alera_core::runtime::RuntimeStore;
use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;

pub(crate) const SATELLITE_METADATA_KEY: &str = "satelliteOfHub";

pub(crate) async fn is_satellite(store: &RuntimeStore) -> bool {
    store
        .get_metadata(SATELLITE_METADATA_KEY)
        .await
        .ok()
        .flatten()
        .is_some_and(|value| value == "1")
}

/// Asks the hub when this runtime is a satellite. `Ok(None)` means this is an
/// ordinary runtime and the caller answers from its own store as before.
pub(crate) async fn read_from_hub(
    runtime: &RuntimeDirArgs,
    store: &RuntimeStore,
    request_type: &str,
    payload: Value,
) -> Result<Option<Value>> {
    if !is_satellite(store).await {
        return Ok(None);
    }
    let mut client = crate::runtime_host_required(runtime).await?;
    client
        .request_value_with_deadline(
            "hub.forward",
            &json!({ "type": request_type, "payload": payload }),
            90_000,
        )
        .await
        .map(Some)
        .map_err(|error| anyhow!("{error}"))
}
