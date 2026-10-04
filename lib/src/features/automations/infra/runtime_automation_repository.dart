import 'dart:async';

import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

const String automationsAuthoringCapability = 'automationsAuthoringV1';
const String automationTerminalObserveCapability =
    aleraRuntimeHostAutomationTerminalObserveCapability;

/// Runtime events that change what the catalog or a detail shows.
const Set<String> automationCatalogEvents = <String>{
  'automationsChanged',
  'automationRunChanged',
  'automationAttentionRequired',
  aleraRuntimeHostConnectedEvent,
};

/// Thrown when the runtime rejects a definition with structured readiness.
class const AutomationReadinessException(final AutomationReadiness readiness)
    implements Exception {
  @override
  String toString() => readiness.errors.isEmpty
      ? 'The automation is not ready.'
      : readiness.errors.map((issue) => issue.message).join(' ');
}

class RuntimeAutomationRepository(final RuntimeHostClient _client) {
  Stream<RuntimeHostEvent> get events => _client.runtimeEvents.where(
    (event) => automationCatalogEvents.contains(event.name),
  );

  Future<bool> supports(String capability) async {
    if (_client case final RuntimeHostCapabilityClient capable) {
      try {
        return await capable.supportsRuntimeCapability(capability);
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<List<AutomationRecord>> list({bool includeTrashed = true}) async {
    final payload = await _client.runtimeRequest(
      'automation.list',
      <String, Object?>{'includeTrashed': includeTrashed},
    );
    return automationJsonList(automationJsonMap(payload)['items'])
        .map(AutomationRecord.fromJson)
        .toList(growable: false);
  }

  Future<AutomationDetail> show(String id) async {
    final payload = await _client.runtimeRequest(
      'automation.show',
      <String, Object?>{'id': id},
    );
    return AutomationDetail.fromJson(payload);
  }

  Future<List<AutomationRunRecord>> recentRuns({int limit = 100}) async {
    final payload = await _client.runtimeRequest(
      'automation.runs',
      <String, Object?>{'limit': limit},
    );
    final map = automationJsonMap(payload);
    final items = payload is List ? payload : automationJsonList(map['items']);
    return items.map(AutomationRunRecord.fromJson).toList(growable: false);
  }

  /// Creates through the additive authoring RPC, or through the legacy upsert
  /// with a complete definition when the runtime predates it.
  Future<AutomationRecord> create(
    JsonMap definition, {
    required bool authoring,
    String? requestKey,
  }) async {
    if (authoring) {
      final payload = await _validated(
        () => _client.runtimeRequest('automation.create', <String, Object?>{
          'automation': definition,
          'requestKey': ?requestKey,
        }),
      );
      return AutomationRecord.fromJson(_automationOf(payload));
    }
    final payload = await _client.runtimeRequest(
      'automation.upsert',
      <String, Object?>{'automation': legacyAutomationDefinition(definition)},
    );
    return AutomationRecord.fromJson(payload);
  }

  Future<AutomationRecord> patch(
    AutomationRecord current,
    JsonMap changes, {
    required bool authoring,
  }) async {
    if (authoring) {
      final payload = await _validated(
        () => _client.runtimeRequest('automation.patch', <String, Object?>{
          'id': current.id,
          'changes': changes,
          'expectedRevision': current.revision,
        }),
      );
      return AutomationRecord.fromJson(_automationOf(payload));
    }
    final payload = await _client.runtimeRequest(
      'automation.upsert',
      <String, Object?>{
        'automation': legacyAutomationDefinition(<String, Object?>{
          ...current.raw,
          ...changes,
        }),
      },
    );
    return AutomationRecord.fromJson(payload);
  }

  Future<AutomationReadiness> readiness({JsonMap? draft, String? id}) async {
    final payload = await _client.runtimeRequest(
      'automation.readiness',
      <String, Object?>{'automation': ?draft, 'id': ?id},
    );
    return AutomationReadiness.fromJson(payload);
  }

  Future<AutomationReadiness> previewSchedule(
    JsonMap schedule, {
    int count = 3,
  }) async {
    final payload = await _client.runtimeRequest(
      'automation.previewSchedule',
      <String, Object?>{'schedule': schedule, 'count': count},
    );
    return AutomationReadiness.fromJson(<String, Object?>{
      ...automationJsonMap(payload),
      'ready': true,
    });
  }

  Future<AutomationRecord> setState(
    String request,
    String id, {
    String? activeRuns,
  }) async {
    final payload = await _client.runtimeRequest(request, <String, Object?>{
      'id': id,
      'activeRuns': ?activeRuns,
    });
    return AutomationRecord.fromJson(payload);
  }

  Future<AutomationRecord> activate(AutomationRecord automation) async {
    final payload = await _client.runtimeRequest(
      'automation.approve',
      <String, Object?>{'id': automation.id, 'revision': automation.revision},
    );
    return AutomationRecord.fromJson(payload);
  }

  /// Manual runs use the definition's own precheck and overlap policy unless
  /// the caller overrides them.
  Future<AutomationRunRecord> runNow(
    String id, {
    bool? precheck,
    String? overlap,
    String? continueFromRunId,
  }) async {
    final payload = await _client.runtimeRequest(
      'automation.runNow',
      <String, Object?>{
        'id': id,
        'precheck': ?precheck,
        'overlap': ?overlap,
        'continueFromRunId': ?continueFromRunId,
      },
    );
    return AutomationRunRecord.fromJson(payload);
  }

  Future<void> cancel(AutomationRunRecord run) async {
    await _client.runtimeRequest('automation.cancel', <String, Object?>{
      'run': run.id,
      'targetIdentity': run.targetIdentity,
    });
  }

  Future<void> resumeWaiting(AutomationRunRecord run) async {
    await _client.runtimeRequest('automation.wait', <String, Object?>{
      'run': run.id,
      'targetIdentity': run.targetIdentity,
      'waiting': false,
    });
  }

  Future<void> extendWaiting(
    AutomationRunRecord run, {
    int seconds = 3600,
  }) async {
    await _client.runtimeRequest('automation.extend', <String, Object?>{
      'run': run.id,
      'targetIdentity': run.targetIdentity,
      'seconds': seconds,
    });
  }

  Future<void> takeOver(String runId) async {
    await _client.runtimeRequest('automation.takeOver', <String, Object?>{
      'runId': runId,
    });
  }

  Future<List<JsonMap>> templates() async {
    final payload = await _client.runtimeRequest('automation.templates');
    return automationJsonList(automationJsonMap(payload)['items'])
        .map(automationJsonMap)
        .toList(growable: false);
  }

  Future<JsonMap> saveTemplate(JsonMap template) async {
    final payload = await _client.runtimeRequest(
      'automation.templates',
      <String, Object?>{'template': template},
    );
    return automationJsonMap(payload);
  }

  Future<List<JsonMap>> tags() async {
    final payload = await _client.runtimeRequest('automation.tags');
    return automationJsonList(automationJsonMap(payload)['items'])
        .map(automationJsonMap)
        .toList(growable: false);
  }

  Future<JsonMap> exportCatalog() async {
    final payload = await _client.runtimeRequest('automation.export');
    return automationJsonMap(payload);
  }

  Future<void> importCatalog(JsonMap bundle, Map<String, String> remap) async {
    await _client.runtimeRequest('automation.import', <String, Object?>{
      'bundle': bundle,
      'remap': remap,
    });
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

/// Fills what an older runtime's `automation.upsert` requires and the
/// authoring RPC would derive: identity, slug, lifecycle and actors.
JsonMap legacyAutomationDefinition(JsonMap partial) {
  final now = DateTime.now().toUtc().toIso8601String();
  final name = automationJsonString(partial['name']);
  final id =
      automationJsonOptionalString(partial['id']) ??
      'automation-${DateTime.now().microsecondsSinceEpoch}';
  final slug =
      automationJsonOptionalString(partial['slug']) ??
      automationSlug(name.isEmpty ? id : name);
  final actor = <String, Object?>{'kind': 'humanDesktop'};
  return <String, Object?>{
    ...partial,
    'id': id,
    'slug': slug,
    'state': automationJsonOptionalString(partial['state']) ?? 'active',
    'revision': automationJsonInt(partial['revision']),
    'createdBy': partial['createdBy'] ?? actor,
    'modifiedBy': actor,
    'createdAt': partial['createdAt'] ?? now,
    'updatedAt': now,
  };
}

String automationSlug(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'automation' : slug;
}
