import 'package:alera_mobile/src/core/json_payload_fields.dart';

class const WorkspaceTabSummary({
  required final String id,
  required final String workspaceId,
  required final String kind,
  required final String title,
  required final Map<String, Object?> payload,
  final String? runtimeTitle,
}) {
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

  factory fromJson(Map<String, Object?> json) {
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

class const MobileTerminalAttachment({
  required final String sessionId,
  required final bool created,
  required final bool running,
  required final List<int> snapshot,
  this.snapshotCols,
  final int? snapshotRows,
}) {
  /// The size [snapshot] was written at, absent on a host that predates the
  /// field. Replaying the bytes at any other width lands every absolute cursor
  /// move and hard wrap in the wrong column, so a narrower client replays here
  /// and then resizes, letting its emulator reflow the wrapped lines.
  final int? snapshotCols;

  factory fromJson(Map<String, Object?> json) {
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

class const MobileTerminalSession({
  required final WorkspaceTabSummary tab,
  required final MobileTerminalAttachment attachment,
}) {
  factory fromJson(Map<String, Object?> json) {
    return MobileTerminalSession(
      tab: .fromJson(json.mapValue('tab')),
      attachment: .fromJson(json.mapValue('attachment')),
    );
  }
}
