enum PushEventKind {
  attention,
  done,
  terminalExit,
  automation,
  unknown;

  static PushEventKind parse(String? value) {
    return switch (value) {
      'automation' => automation,
      'waiting' || 'blocked' || 'gate' || 'attention' => attention,
      'done' => done,
      'terminalExit' || 'terminal_exit' => terminalExit,
      _ => unknown,
    };
  }
}

class PushNavigationIntent {
  const PushNavigationIntent({
    required this.runtimeId,
    required this.eventKind,
    this.accountId,
    this.workspaceId,
    this.tabId,
    this.automationId,
    this.runId,
  });

  final String? accountId;
  final String runtimeId;
  final String? workspaceId;
  final String? tabId;
  final PushEventKind eventKind;
  final String? automationId;
  final String? runId;

  bool get shouldOpenTerminal =>
      eventKind != PushEventKind.terminalExit &&
      eventKind != PushEventKind.automation &&
      tabId != null;

  factory PushNavigationIntent.fromData(Map<String, Object?> data) {
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
