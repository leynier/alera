// Capability strings stay on the historical `aiText*` names so older apps and
// sidecars keep recognizing the same feature.
pub const RUNTIME_HOST_AI_ASSIST_WORKSPACE_IDENTITY_CAPABILITY: &str = "aiTextWorkspaceIdentityV1";
pub const RUNTIME_HOST_AI_ASSIST_AGENT_TITLE_CAPABILITY: &str = "aiTextAgentTitleV1";
pub const RUNTIME_HOST_AI_ASSIST_SPEECH_MESSAGE_CAPABILITY: &str = "aiTextSpeechMessageV1";
/// A paired phone can ask for a commit message over the staged changes of a
/// workspace through `aiText.commitMessage.generate`.
pub const RUNTIME_HOST_AI_ASSIST_COMMIT_MESSAGE_CAPABILITY: &str = "aiTextCommitMessageV1";
