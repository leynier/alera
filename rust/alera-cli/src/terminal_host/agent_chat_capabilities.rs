use serde_json::Value;

pub(crate) const AGENT_CHAT_EXPERIENCE_CAPABILITIES: &[&str] = &[
    "agentChatDeferredStartV1",
    "agentChatUnselectedDraftV1",
    "agentChatPreferencesV1",
    "agentChatProviderSettingsV1",
    "agentChatEffortV1",
    "agentChatQueueSteerV1",
    "agentChatQueueEditV1",
    "agentChatQueueReorderV1",
    "agentChatForkV1",
    "agentChatRewindV1",
    "agentChatDeleteV1",
    "agentChatApprovalHistoryV1",
    "agentChatTurnDiffV1",
    "agentChatSkillsV1",
    "agentChatReadCursorV1",
    "agentChatProviderSetupV1",
    "agentChatRemoteProviderSetupV1",
    "agentChatAttachmentUploadV1",
    "agentChatNativeRewindV1",
    "agentChatRewindFilesV1",
    "agentChatFileCheckpointsV1",
    "agentChatNativeHistoryV1",
    "agentChatApprovalRedirectV1",
    "agentChatFeedbackV1",
    "agentChatSubagentThreadsV1",
    "agentChatMergeBackV1",
    "agentChatGoalV1",
    "agentChatAcpChildSessionsV1",
    "agentChatWorkflowsV1",
    "agentChatTransfersV1",
    "chatOrchestrationPersonParentV1",
    "chatOrchestrationEffortV1",
];

pub(crate) fn append_agent_chat_capabilities(payload: &mut Value) {
    if let Some(capabilities) = payload["runtimeCapabilities"].as_array_mut() {
        for name in AGENT_CHAT_EXPERIENCE_CAPABILITIES {
            if !capabilities
                .iter()
                .any(|value| value.as_str() == Some(name))
            {
                capabilities.push(Value::String((*name).into()));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn append_preserves_existing_capabilities_and_is_idempotent() {
        let mut payload = serde_json::json!({"runtimeCapabilities":["agentChatV1"]});
        append_agent_chat_capabilities(&mut payload);
        let expected = payload.clone();
        append_agent_chat_capabilities(&mut payload);
        assert_eq!(payload, expected);
        assert_eq!(payload["runtimeCapabilities"][0], "agentChatV1");
        assert_eq!(
            payload["runtimeCapabilities"].as_array().unwrap().len(),
            1 + AGENT_CHAT_EXPERIENCE_CAPABILITIES.len()
        );
    }
}
