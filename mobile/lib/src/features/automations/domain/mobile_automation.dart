class const MobileAutomation({
  required final String id,
  required final String name,
  required final String slug,
  required final String state,
  required final int revision,
  required final int? approvedRevision,
  required final Map<String, Object?> schedule,
  required final Map<String, Object?> target,
  final String description = '',
  final String? projectId,
  final List<String> tagIds = const <String>[],
  final String promptTemplate = '',
  final Map<String, Object?> raw = const <String, Object?>{},
}) {
  factory fromJson(Object? value) {
    final map = _map(value);
    return MobileAutomation(
      id: _string(map['id']),
      name: _string(map['name']),
      slug: _string(map['slug']),
      state: _string(map['state']),
      revision: _int(map['revision']),
      approvedRevision: map['approvedRevision'] == null
          ? null
          : _int(map['approvedRevision']),
      schedule: _map(map['schedule']),
      target: _map(map['target']),
      description: _string(map['description']),
      projectId: _string(map['projectId']).isEmpty
          ? null
          : _string(map['projectId']),
      tagIds: _strings(map['tagIds']),
      promptTemplate: _string(map['promptTemplate']),
      raw: map,
    );
  }

  int get heartbeatIntervalSeconds {
    final value = _int(raw['heartbeatIntervalSeconds']);
    return value > 0 ? value : 60;
  }

  bool get isApproved => revision == approvedRevision;
}

class const MobileAutomationDetail({
  required final MobileAutomation automation,
  required final List<Map<String, Object?>> runs,
  required final List<Map<String, Object?>> audit,
  required final List<Map<String, Object?>> occurrences,
  required final Map<String, Object?> effectivePolicies,
}) {
  factory fromJson(Object? value) {
    final map = _map(value);
    return MobileAutomationDetail(
      automation: .fromJson(map['automation']),
      runs: _list(map['runs']).map(_map).toList(growable: false),
      audit: _list(map['audit']).map(_map).toList(growable: false),
      occurrences: _list(map['occurrences']).map(_map).toList(growable: false),
      effectivePolicies: _map(map['effectivePolicies']),
    );
  }
}

Map<String, Object?> _map(Object? value) => value is Map
    ? <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : <String, Object?>{};

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';

int _int(Object? value) =>
    value is int ? value : int.tryParse(_string(value)) ?? 0;

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];
