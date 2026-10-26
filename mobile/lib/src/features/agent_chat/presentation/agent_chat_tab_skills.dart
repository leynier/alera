import 'dart:async';

import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_skill_text_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';

/// A chat tab's skills, as on the desktop: loaded when the chat shows an
/// agent and again after a switch to another one, painted in the composer
/// field, and handed to the menu and the messages. Listeners hear every
/// change of [skills].
class AgentChatTabSkills extends ChangeNotifier {
  AgentChatTabSkills({
    required Future<AgentChatSkillList> Function({required bool refresh}) load,
    required this.textController,
  }) : loader = AgentChatSkillsLoader(load) {
    loader.addListener(_onLoaded);
  }

  final AgentChatSkillsLoader loader;
  final AgentChatSkillTextController textController;
  String? _agent;
  bool _disposed = false;

  /// The skills a person can pick, for chips and highlighting.
  List<AgentChatProviderSkill> get skills =>
      loader.list?.invocable ?? const <AgentChatProviderSkill>[];

  /// Follows the chat's agent; another agent has other skills, so the old
  /// list goes and the new one loads after the frame that noticed it.
  void showAgent(String? providerInstanceId) {
    final agent = providerInstanceId == null || providerInstanceId.isEmpty
        ? null
        : providerInstanceId;
    if (agent == _agent) return;
    final hadAgent = _agent != null;
    _agent = agent;
    if (hadAgent) loader.reset();
    if (agent == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _agent == agent) unawaited(loader.request());
    });
  }

  void _onLoaded() {
    final skills = this.skills;
    textController.skills = skills;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    loader
      ..removeListener(_onLoaded)
      ..dispose();
    super.dispose();
  }
}
