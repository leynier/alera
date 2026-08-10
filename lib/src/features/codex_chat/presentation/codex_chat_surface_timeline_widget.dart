part of 'codex_chat_surface.dart';

class _CodexTimeline extends StatefulWidget {
  const _CodexTimeline({
    super.key,
    required this.snapshot,
    required this.workspacePath,
    required this.title,
    required this.showRawLogs,
    required this.timeline,
    required this.loadingEarlier,
    required this.planDecisionRevision,
    required this.onApproval,
    required this.onElicitation,
    required this.onReject,
    required this.onOpenAttachment,
  });

  final CodexChatSnapshot snapshot;
  final String workspacePath;
  final String title;
  final bool showRawLogs;
  final ScrollController timeline;
  final bool loadingEarlier;
  final ValueNotifier<int> planDecisionRevision;
  final Future<void> Function(
    CodexPendingRequest request, {
    required Object decision,
  })
  onApproval;
  final Future<void> Function(
    CodexPendingRequest request, {
    required String action,
    Map<String, Object?> content,
  })
  onElicitation;
  final Future<void> Function(CodexPendingRequest request) onReject;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;

  @override
  State<_CodexTimeline> createState() => _CodexTimelineState();
}
