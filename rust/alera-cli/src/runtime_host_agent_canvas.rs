use std::path::Path;

use anyhow::Result;

use crate::terminal_host::protocol::RUNTIME_HOST_AGENT_CANVAS_CAPABILITY;

use super::RuntimeHostRpcClient;

impl RuntimeHostRpcClient {
    pub(crate) async fn connect_or_start_agent_canvas(runtime_dir: &Path) -> Result<Self> {
        Self::connect_or_start_with_required_capability(
            runtime_dir,
            RUNTIME_HOST_AGENT_CANVAS_CAPABILITY,
        )
        .await
    }
}
