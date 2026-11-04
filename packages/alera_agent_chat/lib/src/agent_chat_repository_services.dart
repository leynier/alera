import 'package:alera_agent_chat/src/agent_chat_lifecycle_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_settings_repository.dart';

abstract interface class AgentChatExtendedRepository {
  AgentChatLifecycleRepository get lifecycle;
  AgentChatSettingsRepository get settings;
}

extension AgentChatRepositoryServices on AgentChatRepository {
  AgentChatLifecycleRepository get lifecycle =>
      this is AgentChatExtendedRepository
      ? (this as AgentChatExtendedRepository).lifecycle
      : const UnsupportedAgentChatLifecycleRepository();

  AgentChatSettingsRepository get settings =>
      this is AgentChatExtendedRepository
      ? (this as AgentChatExtendedRepository).settings
      : const UnsupportedAgentChatSettingsRepository();
}
