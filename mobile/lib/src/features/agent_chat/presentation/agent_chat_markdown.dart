import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/markdown/alera_markdown_view.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_view_memory.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_link_target.dart';
import 'package:alera_mobile/src/features/updater/infra/mobile_external_browser.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_markdown_uri_policy.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:flutter/material.dart';

/// The chat a timeline row belongs to. Provided once by the chat body so
/// every message can open the files the agent names, so notices can say
/// which chat they are about, and so folds remember what the person opened.
class const AgentChatScope({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String chatId,
  required final String? cwd,
  final AgentChatViewMemory? memory,
  required super.child,
}) extends InheritedWidget {
  static AgentChatScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentChatScope>();

  @override
  bool updateShouldNotify(AgentChatScope oldWidget) =>
      hostId != oldWidget.hostId ||
      workspaceId != oldWidget.workspaceId ||
      chatId != oldWidget.chatId ||
      cwd != oldWidget.cwd ||
      !identical(memory, oldWidget.memory);
}

/// Whether the fold under [key] is open: the person's own choice for this
/// chat when they made one, else [fallback].
bool agentChatFoldExpanded(
  BuildContext context,
  String key, {
  required bool fallback,
}) =>
    context.getInheritedWidgetOfExactType<AgentChatScope>()?.memory?.expansion(
      key,
    ) ??
    fallback;

/// Keeps a fold the person toggled the way they left it, across tab
/// switches and reconnects.
void agentChatRememberFold(
  BuildContext context,
  String key, {
  required bool expanded,
}) => context
    .getInheritedWidgetOfExactType<AgentChatScope>()
    ?.memory
    ?.rememberExpansion(key, expanded: expanded);

/// Agent Markdown in the shared viewer style. Web links open in the browser;
/// file links open the workspace file viewer, which the user asked for by
/// tapping, so it is the one navigation a message may cause.
class const AgentChatMarkdown({super.key, required final String text})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AleraMarkdownView(
    data: text,
    imageBuilder: _image,
    onLinkTap: (url) => unawaited(openAgentChatLink(context, url)),
  );
}

Future<void> openAgentChatLink(BuildContext context, String url) async {
  final scope = AgentChatScope.maybeOf(context);
  final target = agentChatLinkTarget(url, cwd: scope?.cwd);
  switch (target) {
    case AgentChatExternalLink(:final uri):
      await openMobileExternalBrowser(uri);
    case AgentChatWorkspaceLink(:final path, :final line):
      if (scope == null || !context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceFileViewerScreen(
            hostId: scope.hostId,
            workspaceId: scope.workspaceId,
            relativePath: path,
            highlightLine: line,
          ),
        ),
      );
    case null:
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('This link cannot be opened here.')),
        );
      }
  }
}

Widget _image(
  BuildContext context,
  String imageUrl,
  double? width,
  double? height,
) {
  if (!isSupportedMarkdownViewerRemoteImageUri(Uri.tryParse(imageUrl))) {
    return _ImagePlaceholder(width: width, height: height);
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    child: Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: .contain,
      errorBuilder: (_, _, _) =>
          _ImagePlaceholder(width: width, height: height),
    ),
  );
}

class const _ImagePlaceholder({final double? width, final double? height})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: width ?? AleraTokens.space48,
    height: height ?? AleraTokens.space48,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AleraTokens.surface,
      border: Border.all(color: AleraTokens.borderSubtle),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    ),
    child: const Icon(
      AleraIcons.imageError,
      color: AleraTokens.foregroundMuted,
    ),
  );
}
