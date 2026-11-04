import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_skill_chips.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_skill_text_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A chat surface's skills: loaded when the chat shows an agent and again
/// after a switch to another one, painted in the composer field, and handed
/// to the menu and the messages. Listeners hear every change of [skills].
class AgentChatSkillsBinding extends ChangeNotifier {
  AgentChatSkillsBinding({
    required Future<AgentChatSkillList> Function({required bool refresh}) load,
    AgentChatSkillTextController? textController,
  }) : loader = AgentChatSkillsLoader(load),
       textController = textController ?? AgentChatSkillTextController() {
    loader.addListener(_onLoaded);
  }

  /// Loads through the runtime for whichever chat [chat] names when asked.
  AgentChatSkillsBinding.forChat(WidgetRef ref, AgentChatRef Function() chat)
    : this(
        load: ({required refresh}) => ref
            .read(agentChatLifecycleRepositoryProvider)
            .skills(chat(), refresh: refresh),
      );

  final AgentChatSkillsLoader loader;
  final AgentChatSkillTextController textController;
  String? _agent;
  bool _disposed = false;

  /// The skills a person can pick, for chips and highlighting.
  List<AgentChatProviderSkill> get skills =>
      loader.list?.invocable ?? const <AgentChatProviderSkill>[];

  /// Forgets the list, as when the surface shows another chat.
  void forget() {
    _agent = null;
    loader.reset();
  }

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

/// Hands [binding]'s skills to the messages in [child].
class const AgentChatSkillsBuilder({
  super.key,
  required final AgentChatSkillsBinding binding,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: binding,
    builder: (context, child) =>
        AgentChatSkillsScope(skills: binding.skills, child: child!),
    child: child,
  );
}
