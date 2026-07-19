import 'package:alera_mobile/src/core/json_payload_fields.dart';

class WorkspaceTabSummary {
  const WorkspaceTabSummary({
    required this.id,
    required this.workspaceId,
    required this.kind,
    required this.title,
    required this.payload,
  });

  final String id;
  final String workspaceId;
  final String kind;
  final String title;
  final Map<String, Object?> payload;

  factory WorkspaceTabSummary.fromJson(Map<String, Object?> json) {
    return WorkspaceTabSummary(
      id: json.requiredString('id'),
      workspaceId: json.requiredString('workspaceId'),
      kind: json.requiredString('kind'),
      title: json.requiredString('title'),
      payload: json.mapValue('payload'),
    );
  }
}

class MobileTerminalAttachment {
  const MobileTerminalAttachment({
    required this.sessionId,
    required this.created,
    required this.running,
    required this.snapshot,
  });

  final String sessionId;
  final bool created;
  final bool running;
  final List<int> snapshot;

  factory MobileTerminalAttachment.fromJson(Map<String, Object?> json) {
    return MobileTerminalAttachment(
      sessionId: json.requiredString('sessionId'),
      created: json['created'] == true,
      running: json['running'] == true,
      snapshot: json.base64Bytes('snapshotBase64'),
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
