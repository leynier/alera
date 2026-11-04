import 'package:alera_agent_chat/src/agent_chat_modes.dart';

const String agentChatPickerSearchHint = 'Search agents and models';
const String agentChatNoAgentLabel = 'No Agent Available';
const String agentChatOpenProviderSettingsLabel = 'Open Provider Settings';
const String agentChatProviderDefaultLabel = 'Provider Default';
const String agentChatLoadingAgentsLabel = 'Loading agents';
const String agentChatTryAgainLabel = 'Try Again';
const String agentChatArchivedChatsLabel = 'Archived Chats';
const String agentChatReadyMessage = 'Send a message to start.';
const String agentChatWaitingForDecisionHint =
    'The agent is waiting for your decision.';
const String agentChatSwitchBusyReason =
    'The agent can change once this turn ends and nothing is pending.';

const String agentChatFullAccessTitle = 'Turn On Full Access?';
const String agentChatFullAccessMessage =
    'The agent can run commands and change any file without asking.';
const String agentChatFullAccessConfirm = 'Turn On';
const String agentChatSwitchAgentConfirm = 'Switch Agent';

String agentChatSwitchAgentTitle(String agent) => 'Switch To $agent?';

String agentChatSwitchAgentMessage(String agent) =>
    'The conversation so far is handed to $agent, which starts with your '
    'next message.';

String agentChatRuntimeModeLabel(AgentChatRuntimeMode mode) => switch (mode) {
  .approvalRequired => 'Ask For Approval',
  .autoAcceptEdits => 'Accept Edits',
  .auto => 'Auto',
  .fullAccess => 'Full Access',
};

String agentChatRuntimeModeDescription(AgentChatRuntimeMode mode) =>
    switch (mode) {
      .approvalRequired => 'Ask before running commands or changing files.',
      .autoAcceptEdits =>
        'Change files in the workspace without asking; ask for the rest.',
      .auto => 'Only ask for actions the agent considers risky.',
      .fullAccess =>
        'Run commands, use the network and change files without asking.',
    };

String agentChatEffortLabel(String effort) => switch (effort) {
  'none' => 'None',
  'minimal' => 'Minimal',
  'low' => 'Low',
  'medium' => 'Medium',
  'high' => 'High',
  'xhigh' => 'Extra High',
  'max' => 'Max',
  '' => effort,
  _ => '${effort[0].toUpperCase()}${effort.substring(1)}',
};
