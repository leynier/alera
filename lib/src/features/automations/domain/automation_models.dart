typedef JsonMap = Map<String, Object?>;

class const AutomationRecord({
  required final String id,
  required final String slug,
  required final String name,
  required final String description,
  required final String promptTemplate,
  required final JsonMap schedule,
  required final JsonMap target,
  required final String state,
  required final int revision,
  required final int? approvedRevision,
  required final DateTime? updatedAt,
  final String? projectId,
  final List<String> tagIds = const <String>[],
  final String setupPolicy = 'wait',
  final String? cleanupPolicy,
  final String overlapPolicy = 'skip',
  final int queueCap = 10,
  final int inactivityTimeoutSeconds = 7200,
  final int heartbeatIntervalSeconds = 60,
  final int misfireGraceSeconds = 900,
  final String misfirePolicy = 'skip',
  final int retryMaxAttempts = 3,
  final int retryBackoffSeconds = 60,
  final int circuitFailureThreshold = 3,
  final int circuitOpenSeconds = 900,
  final JsonMap? precheck,
  final bool notifyOnSuccess = false,
  final JsonMap raw = const <String, Object?>{},
}) {
  factory fromJson(Object? value) {
    final map = _asMap(value);
    final record = AutomationRecord(
      id: _string(map['id']),
      slug: _string(map['slug']),
      name: _string(map['name']),
      description: _string(map['description']),
      promptTemplate: _string(map['promptTemplate']),
      schedule: _asMap(map['schedule']),
      target: _asMap(map['target']),
      state: _string(map['state']).isEmpty ? 'draft' : _string(map['state']),
      revision: _int(map['revision']),
      approvedRevision: _nullableInt(map['approvedRevision']),
      updatedAt: DateTime.tryParse(_string(map['updatedAt'])),
      projectId: _nullableString(map['projectId']),
      tagIds: _asStringList(map['tagIds']),
      setupPolicy: _string(map['setupPolicy']).isEmpty
          ? 'wait'
          : _string(map['setupPolicy']),
      cleanupPolicy: _nullableString(map['cleanupPolicy']),
      overlapPolicy: _string(map['overlapPolicy']).isEmpty
          ? 'skip'
          : _string(map['overlapPolicy']),
      queueCap: _intOr(map['queueCap'], 10),
      inactivityTimeoutSeconds: _intOr(map['inactivityTimeoutSeconds'], 7200),
      heartbeatIntervalSeconds: _intOr(map['heartbeatIntervalSeconds'], 60),
      misfireGraceSeconds: _intOr(map['misfireGraceSeconds'], 900),
      misfirePolicy: _string(map['misfirePolicy']).isEmpty
          ? 'skip'
          : _string(map['misfirePolicy']),
      retryMaxAttempts: _intOr(map['retryMaxAttempts'], 3),
      retryBackoffSeconds: _intOr(map['retryBackoffSeconds'], 60),
      circuitFailureThreshold: _intOr(map['circuitFailureThreshold'], 3),
      circuitOpenSeconds: _intOr(map['circuitOpenSeconds'], 900),
      precheck: map['precheck'] is Map ? _asMap(map['precheck']) : null,
      notifyOnSuccess: map['notifyOnSuccess'] == true,
      raw: map,
    );
    return record;
  }

  bool get isApproved => approvedRevision == revision;

  String get scheduleKind {
    if (schedule.containsKey('recurring') || schedule.containsKey('cron')) {
      return 'Recurring';
    }
    return 'One-time';
  }

  String get targetKind {
    if (target.containsKey('existingTab')) {
      return 'Existing tab';
    }
    if (target.containsKey('freshTab')) {
      return 'Fresh tab';
    }
    return target['type']?.toString() ?? 'Managed workspace';
  }
}

class const AutomationRunRecord({
  required final String id,
  required final String automationId,
  required final int number,
  required final String status,
  required final String trigger,
  required final String? summary,
  required final String? error,
  required final DateTime? scheduledAt,
  required final DateTime? finishedAt,
  final JsonMap targetIdentity = const <String, Object?>{},
}) {
  factory fromJson(Object? value) {
    final map = _asMap(value);
    return AutomationRunRecord(
      id: _string(map['id']),
      automationId: _string(map['automationId']),
      number: _int(map['number']),
      status: _string(map['status']),
      trigger: _string(map['trigger']),
      summary: _nullableString(map['summary']),
      error: _nullableString(map['error']),
      scheduledAt: DateTime.tryParse(_string(map['scheduledAt'])),
      finishedAt: DateTime.tryParse(_string(map['finishedAt'])),
      targetIdentity: _asMap(map['targetIdentity']),
    );
  }
}

class const AutomationDetail({
  required final AutomationRecord automation,
  required final List<AutomationRunRecord> runs,
  required final List<JsonMap> audit,
  required final List<JsonMap> occurrences,
  final JsonMap effectivePolicies = const <String, Object?>{},
}) {
  factory fromJson(Object? value) {
    final map = _asMap(value);
    return AutomationDetail(
      automation: .fromJson(map['automation']),
      runs: _asList(map['runs']).map(AutomationRunRecord.fromJson).toList(),
      audit: _asList(map['audit']).map(_asMap).toList(),
      occurrences: _asList(map['occurrences']).map(_asMap).toList(),
      effectivePolicies: _asMap(map['effectivePolicies']),
    );
  }
}

JsonMap _asMap(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return <String, Object?>{};
}

List<Object?> _asList(Object? value) =>
    value is List ? value : const <Object?>[];

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';

String? _nullableString(Object? value) {
  final result = _string(value);
  return result.isEmpty ? null : result;
}

int _int(Object? value) =>
    value is int ? value : int.tryParse(_string(value)) ?? 0;

int _intOr(Object? value, int fallback) {
  final parsed = int.tryParse(_string(value));
  return parsed ?? fallback;
}

int? _nullableInt(Object? value) =>
    value == null ? null : int.tryParse(_string(value));

List<String> _asStringList(Object? value) => value is List
    ? value.whereType<String>().where((item) => item.trim().isNotEmpty).toList()
    : const <String>[];
