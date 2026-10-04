import 'package:alera_mobile/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:logging/logging.dart';

const String automationsAuthoringCapability = 'automationsAuthoringV1';
const String automationTerminalObserveCapability =
    'automationTerminalObserveV1';

/// Runtime events that change what the catalog or a detail shows. The
/// runtime sends them to every authenticated client, phones included.
const Set<String> automationCatalogEvents = <String>{
  'automationsChanged',
  'automationRunChanged',
  'automationAttentionRequired',
};

class const AutomationReadinessException(final AutomationReadiness readiness)
    implements Exception {
  @override
  String toString() => readiness.errors.isEmpty
      ? 'The automation is not ready.'
      : readiness.errors.map((issue) => issue.message).join(' ');
}

class MobileRuntimeAutomationRepository(final MobileAutomationClient _client) {
  final Logger _logger = Logger('MobileRuntimeAutomationRepository');

  Stream<MobileRuntimeEvent> get events => _client.events.where(
    (event) => automationCatalogEvents.contains(event.name),
  );

  bool get supportsAuthoring =>
      _client.runtimeCapabilities.contains(automationsAuthoringCapability);

  bool get supportsObserve =>
      _client.runtimeCapabilities.contains(automationTerminalObserveCapability);

  Future<List<AutomationRecord>> list() async {
    try {
      final payload = await _client.requestMap(
        'automation.list',
        <String, Object?>{'includeTrashed': true},
      );
      return automationJsonList(payload['items'])
          .map(AutomationRecord.fromJson)
          .toList(growable: false);
    } on Object catch (error, stackTrace) {
      _logger.warning('could not list automations', error, stackTrace);
      rethrow;
    }
  }

  Future<AutomationDetail> show(String id) async {
    final payload = await _client.requestMap(
      'automation.show',
      <String, Object?>{'id': id},
    );
    return AutomationDetail.fromJson(payload);
  }

  Future<List<AutomationRunRecord>> recentRuns({int limit = 100}) async {
    final payload = await _client.request('automation.runs', <String, Object?>{
      'limit': limit,
    });
    final items = payload is List
        ? payload
        : automationJsonList(automationJsonMap(payload)['items']);
    return items.map(AutomationRunRecord.fromJson).toList(growable: false);
  }

  Future<AutomationRecord> create(
    JsonMap definition, {
    String? requestKey,
  }) async {
    if (supportsAuthoring) {
      final payload = await _validated(
        () => _client.request('automation.create', <String, Object?>{
          'automation': definition,
          'requestKey': ?requestKey,
        }),
      );
      return AutomationRecord.fromJson(_automationOf(payload));
    }
    final payload = await _client.requestMap(
      'automation.upsert',
      <String, Object?>{
        'automation': mobileLegacyAutomationDefinition(definition),
      },
    );
    return AutomationRecord.fromJson(payload);
  }

  Future<AutomationRecord> patch(
    AutomationRecord current,
    JsonMap changes,
  ) async {
    if (supportsAuthoring) {
      final payload = await _validated(
        () => _client.request('automation.patch', <String, Object?>{
          'id': current.id,
          'changes': changes,
          'expectedRevision': current.revision,
        }),
      );
      return AutomationRecord.fromJson(_automationOf(payload));
    }
    final payload = await _client.requestMap(
      'automation.upsert',
      <String, Object?>{
        'automation': mobileLegacyAutomationDefinition(<String, Object?>{
          ...current.raw,
          ...changes,
        }),
      },
    );
    return AutomationRecord.fromJson(payload);
  }

  Future<AutomationReadiness?> readiness(JsonMap draft) async {
    if (!supportsAuthoring) return null;
    final payload = await _client.request(
      'automation.readiness',
      <String, Object?>{'automation': draft},
    );
    return AutomationReadiness.fromJson(payload);
  }

  Future<AutomationReadiness?> previewSchedule(JsonMap schedule) async {
    if (!supportsAuthoring) return null;
    final payload = await _client.requestMap(
      'automation.previewSchedule',
      <String, Object?>{'schedule': schedule, 'count': 3},
    );
    return AutomationReadiness.fromJson(<String, Object?>{
      ...payload,
      'ready': true,
    });
  }

  Future<void> pause(String id, {bool cancelRuns = false}) => _state(
    'automation.pause',
    id,
    activeRuns: cancelRuns ? 'cancel-active' : 'continue-active',
  );

  Future<void> resume(String id) => _state('automation.resume', id);

  Future<void> trash(String id) => _state('automation.trash', id);

  Future<void> restore(String id) => _state('automation.restore', id);

  /// `automation.approve` is the activation verb every runtime understands;
  /// it no longer gates anything.
  Future<void> activate(AutomationRecord automation) => _client.request(
    'automation.approve',
    <String, Object?>{'id': automation.id, 'revision': automation.revision},
  );

  Future<AutomationRunRecord> runNow(
    String id, {
    bool? precheck,
    String? overlap,
    String? continueFromRunId,
  }) async {
    try {
      final payload = await _client.request(
        'automation.runNow',
        <String, Object?>{
          'id': id,
          'precheck': ?precheck,
          'overlap': ?overlap,
          'continueFromRunId': ?continueFromRunId,
        },
      );
      return AutomationRunRecord.fromJson(payload);
    } on Object catch (error, stackTrace) {
      _logger.warning('could not start automation $id', error, stackTrace);
      rethrow;
    }
  }

  Future<void> cancel(AutomationRunRecord run) => _client.request(
    'automation.cancel',
    <String, Object?>{'run': run.id, 'targetIdentity': run.targetIdentity},
  );

  Future<void> resumeWaiting(AutomationRunRecord run) =>
      _client.request('automation.wait', <String, Object?>{
        'run': run.id,
        'targetIdentity': run.targetIdentity,
        'waiting': false,
      });

  Future<void> extendWaiting(AutomationRunRecord run) =>
      _client.request('automation.extend', <String, Object?>{
        'run': run.id,
        'targetIdentity': run.targetIdentity,
        'seconds': 3600,
      });

  Future<void> takeOver(String runId) =>
      _client.request('automation.takeOver', <String, Object?>{'runId': runId});

  Future<List<JsonMap>> templates() async {
    final payload = await _client.requestMap('automation.templates');
    return automationJsonList(payload['items'])
        .map(automationJsonMap)
        .toList(growable: false);
  }

  Future<JsonMap> exportCatalog() => _client.requestMap('automation.export');

  Future<void> importCatalog(JsonMap bundle, Map<String, String> remap) =>
      _client.request('automation.import', <String, Object?>{
        'bundle': bundle,
        'remap': remap,
      });

  Future<void> _state(String request, String id, {String? activeRuns}) async {
    try {
      await _client.request(request, <String, Object?>{
        'id': id,
        'activeRuns': ?activeRuns,
      });
    } on Object catch (error, stackTrace) {
      _logger.warning('could not update automation $id', error, stackTrace);
      rethrow;
    }
  }

  Future<Object?> _validated(Future<Object?> Function() request) async {
    final payload = await request();
    final map = automationJsonMap(payload);
    final readiness = map['readiness'];
    if (map['automation'] == null && readiness is Map) {
      final parsed = AutomationReadiness.fromJson(readiness);
      if (!parsed.ready) throw AutomationReadinessException(parsed);
    }
    return payload;
  }

  Object? _automationOf(Object? payload) {
    final map = automationJsonMap(payload);
    return map['automation'] is Map ? map['automation'] : payload;
  }
}

/// Fills what an older runtime's `automation.upsert` requires.
JsonMap mobileLegacyAutomationDefinition(JsonMap partial) {
  final now = DateTime.now().toUtc().toIso8601String();
  final name = automationJsonString(partial['name']);
  final id =
      automationJsonOptionalString(partial['id']) ??
      'mobile-${DateTime.now().microsecondsSinceEpoch}';
  final slug =
      automationJsonOptionalString(partial['slug']) ??
      name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
  const actor = <String, Object?>{'kind': 'authenticatedMobile'};
  return <String, Object?>{
    ...partial,
    'id': id,
    'slug': slug.isEmpty ? id : slug,
    'state': automationJsonOptionalString(partial['state']) ?? 'active',
    'revision': automationJsonInt(partial['revision']),
    'createdBy': partial['createdBy'] ?? actor,
    'modifiedBy': actor,
    'createdAt': partial['createdAt'] ?? now,
    'updatedAt': now,
  };
}
