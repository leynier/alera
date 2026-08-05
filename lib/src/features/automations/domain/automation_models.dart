typedef JsonMap = Map<String, Object?>;

class AutomationRecord {
  const AutomationRecord({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.promptTemplate,
    required this.schedule,
    required this.target,
    required this.state,
    required this.revision,
    required this.approvedRevision,
    required this.updatedAt,
    this.projectId,
    this.tagIds = const <String>[],
    this.setupPolicy = 'wait',
    this.cleanupPolicy,
    this.overlapPolicy = 'skip',
    this.queueCap = 10,
    this.inactivityTimeoutSeconds = 7200,
    this.heartbeatIntervalSeconds = 60,
    this.misfireGraceSeconds = 900,
    this.misfirePolicy = 'skip',
    this.retryMaxAttempts = 3,
    this.retryBackoffSeconds = 60,
    this.circuitFailureThreshold = 3,
    this.circuitOpenSeconds = 900,
    this.precheck,
    this.notifyOnSuccess = false,
    this.raw = const <String, Object?>{},
  });

  factory AutomationRecord.fromJson(Object? value) {
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

  final String id;
  final String slug;
  final String name;
  final String description;
  final String promptTemplate;
  final JsonMap schedule;
  final JsonMap target;
  final String state;
  final int revision;
  final int? approvedRevision;
  final DateTime? updatedAt;
  final String? projectId;
  final List<String> tagIds;
  final String setupPolicy;
  final String? cleanupPolicy;
  final String overlapPolicy;
  final int queueCap;
  final int inactivityTimeoutSeconds;
  final int heartbeatIntervalSeconds;
  final int misfireGraceSeconds;
  final String misfirePolicy;
  final int retryMaxAttempts;
  final int retryBackoffSeconds;
  final int circuitFailureThreshold;
  final int circuitOpenSeconds;
  final JsonMap? precheck;
  final bool notifyOnSuccess;
  final JsonMap raw;

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

class AutomationRunRecord {
  const AutomationRunRecord({
    required this.id,
    required this.automationId,
    required this.number,
    required this.status,
    required this.trigger,
    required this.summary,
    required this.error,
    required this.scheduledAt,
    required this.finishedAt,
    this.targetIdentity = const <String, Object?>{},
  });

  factory AutomationRunRecord.fromJson(Object? value) {
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

  final String id;
  final String automationId;
  final int number;
  final String status;
  final String trigger;
  final String? summary;
  final String? error;
  final DateTime? scheduledAt;
  final DateTime? finishedAt;
  final JsonMap targetIdentity;
}

class AutomationDetail {
  const AutomationDetail({
    required this.automation,
    required this.runs,
    required this.audit,
    required this.occurrences,
    this.effectivePolicies = const <String, Object?>{},
  });

  factory AutomationDetail.fromJson(Object? value) {
    final map = _asMap(value);
    return AutomationDetail(
      automation: AutomationRecord.fromJson(map['automation']),
      runs: _asList(map['runs']).map(AutomationRunRecord.fromJson).toList(),
      audit: _asList(map['audit']).map(_asMap).toList(),
      occurrences: _asList(map['occurrences']).map(_asMap).toList(),
      effectivePolicies: _asMap(map['effectivePolicies']),
    );
  }

  final AutomationRecord automation;
  final List<AutomationRunRecord> runs;
  final List<JsonMap> audit;
  final List<JsonMap> occurrences;
  final JsonMap effectivePolicies;
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
