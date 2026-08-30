part of 'codex_chat_surface.dart';

class const _CodexTimeline({
  super.key,
  required final CodexChatSnapshot snapshot,
  required final String workspacePath,
  required final String title,
  required final bool showRawLogs,
  required final ScrollController timeline,
  required final bool loadingEarlier,
  required final ValueNotifier<int> planDecisionRevision,
  required final Future<void> Function(
    CodexPendingRequest request, {
    required Object decision,
  })
  onApproval,
  required final Future<void> Function(
    CodexPendingRequest request, {
    required String action,
    Map<String, Object?> content,
  })
  onElicitation,
  required final Future<void> Function(CodexPendingRequest request) onReject,
  required final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment,
}) extends StatefulWidget {
  @override
  State<_CodexTimeline> createState() => _CodexTimelineState();
}
