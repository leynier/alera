import 'package:alera_mobile/src/core/json_payload_fields.dart';

class WorkspaceTabSummary {
  const WorkspaceTabSummary({
    required this.id,
    required this.workspaceId,
    required this.kind,
    required this.title,
    required this.payload,
    this.runtimeTitle,
  });

  final String id;
  final String workspaceId;
  final String kind;
  final String title;
  final Map<String, Object?> payload;
  final String? runtimeTitle;

  bool get isTerminal => kind == 'terminal';

  bool get isCodex => kind == 'codex';

  bool get hasManualTitle => payload['manualTitle'] == true;

  String get displayTitle {
    if (hasManualTitle) {
      return title;
    }
    if (isCodex) {
      return title.trim().isEmpty || title == 'Codex' ? 'Codex Chat' : title;
    }
    final automaticTitle = runtimeTitle?.trim() ?? '';
    if (automaticTitle.isEmpty || automaticTitle == 'Terminal') {
      return title;
    }
    return automaticTitle;
  }

  /// The PTY session handle for terminal tabs; the runtime falls back to the
  /// tab id when the payload carries no explicit session id.
  String get terminalSessionId =>
      payload.optionalString('terminalSessionId') ?? id;

  factory WorkspaceTabSummary.fromJson(Map<String, Object?> json) {
    return WorkspaceTabSummary(
      id: json.requiredString('id'),
      workspaceId: json.requiredString('workspaceId'),
      kind: json.requiredString('kind'),
      title: json.requiredString('title'),
      payload: json.mapValue('payload'),
      runtimeTitle: json.optionalString('runtimeTitle'),
    );
  }

  WorkspaceTabSummary copyWithRuntimeTitle(String value) {
    return WorkspaceTabSummary(
      id: id,
      workspaceId: workspaceId,
      kind: kind,
      title: title,
      payload: payload,
      runtimeTitle: value,
    );
  }
}

class MobileTerminalAttachment {
  const MobileTerminalAttachment({
    required this.sessionId,
    required this.created,
    required this.running,
    required this.snapshot,
    this.snapshotCols,
    this.snapshotRows,
  });

  final String sessionId;
  final bool created;
  final bool running;
  final List<int> snapshot;

  /// The size [snapshot] was written at, absent on a host that predates the
  /// field. Replaying the bytes at any other width lands every absolute cursor
  /// move and hard wrap in the wrong column, so a narrower client replays here
  /// and then resizes, letting its emulator reflow the wrapped lines.
  final int? snapshotCols;
  final int? snapshotRows;

  factory MobileTerminalAttachment.fromJson(Map<String, Object?> json) {
    return MobileTerminalAttachment(
      sessionId: json.requiredString('sessionId'),
      created: json['created'] == true,
      running: json['running'] == true,
      snapshot: json.base64Bytes('snapshotBase64'),
      snapshotCols: json.optionalPositiveInt('snapshotCols'),
      snapshotRows: json.optionalPositiveInt('snapshotRows'),
    );
  }
}

class MobileTerminalSession {
  const MobileTerminalSession({required this.tab, required this.attachment});

  final WorkspaceTabSummary tab;
  final MobileTerminalAttachment attachment;

  factory MobileTerminalSession.fromJson(Map<String, Object?> json) {
    return MobileTerminalSession(
      tab: WorkspaceTabSummary.fromJson(json.mapValue('tab')),
      attachment: MobileTerminalAttachment.fromJson(
        json.mapValue('attachment'),
      ),
    );
  }
}
