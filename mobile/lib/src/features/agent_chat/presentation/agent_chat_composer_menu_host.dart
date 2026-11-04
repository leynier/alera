import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/mobile_agent_chat_composer_file_search.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_composer_menu.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wires the composer's `@` and `/` suggestions to the paired host: files
/// come from its Quick Open index when it serves one, a picked file joins
/// the draft as a workspace file, as from the Add Attachment sheet, and the
/// local commands run through [commands].
class const AgentChatComposerMenuHost({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String chatId,
  required final TextEditingController controller,
  required final FocusNode focusNode,
  required final AgentChatComposerControls commands,

  /// The chat's skills for `$` and `/skill:name`.
  final AgentChatSkillsLoader? skills,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatComposerMenuHost> createState() =>
      _AgentChatComposerMenuHostState();
}

class _AgentChatComposerMenuHostState
    extends ConsumerState<AgentChatComposerMenuHost> {
  late AgentChatComposerMenuController _menu = _create();

  AgentChatComposerMenuController _create() => AgentChatComposerMenuController(
    text: widget.controller,
    focusNode: widget.focusNode,
    fileSearch: _fileSearch,
    skills: widget.skills,
    commandState: () => widget.commands.slashCommandState(
      ref,
      skills: widget.skills?.skills ?? const <AgentChatProviderSkill>[],
    ),
    onAttach: _attach,
    onCommand: (command) =>
        unawaited(widget.commands.runSlashCommand(context, ref, command)),
  );

  @override
  void didUpdateWidget(covariant AgentChatComposerMenuHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.focusNode != widget.focusNode ||
        oldWidget.skills != widget.skills) {
      _menu.dispose();
      _menu = _create();
    }
  }

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  MobileAgentChatComposerFileSearch? _fileSearch() {
    final Object? client = ref
        .read(workspaceClientProvider(widget.hostId))
        .value;
    if (client is! MobileCodexWorkspaceClient ||
        !client.supportsCodexWorkspaceFiles) {
      return null;
    }
    return MobileAgentChatComposerFileSearch(
      hostId: widget.hostId,
      workspaceId: widget.workspaceId,
      client: client,
    );
  }

  void _attach(String path) => ref
      .read(agentChatDraftStoreProvider)
      .addAttachment(
        widget.hostId,
        widget.chatId,
        AgentChatDraftAttachment(
          path: path,
          source: .workspaceFile,
          displayName: path.split(RegExp(r'[/\\]')).last,
        ),
        workspaceId: widget.workspaceId,
      );

  @override
  Widget build(BuildContext context) =>
      AgentChatComposerSuggestionsView(controller: _menu);
}
