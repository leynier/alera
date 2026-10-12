import 'dart:async';

import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_check_result.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_in_use_exception.dart';
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

  /// Throws [SshTargetInUseException] while the host still has workspaces or
  /// project checkouts.
  Future<void> remove(String targetId) async {
    await beforeAccess?.call();
    await _request('sshTarget.remove', <String, Object?>{'id': targetId});
  }

  /// Probes [targetId] over ssh (`sshTarget.check`), which also persists the
  /// result and nudges a wanted host to connect.
  Future<RemoteHostCheckResult> checkReachability(String targetId) async {
    await beforeAccess?.call();
    final payload = await _request('sshTarget.check', <String, Object?>{
      'id': targetId,
    });
    final targets = _mapFromPayload(payload)['targets'];
    if (targets is List) {
      for (final item in targets) {
        if (item is Map) {
          final target = SshTarget.fromJson(Map<String, Object?>.from(item));
          if (target.id == targetId) {
            return RemoteHostCheckResult(target: target);
          }
        }
      }
    }
    throw FormatException('sshTarget.check did not report $targetId.');
  }

  /// Reinstalls the runtime on [targetId] and restarts it onto the new
  /// version. Throws [HostBusyException] while terminals are open there,
  /// unless [force] closes them.
  Future<SshTargetBootstrapJob> updateRuntime(
    String targetId, {
    bool force = false,
  }) async {
    await beforeAccess?.call();
    final payload = await _request(
      'sshTarget.bootstrap.start',
      <String, Object?>{
        ..._bootstrapRequestPayload(targetId),
        'restartRuntime': true,
        'force': force,
      },
    );
    return SshTargetBootstrapJob.fromJson(_mapFromPayload(payload));
  }

  /// Restarts the runtime already installed on [targetId] without
  /// reinstalling it. Throws [HostBusyException] like [updateRuntime].
  Future<void> restartRuntime(String targetId, {bool force = false}) async {
    await beforeAccess?.call();
    await _request('sshTarget.restartRuntime', <String, Object?>{
      'id': targetId,
      'force': force,
    });
  }

  /// Installs the runtime is running now, so a restarted app can show the
  /// progress of a job it did not start.
  Future<List<SshTargetBootstrapJob>> listBootstrapJobs() async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest('sshTarget.bootstrap.jobs');
    if (payload is! List) {
      return const <SshTargetBootstrapJob>[];
    }
    return <SshTargetBootstrapJob>[
      for (final item in payload)
        if (item is Map)
          SshTargetBootstrapJob.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  Future<bool> supportsCapability(String capability) async {
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          capability,
        );
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
    final payload = await _request(
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

  Future<bool> supportsHostLinks() =>
      supportsCapability(aleraRuntimeHostRemoteHostLinkCapability);

  /// Link states for every host the hub has tried. Empty on a host without
  /// [aleraRuntimeHostRemoteHostLinkCapability].
  Future<List<HostLinkState>> hostLinks() async {
    await beforeAccess?.call();
    if (!await supportsHostLinks()) {
      return const <HostLinkState>[];
    }
    final payload = await _client.runtimeRequest('hostLink.status');
    final links = _mapFromPayload(payload)['links'];
    if (links is! List) {
      return const <HostLinkState>[];
    }
    return <HostLinkState>[
      for (final item in links)
        if (item is Map)
          HostLinkState.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  Stream<List<HostLinkState>> watchHostLinks() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'hostLinkChanged'},
      readSnapshot: hostLinks,
      coalesceKey: 'hostLinks',
      coalescer: _coalescer,
    );
  }

  Future<HostLinkState> connectHostLink(String hostId) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'hostLink.connect',
      <String, Object?>{'hostId': hostId},
    );
    return HostLinkState.fromJson(_mapFromPayload(payload));
  }

  Future<HostLinkState> disconnectHostLink(String hostId) async {
    await beforeAccess?.call();
    final payload = await _client.runtimeRequest(
      'hostLink.disconnect',
      <String, Object?>{'hostId': hostId},
    );
    return HostLinkState.fromJson(_mapFromPayload(payload));
  }

  /// Sends [type], turning the runtime's typed host conflicts into the
  /// exceptions the UI branches on.
  Future<Object?> _request(String type, Map<String, Object?> payload) async {
    try {
      return await _client.runtimeRequest(type, payload);
    } on TerminalHostConflictException catch (error) {
      switch (error.code) {
        case 'sshTargetInUse':
          throw SshTargetInUseException.fromDetails(error.details);
        case 'hostBusy':
          throw HostBusyException.fromDetails(error.details);
        default:
          rethrow;
      }
    }
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
