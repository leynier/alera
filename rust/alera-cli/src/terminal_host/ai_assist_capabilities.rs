// Capability strings stay on the historical `aiText*` names so older apps and
// sidecars keep recognizing the same feature.
pub const RUNTIME_HOST_AI_ASSIST_WORKSPACE_IDENTITY_CAPABILITY: &str = "aiTextWorkspaceIdentityV1";
pub const RUNTIME_HOST_AI_ASSIST_AGENT_TITLE_CAPABILITY: &str = "aiTextAgentTitleV1";
pub const RUNTIME_HOST_AI_ASSIST_SPEECH_MESSAGE_CAPABILITY: &str = "aiTextSpeechMessageV1";
/// A paired phone can ask for a commit message over the staged changes of a
/// workspace through `aiText.commitMessage.generate`.
pub const RUNTIME_HOST_AI_ASSIST_COMMIT_MESSAGE_CAPABILITY: &str = "aiTextCommitMessageV1";
/// A paired phone can ask for a pull request title and description over the
/// range between a base branch and HEAD through
/// `aiText.pullRequestDetails.generate`.
pub const RUNTIME_HOST_AI_ASSIST_PULL_REQUEST_DETAILS_CAPABILITY: &str =
    "aiTextPullRequestDetailsV1";
/// `aiText.pullRequestDetails.generate` accepts `waitMs`: the runtime keeps the
/// generation running past the caller, answers `status: running` when the wait
/// ends first, and a request with the same `operationId` attaches to it or
/// reads its result for 15 minutes. Additive: do not bump
/// `aleraTerminalHostProtocolVersion`.
pub const RUNTIME_HOST_AI_ASSIST_PULL_REQUEST_DETAILS_RESUME_CAPABILITY: &str =
    "aiTextPullRequestDetailsResumeV1";
/// Direct OpenCode Go HTTP completion and model discovery for AI Assist.
/// Additive: do not bump `aleraTerminalHostProtocolVersion`.
pub const RUNTIME_HOST_AI_ASSIST_OPENCODE_GO_CAPABILITY: &str = "aiAssistOpenCodeGoV1";
pub const RUNTIME_HOST_AI_ASSIST_CHATGPT_CAPABILITY: &str = "aiAssistChatGptV1";
/// Direct ChatGPT completion options such as reasoning effort and service tier.
/// Additive: older clients can continue using the base ChatGPT capability.
pub const RUNTIME_HOST_AI_ASSIST_CHATGPT_OPTIONS_CAPABILITY: &str = "aiAssistChatGptOptionsV1";
