import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:logging/logging.dart';

class MobileRuntimeAutomationRepository(final MobileRuntimeClient _client) {
  final Logger _logger = Logger('MobileRuntimeAutomationRepository');

  Future<List<MobileAutomation>> list({
    bool includeTrashed = false,
    String? state,
    String? search,
    String? projectId,
    String? profileId,
    String? tag,
  }) async {
    try {
      final payload = await _client.requestMap(
        'automation.list',
        <String, Object?>{
          'includeTrashed': includeTrashed,
          'state': ?state,
          'search': ?search,
          'projectId': ?projectId,
          'profileId': ?profileId,
          'tag': ?tag,
        },
      );
      final items = payload['items'];
      if (items is! List) {
        return const <MobileAutomation>[];
      }
      return items.map(MobileAutomation.fromJson).toList(growable: false);
    } on Object catch (error, stackTrace) {
      _logger.warning('could not list automations', error, stackTrace);
      rethrow;
    }
  }

  Future<void> pause(String id, {String? activeRuns}) =>
      _requestState('automation.pause', id, activeRuns: activeRuns);

  Future<void> resume(String id) => _requestState('automation.resume', id);

  Future<void> trash(String id) => _requestState('automation.trash', id);

  Future<void> restore(String id) => _requestState('automation.restore', id);

  Future<void> runNow(
    String id, {
    required bool precheck,
    required String overlap,
    bool draftTest = false,
    int? revision,
  }) async {
    try {
      await _client.request('automation.runNow', <String, Object?>{
        'id': id,
        'precheck': precheck,
        'overlap': overlap,
        'draftTest': draftTest,
        'revision': ?revision,
      });
    } on Object catch (error, stackTrace) {
      _logger.warning('could not start automation $id', error, stackTrace);
      rethrow;
    }
  }

  Future<MobileAutomationDetail> show(String id) async {
    final payload = await _client.requestMap(
      'automation.show',
      <String, Object?>{'id': id},
    );
    return MobileAutomationDetail.fromJson(payload);
  }

  Future<MobileAutomation> upsert(Map<String, Object?> definition) async {
    final payload = await _client.requestMap(
      'automation.upsert',
      <String, Object?>{'automation': definition},
    );
    return MobileAutomation.fromJson(payload);
  }

  Future<void> approve(String id, int revision) async {
    await _client.request('automation.approve', <String, Object?>{
      'id': id,
      'revision': revision,
    });
  }

  Future<void> cancel(String runId, Map<String, Object?> targetIdentity) async {
    await _client.request('automation.cancel', <String, Object?>{
      'run': runId,
      'targetIdentity': targetIdentity,
    });
  }

  Future<Map<String, Object?>> policy({
    required String kind,
    String? profileId,
    String? projectId,
    Map<String, Object?>? value,
  }) async {
    return _client.requestMap('automation.policy', <String, Object?>{
      'kind': kind,
      'profileId': ?profileId,
      'projectId': ?projectId,
      'policy': ?value,
    });
  }

  Future<List<Map<String, Object?>>> templates() async {
    final payload = await _client.requestMap('automation.templates');
    return _maps(payload['items']);
  }

  Future<Map<String, Object?>> saveTemplate(
    Map<String, Object?> template,
  ) async {
    return _client.requestMap('automation.templates', <String, Object?>{
      'template': template,
    });
  }

  Future<List<Map<String, Object?>>> tags() async {
    final payload = await _client.requestMap('automation.tags');
    return _maps(payload['items']);
  }

  Future<Map<String, Object?>> saveTag(String name) async {
    return _client.requestMap('automation.tags', <String, Object?>{
      'tag': <String, Object?>{
        'id': 'mobile-tag-${DateTime.now().microsecondsSinceEpoch}',
        'name': name.trim(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    });
  }

  Future<void> setTags(String automationId, List<String> tagIds) async {
    await _client.request('automation.tags', <String, Object?>{
      'automationId': automationId,
      'tagIds': tagIds,
    });
  }

  Future<Map<String, Object?>> wait(
    String runId,
    Map<String, Object?> targetIdentity, {
    required bool waiting,
  }) async {
    return _client.requestMap('automation.wait', <String, Object?>{
      'run': runId,
      'targetIdentity': targetIdentity,
      'waiting': waiting,
    });
  }

  Future<Map<String, Object?>> extend(
    String runId,
    Map<String, Object?> targetIdentity, {
    int? seconds,
    String? until,
  }) async {
    return _client.requestMap('automation.extend', <String, Object?>{
      'run': runId,
      'targetIdentity': targetIdentity,
      'seconds': ?seconds,
      'until': ?until,
    });
  }

  Future<Map<String, Object?>> exportCatalog() async {
    return _client.requestMap('automation.export');
  }

  Future<void> importCatalog(
    Map<String, Object?> bundle,
    Map<String, String> remap,
  ) async {
    await _client.request('automation.import', <String, Object?>{
      'bundle': bundle,
      'remap': remap,
    });
  }

  Future<void> _requestState(
    String request,
    String id, {
    String? activeRuns,
  }) async {
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

  List<Map<String, Object?>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map(
              (item) => <String, Object?>{
                for (final entry in item.entries)
                  if (entry.key is String) entry.key as String: entry.value,
              },
            )
            .toList(growable: false)
      : const <Map<String, Object?>>[];
}
