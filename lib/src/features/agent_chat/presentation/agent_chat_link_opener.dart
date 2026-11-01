import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_open_actions.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a link an agent message holds: another chat's `alera-chat` link on
/// that chat's tab (an archived chat stays closed), a path as a workspace
/// file, and web or mail links outside Alera. Anything else only says so.
Future<void> openAgentChatMessageLink(
  BuildContext context,
  WidgetRef ref,
  String link, {
  required Future<void> Function(String path) openFile,
  ExternalUriLauncher? launcher,
}) async {
  if (agentChatRefFromLink(link) case final chat?) {
    return openChatTaskChat(
      context,
      ref,
      chatId: chat.chatId,
      workspaceId: chat.workspaceId,
    );
  }
  final uri = Uri.tryParse(link.trim());
  if (uri == null) return;
  if (!uri.hasScheme) return openFile(uri.path);
  if (!const <String>{'http', 'https', 'mailto'}.contains(uri.scheme)) {
    AleraToast.publish(message: 'This link cannot be opened from a chat.');
    return;
  }
  try {
    await (launcher ?? UrlLauncherExternalUriLauncher()).open(uri);
  } on Object catch (error) {
    AleraToast.publish(
      message: 'Could not open the link: $error',
      tone: .error,
    );
  }
}
