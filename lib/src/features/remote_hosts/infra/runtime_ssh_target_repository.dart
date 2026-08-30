import 'dart:async';

import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

class RuntimeSshTargetRepository(
  final RuntimeHostClient _client, {
  final Future<void> Function()? beforeAccess,
  final RuntimeSshBootstrapDefaults bootstrapDefaults =
      const RuntimeSshBootstrapDefaults.fromEnvironment(),
  RuntimeChangeCoalescer? coalescer,
}) {
  this : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeChangeCoalescer _coalescer;

  Future<List<SshTarget>> list() async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest('sshTarget.list');
    return _targetListFromPayload(payload);
  }

  Stream<List<SshTarget>> watchAll() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'sshTargetsChanged'},
      readSnapshot: list,
      coalesceKey: 'sshTargets',
      coalescer: _coalescer,
    );
  }

  Stream<SshTargetBootstrapProgress> watchBootstrapProgress() async* {
    await for (final event in _client.runtimeEvents) {
      if (event.name != 'sshTargetBootstrapProgress') {
        continue;
      }
      yield SshTargetBootstrapProgress.fromJson(event.payload);
    }
  }

  Future<SshTarget> upsert(SshTarget target) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'sshTarget.upsert',
      target.toJson(),
    );
    return SshTarget.fromJson(_mapFromPayload(payload));
  }

  Future<void> remove(String targetId) async {
    await beforeAccess?.call();
    await _client.runtimeRequest('sshTarget.remove', <String, Object?>{
      'id': targetId,
    });
  }

  Future<SshTargetBootstrapPlan> bootstrapPlan({
    required String targetId,
    String? installDir,
    String? platform,
    String? arch,
  }) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'sshTarget.bootstrap.plan',
      _bootstrapRequestPayload(
        targetId,
        installDir: installDir,
        platform: platform,
        arch: arch,
      ),
    );
    return SshTargetBootstrapPlan.fromJson(_mapFromPayload(payload));
  }

  Future<SshTargetBootstrapJob> startBootstrap({
    required String targetId,
    String? installDir,
    String? platform,
    String? arch,
  }) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'sshTarget.bootstrap.start',
      _bootstrapRequestPayload(
        targetId,
        installDir: installDir,
        platform: platform,
        arch: arch,
      ),
    );
    return SshTargetBootstrapJob.fromJson(_mapFromPayload(payload));
  }

  Future<SshTarget> cancelBootstrap(String targetId) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'sshTarget.bootstrap.cancel',
      <String, Object?>{'id': targetId},
    );
    return SshTarget.fromJson(_mapFromPayload(payload));
  }

  Map<String, Object?> _bootstrapRequestPayload(
    String targetId, {
    String? installDir,
    String? platform,
    String? arch,
  }) {
    final payload = <String, Object?>{
      'targetId': targetId,
      'installDir': installDir,
      'platform': platform,
      'arch': arch,
    };
    bootstrapDefaults.addTo(payload);
    return payload;
  }
}

final class const RuntimeSshBootstrapDefaults({
  required final String channel,
  required final String archiveUrl,
  required final String version,
}) {
  const factory fromEnvironment() = RuntimeSshBootstrapDefaultsEnvironment;

  void addTo(Map<String, Object?> payload) {
    _putIfNotEmpty(payload, 'channel', channel);
    _putIfNotEmpty(payload, 'archiveUrl', archiveUrl);
    _putIfNotEmpty(payload, 'version', version);
  }
}

final class const RuntimeSshBootstrapDefaultsEnvironment()
    extends RuntimeSshBootstrapDefaults {
  this
    : super(
        channel: const .fromEnvironment(
          'ALERA_UPDATE_CHANNEL',
          defaultValue: 'stable',
        ),
        archiveUrl: const .fromEnvironment('ALERA_RUNTIME_ARCHIVE_URL'),
        version: const .fromEnvironment('ALERA_RUNTIME_VERSION'),
      );
}

void _putIfNotEmpty(Map<String, Object?> payload, String key, String value) {
  final normalized = value.trim();
  if (normalized.isNotEmpty) {
    payload[key] = normalized;
  }
}

List<SshTarget> _targetListFromPayload(Object? payload) {
  if (payload is List) {
    return <SshTarget>[
      for (final item in payload)
        if (item is Map) SshTarget.fromJson(Map<String, Object?>.from(item)),
    ];
  }
  throw const FormatException(
    'Runtime SSH target payload must be a JSON list.',
  );
}

Map<String, Object?> _mapFromPayload(Object? payload) {
  if (payload is Map) {
    return Map<String, Object?>.from(payload);
  }
  throw const FormatException(
    'Runtime SSH target payload must be a JSON object.',
  );
}
