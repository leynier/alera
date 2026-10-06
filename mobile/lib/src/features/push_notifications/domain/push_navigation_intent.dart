enum PushEventKind {
  attention,
  done,
  terminalExit,
  automation,

  /// An agent replied to a question asked from an inbox.
  inboxReply,
  unknown;

  static PushEventKind parse(String? value) {
    return switch (value) {
      'automation' => automation,
      'inboxReply' || 'inbox_reply' => inboxReply,
      'waiting' || 'blocked' || 'gate' || 'attention' => attention,
      'done' => done,
      'terminalExit' || 'terminal_exit' => terminalExit,
      _ => unknown,
    };
  }
}

class const PushNavigationIntent({
  required final String runtimeId,
  required final PushEventKind eventKind,
  final String? accountId,
  final String? workspaceId,
  final String? tabId,
  final String? automationId,
  final String? runId,
  final String? threadId,
}) {
  bool get shouldOpenTerminal =>
      eventKind != PushEventKind.terminalExit &&
      eventKind != PushEventKind.automation &&
      eventKind != PushEventKind.inboxReply &&
      tabId != null;

  factory fromData(Map<String, Object?> data) {
    final runtimeId = _nonEmpty(data['runtimeId']);
    if (runtimeId == null) {
      throw const FormatException('Push payload is missing runtime ID');
    }
    return PushNavigationIntent(
      accountId: _nonEmpty(data['accountId']),
      runtimeId: runtimeId,
      workspaceId: _nonEmpty(data['workspaceId']),
      tabId: _nonEmpty(data['tabId']),
      eventKind: PushEventKind.parse(
        _nonEmpty(data['kind']) ??
            _nonEmpty(data['category']) ??
            _nonEmpty(data['eventType']),
      ),
      automationId: _nonEmpty(data['automationId']),
      runId: _nonEmpty(data['runId']),
      threadId: _nonEmpty(data['threadId']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (accountId != null) 'accountId': accountId,
      'runtimeId': runtimeId,
      if (workspaceId != null) 'workspaceId': workspaceId,
      if (tabId != null) 'tabId': tabId,
      if (automationId != null) 'automationId': automationId,
      if (runId != null) 'runId': runId,
      if (threadId != null) 'threadId': threadId,
      'eventType': eventKind.name,
    };
  }
}

String? _nonEmpty(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
