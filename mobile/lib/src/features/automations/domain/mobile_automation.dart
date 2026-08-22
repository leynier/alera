class MobileAutomation {
  const MobileAutomation({
    required this.id,
    required this.name,
    required this.slug,
    required this.state,
    required this.revision,
    required this.approvedRevision,
    required this.schedule,
    required this.target,
    this.description = '',
    this.projectId,
    this.tagIds = const <String>[],
    this.promptTemplate = '',
    this.raw = const <String, Object?>{},
  });

  factory MobileAutomation.fromJson(Object? value) {
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

  final String id;
  final String name;
  final String slug;
  final String state;
  final int revision;
  final int? approvedRevision;
  final Map<String, Object?> schedule;
  final Map<String, Object?> target;
  final String description;
  final String? projectId;
  final List<String> tagIds;
  final String promptTemplate;
  final Map<String, Object?> raw;

  int get heartbeatIntervalSeconds {
    final value = _int(raw['heartbeatIntervalSeconds']);
    return value > 0 ? value : 60;
  }

  bool get isApproved => revision == approvedRevision;
}

class MobileAutomationDetail {
  const MobileAutomationDetail({
    required this.automation,
    required this.runs,
    required this.audit,
    required this.occurrences,
    required this.effectivePolicies,
  });

  factory MobileAutomationDetail.fromJson(Object? value) {
    final map = _map(value);
    return MobileAutomationDetail(
      automation: MobileAutomation.fromJson(map['automation']),
      runs: _list(map['runs']).map(_map).toList(growable: false),
      audit: _list(map['audit']).map(_map).toList(growable: false),
      occurrences: _list(map['occurrences']).map(_map).toList(growable: false),
      effectivePolicies: _map(map['effectivePolicies']),
    );
  }

  final MobileAutomation automation;
  final List<Map<String, Object?>> runs;
  final List<Map<String, Object?>> audit;
  final List<Map<String, Object?>> occurrences;
  final Map<String, Object?> effectivePolicies;
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
