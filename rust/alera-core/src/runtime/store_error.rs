use thiserror::Error;

#[derive(Debug, Error)]
pub enum RuntimeStoreError {
    #[error("{0}")]
    Message(String),
    #[error(
        "Agent profile revision conflict for {profile_id}: expected {expected:?}, current {current:?}. Refresh the profile and try again."
    )]
    AgentProfileRevisionConflict {
        profile_id: String,
        expected: Option<i64>,
        current: Option<i64>,
    },
}
