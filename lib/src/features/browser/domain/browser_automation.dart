import 'package:alera/src/features/browser/domain/browser_error.dart';

final class BrowserAutomationRef {
  const BrowserAutomationRef({
    required this.pageId,
    required this.snapshotId,
    required this.ref,
  });

  factory BrowserAutomationRef.fromJson(Map<String, Object?> json) {
    if (json['pageId'] is! String ||
        json['snapshotId'] is! String ||
        json['ref'] is! String) {
      throw const FormatException('Browser Automation Ref Is Invalid.');
    }
    return BrowserAutomationRef(
      pageId: json['pageId']! as String,
      snapshotId: json['snapshotId']! as String,
      ref: json['ref']! as String,
    );
  }

  final String pageId;
  final String snapshotId;
  final String ref;

  void validateFor({required String pageId, required String snapshotId}) {
    if (this.pageId != pageId || this.snapshotId != snapshotId) {
      throw const BrowserFailure(
        code: BrowserErrorCode.staleAutomationReference,
        message: 'The Browser Element Reference Is Stale.',
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

final class BrowserAutomationSnapshot {
  const BrowserAutomationSnapshot({
    required this.pageId,
    required this.snapshotId,
    required this.url,
    required this.title,
    required this.nodes,
    required this.capturedAt,
    this.truncated = false,
  });

  final String pageId;
  final String snapshotId;
  final Uri? url;
  final String title;
  final List<BrowserAutomationNode> nodes;
  final DateTime capturedAt;
  final bool truncated;

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

final class BrowserAutomationNode {
  const BrowserAutomationNode({
    required this.target,
    required this.role,
    required this.name,
    required this.depth,
    this.value,
    this.disabled = false,
    this.checked,
  });

  final BrowserAutomationRef target;
  final String role;
  final String name;
  final String? value;
  final int depth;
  final bool disabled;
  final bool? checked;

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

final class BrowserAutomationAction {
  const BrowserAutomationAction({
    required this.kind,
    this.target,
    this.secondaryTarget,
    this.value,
    this.options = const <String, Object?>{},
  });

  final BrowserAutomationActionKind kind;
  final BrowserAutomationRef? target;
  final BrowserAutomationRef? secondaryTarget;
  final String? value;
  final Map<String, Object?> options;
}
