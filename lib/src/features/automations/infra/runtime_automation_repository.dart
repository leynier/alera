import 'dart:async';

import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeAutomationRepository {
  RuntimeAutomationRepository(this._client);

  final RuntimeHostClient _client;

  Future<List<AutomationRecord>> list({
    bool includeTrashed = false,
    String? state,
    String? projectId,
    String? profileId,
    String? tag,
    String? search,
  }) async {
    final payload = await _client
        .runtimeRequest('automation.list', <String, Object?>{
          'includeTrashed': includeTrashed,
          'state': ?state,
          'projectId': ?projectId,
          'profileId': ?profileId,
          'tag': ?tag,
          'search': ?search,
        });
    final map = _map(payload);
    return _list(
      map['items'],
    ).map(AutomationRecord.fromJson).toList(growable: false);
  }

  Stream<List<AutomationRecord>> watch() async* {
    yield await list();
    await for (final event in _client.runtimeEvents) {
      if (event.name == 'automationsChanged' ||
          event.name == 'automationRunChanged') {
        yield await list();
      }
    }
  }

  Future<AutomationDetail> show(String id) async {
    final payload = await _client.runtimeRequest(
      'automation.show',
      <String, Object?>{'id': id},
    );
    return AutomationDetail.fromJson(payload);
  }

  Future<AutomationRecord> upsert(JsonMap definition) async {
    final payload = await _client.runtimeRequest(
      'automation.upsert',
      <String, Object?>{'automation': definition},
    );
    return AutomationRecord.fromJson(payload);
  }

  Future<AutomationRecord> setState(
    String request,
    String id, {
    String? reason,
    String? activeRuns,
  }) async {
    final payload = await _client.runtimeRequest(request, <String, Object?>{
      'id': id,
      'reason': reason,
      'activeRuns': ?activeRuns,
    });
    return AutomationRecord.fromJson(payload);
  }

  Future<AutomationRecord> approve(String id, int revision) async {
    final payload = await _client.runtimeRequest(
      'automation.approve',
      <String, Object?>{'id': id, 'revision': revision},
    );
    return AutomationRecord.fromJson(payload);
  }

  Future<AutomationRunRecord> runNow(
    String id, {
    required bool runPrecheck,
    required String overlap,
    bool draftTest = false,
    int? revision,
  }) async {
    final payload = await _client
        .runtimeRequest('automation.runNow', <String, Object?>{
          'id': id,
          'precheck': runPrecheck,
          'overlap': overlap,
          'draftTest': draftTest,
          'revision': ?revision,
        });
    return AutomationRunRecord.fromJson(payload);
  }

  Future<void> cancel(String runId, JsonMap targetIdentity) async {
    await _client.runtimeRequest('automation.cancel', <String, Object?>{
      'run': runId,
      'targetIdentity': targetIdentity,
    });
  }

  Future<void> setWaiting(
    String runId,
    JsonMap targetIdentity, {
    required bool waiting,
  }) async {
    await _client.runtimeRequest('automation.wait', <String, Object?>{
      'run': runId,
      'targetIdentity': targetIdentity,
      'waiting': waiting,
    });
  }

  Future<void> extendWaiting(
    String runId,
    JsonMap targetIdentity, {
    int seconds = 3600,
  }) async {
    await _client.runtimeRequest('automation.extend', <String, Object?>{
      'run': runId,
      'targetIdentity': targetIdentity,
      'seconds': seconds,
    });
  }

  Future<Map<String, Object?>> policy({
    String? profileId,
    String? projectId,
  }) async {
    final payload = await _client.runtimeRequest(
      'automation.policy',
      <String, Object?>{
        'kind': 'show',
        'profileId': ?profileId,
        'projectId': ?projectId,
      },
    );
    return _map(payload);
  }

  Future<List<JsonMap>> templates() async {
    final payload = await _client.runtimeRequest('automation.templates');
    return _list(_map(payload)['items']).map(_map).toList(growable: false);
  }

  Future<List<JsonMap>> tags() async {
    final payload = await _client.runtimeRequest('automation.tags');
    return _list(_map(payload)['items']).map(_map).toList(growable: false);
  }

  Future<JsonMap> exportCatalog() async {
    final payload = await _client.runtimeRequest('automation.export');
    return _map(payload);
  }

  Future<List<AutomationRecord>> importCatalog(
    JsonMap bundle,
    Map<String, String> remap,
  ) async {
    final payload = await _client.runtimeRequest(
      'automation.import',
      <String, Object?>{'bundle': bundle, 'remap': remap},
    );
    return _list(
      _map(payload)['items'],
    ).map(AutomationRecord.fromJson).toList(growable: false);
  }
}

JsonMap _map(Object? value) => value is Map
    ? <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : <String, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];
