import 'package:alera/src/features/browser/domain/browser_error.dart';

final class const BrowserAutomationRef({
  required final String pageId,
  required final String snapshotId,
  required final String ref,
}) {
  factory fromJson(Map<String, Object?> json) {
    if (json['pageId'] is! String ||
        json['snapshotId'] is! String ||
        json['ref'] is! String) {
      throw const FormatException('Browser automation ref is invalid.');
    }
    return BrowserAutomationRef(
      pageId: json['pageId']! as String,
      snapshotId: json['snapshotId']! as String,
      ref: json['ref']! as String,
    );
  }

  void validateFor({required String pageId, required String snapshotId}) {
    if (this.pageId != pageId || this.snapshotId != snapshotId) {
      throw const BrowserFailure(
        code: .staleAutomationReference,
        message: 'The browser element reference is stale.',
        recoverable: true,
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'pageId': pageId,
    'snapshotId': snapshotId,
    'ref': ref,
  };
}

final class const BrowserAutomationSnapshot({
  required final String pageId,
  required final String snapshotId,
  required final Uri? url,
  required final String title,
  required final List<BrowserAutomationNode> nodes,
  required final DateTime capturedAt,
  final bool truncated = false,
}) {
  Map<String, Object?> toJson() => <String, Object?>{
    'pageId': pageId,
    'snapshotId': snapshotId,
    if (url != null) 'url': url.toString(),
    'title': title,
    'nodes': <Map<String, Object?>>[for (final node in nodes) node.toJson()],
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'truncated': truncated,
  };
}

final class const BrowserAutomationNode({
  required final BrowserAutomationRef target,
  required final String role,
  required final String name,
  required final int depth,
  final String? value,
  final bool disabled = false,
  final bool? checked,
}) {
  Map<String, Object?> toJson() => <String, Object?>{
    ...target.toJson(),
    'role': role,
    'name': name,
    if (value != null) 'value': value,
    'depth': depth,
    'disabled': disabled,
    if (checked != null) 'checked': checked,
  };
}

enum BrowserAutomationActionKind {
  click,
  fill,
  type,
  select,
  check,
  uncheck,
  focus,
  clear,
  hover,
  drag,
  keypress,
  upload,
  scroll,
}

final class const BrowserAutomationAction({
  required final BrowserAutomationActionKind kind,
  final BrowserAutomationRef? target,
  final BrowserAutomationRef? secondaryTarget,
  final String? value,
  final Map<String, Object?> options = const <String, Object?>{},
});
