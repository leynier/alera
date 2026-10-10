/// Runtime capability that advertises the `webhook.*` requests.
const String runtimeEventsCapability = 'runtimeEventsV1';

/// Event kinds a webhook can subscribe to, in the runtime journal's order.
enum RuntimeEventKind(final String wireName, final String label) {
  inboxReply('inbox.reply', 'Inbox Reply'),
  inboxQuestionStatus('inbox.question.status', 'Inbox Question Status'),
  agentStatus('agent.status', 'Agent Status'),
  terminalExit('terminal.exit', 'Terminal Exit'),
  orchestrationTaskState('orchestration.task.state', 'Task State'),
  orchestrationGateCreated('orchestration.gate.created', 'Gate Created'),
  orchestrationEscalation('orchestration.escalation', 'Escalation'),
  automationRunState('automation.run.state', 'Automation Run State'),
  workspaceStartState('workspace.start.state', 'Workspace Start State'),
  workspaceLifecycle('workspace.lifecycle', 'Workspace Lifecycle'),
  pullRequestWatch('pullRequest.watch', 'Pull Request Watch');

  static RuntimeEventKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wireName == value) {
        return kind;
      }
    }
    return null;
  }
}

/// A signed webhook that receives this account's runtime events, as returned
/// by `webhook.list` and `webhook.create`.
final class const RuntimeWebhook({
  required final String id,
  required final String url,
  required final List<String> kinds,
  final List<String> runtimeIds = const <String>[],
  final bool allRuntimes = true,
  final String status = '',
  final DateTime? createdAt,
  final DateTime? lastDeliveryAt,
  final String? lastError,
}) {
  factory fromJson(Map<String, Object?> json) {
    final id = _optionalString(json['id']);
    final url = _optionalString(json['url']);
    if (id == null || url == null) {
      throw const FormatException('Webhook payload needs an id and a url.');
    }
    return RuntimeWebhook(
      id: id,
      url: url,
      kinds: _strings(json['kinds']),
      runtimeIds: _strings(json['runtimeIds']),
      allRuntimes: json['allRuntimes'] != false,
      status: _optionalString(json['status']) ?? '',
      createdAt: _optionalDateTime(json['createdAt']),
      lastDeliveryAt: _optionalDateTime(json['lastDeliveryAt']),
      lastError: _optionalString(json['lastError']),
    );
  }

  /// Whether the webhook receives every event kind the runtime knows.
  bool get receivesAllKinds {
    return RuntimeEventKind.values.every(
      (kind) => kinds.contains(kind.wireName),
    );
  }
}

/// Result of `webhook.create`: the stored webhook and its signing secret,
/// which the cloud returns only this once.
final class const RuntimeWebhookCreation({
  required final RuntimeWebhook webhook,
  required final String secret,
}) {
  factory fromJson(Map<String, Object?> json) {
    final webhook = json['webhook'];
    final secret = _optionalString(json['secret']);
    if (webhook is! Map || secret == null) {
      throw const FormatException(
        'Webhook creation payload needs a webhook and a secret.',
      );
    }
    return RuntimeWebhookCreation(
      webhook: RuntimeWebhook.fromJson(Map<String, Object?>.from(webhook)),
      secret: secret,
    );
  }
}

/// Sentence-case reason [value] is not an acceptable webhook URL, or `null`
/// when it is one.
String? webhookUrlError(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'Enter the URL that receives the events.';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
    return 'Enter a full URL, such as https://example.com/hooks/alera.';
  }
  if (uri.scheme != 'https') {
    return 'Webhook URLs must use https.';
  }
  return null;
}

String? _optionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

List<String> _strings(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return List<String>.unmodifiable(<String>[
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ]);
}

// ISO-8601 strings are the contract; epoch numbers are read defensively so a
// payload change degrades to a readable date instead of a parse failure.
DateTime? _optionalDateTime(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  if (value is num) {
    final millis = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
  }
  return null;
}
