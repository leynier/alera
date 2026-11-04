//! What the running turn reported that later frames of the same turn
//! depend on. Reset when a turn starts and when it ends.

use super::compaction::RunningCompaction;
use super::progress_text::ThinkingProgress;
use super::system_notices::ApiRetry;

#[derive(Debug, Default)]
pub(crate) struct TurnSignals {
    /// The compaction item that started and has not reached its boundary.
    pub(crate) compaction: Option<RunningCompaction>,
    /// A compaction result or boundary arrived in this turn.
    pub(crate) compaction_reported: bool,
    /// The turn's prompt is a bare `/compact`.
    pub(crate) compact_command: bool,
    /// The live retry item while the CLI retries an API request.
    pub(crate) api_retry: Option<ApiRetry>,
    pub(crate) thinking: ThinkingProgress,
}
