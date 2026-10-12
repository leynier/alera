import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_runtime_version.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteHostStatus.fromJson', () {
    test('parses every hostStatus state', () {
      expect(
        RemoteHostStatus.fromJson(<String, Object?>{
          'state': 'needsSetup',
          'detail': 'mkdir failed',
        }),
        isA<RemoteHostNeedsSetup>().having(
          (status) => status.detail,
          'detail',
          'mkdir failed',
        ),
      );
      expect(
        RemoteHostStatus.fromJson(<String, Object?>{
          'state': 'installing',
          'stage': 'upload',
        }),
        isA<RemoteHostInstalling>().having(
          (status) => status.stage,
          'stage',
          'upload',
        ),
      );
      expect(
        RemoteHostStatus.fromJson(<String, Object?>{'state': 'disconnected'}),
        isA<RemoteHostDisconnected>(),
      );
      final offline = RemoteHostStatus.fromJson(<String, Object?>{
        'state': 'offline',
        'retry': <String, Object?>{
          'attempt': 3,
          'nextRetryAt': '2026-10-11T10:00:00Z',
        },
      });
      expect(offline, isA<RemoteHostOffline>());
      expect((offline! as RemoteHostOffline).retry?.attempt, 3);
      expect(
        (offline as RemoteHostOffline).retry?.nextRetryAt,
        DateTime.utc(2026, 10, 11, 10),
      );
      expect(
        RemoteHostStatus.fromJson(<String, Object?>{
          'state': 'connecting',
          'retry': null,
        }),
        isA<RemoteHostConnecting>().having(
          (status) => status.retry,
          'retry',
          isNull,
        ),
      );
      final connected = RemoteHostStatus.fromJson(<String, Object?>{
        'state': 'connected',
        'satelliteVersion': '1.4.0',
        'hubVersion': '1.5.0',
        'runtimeUpdateAvailable': true,
      });
      expect(connected, isA<RemoteHostConnected>());
      expect((connected! as RemoteHostConnected).updateAvailable, isTrue);
      expect((connected as RemoteHostConnected).satelliteVersion, '1.4.0');
      expect(connected.hubVersion, '1.5.0');
      expect(connected.label, 'Update Available');
      expect(
        RemoteHostStatus.fromJson(<String, Object?>{
          'state': 'error',
          'detail': 'Permission denied (publickey).',
        }),
        isA<RemoteHostError>()
            .having((status) => status.detail, 'detail', contains('publickey'))
            .having(
              (status) => status.origin,
              'origin',
              RemoteHostErrorOrigin.connect,
            ),
      );
    });

    test('returns null for a missing payload or an unknown state', () {
      expect(RemoteHostStatus.fromJson(null), isNull);
      expect(RemoteHostStatus.fromJson('connected'), isNull);
      expect(
        RemoteHostStatus.fromJson(<String, Object?>{'state': 'sleeping'}),
        isNull,
      );
    });

    test('SshTarget parses hostStatus and never sends it back', () {
      final target = SshTarget.fromJson(<String, Object?>{
        ..._targetJson(),
        'identityFile': '~/.ssh/build_mac',
        'hostStatus': <String, Object?>{'state': 'connected'},
      });

      expect(target.hostStatus, isA<RemoteHostConnected>());
      expect(target.identityFile, '~/.ssh/build_mac');
      expect(target.toJson()['identityFile'], '~/.ssh/build_mac');
      expect(target.toJson().containsKey('hostStatus'), isFalse);
      expect(target.copyWith(alias: 'Other').identityFile, '~/.ssh/build_mac');
    });
  });

  group('RemoteHostStatus labels and readiness', () {
    test('follow the badge table', () {
      final cases = <RemoteHostStatus, (String, bool, RemoteHostStatusTone)>{
        const RemoteHostNeedsSetup(): (
          'Needs Setup',
          false,
          RemoteHostStatusTone.attention,
        ),
        const RemoteHostInstalling(): (
          'Installing…',
          false,
          RemoteHostStatusTone.info,
        ),
        const RemoteHostDisconnected(): (
          'Not Connected',
          true,
          RemoteHostStatusTone.neutral,
        ),
        const RemoteHostOffline(): (
          'Offline',
          true,
          RemoteHostStatusTone.neutral,
        ),
        const RemoteHostConnecting(): (
          'Connecting…',
          true,
          RemoteHostStatusTone.neutral,
        ),
        const RemoteHostConnected(): (
          'Connected',
          true,
          RemoteHostStatusTone.success,
        ),
        const RemoteHostConnected(updateAvailable: true): (
          'Update Available',
          true,
          RemoteHostStatusTone.info,
        ),
        const RemoteHostError(detail: 'boom'): (
          'Error',
          false,
          RemoteHostStatusTone.error,
        ),
      };
      for (final MapEntry(key: status, value: (label, ready, tone))
          in cases.entries) {
        expect(status.label, label);
        expect(status.isReady, ready, reason: label);
        expect(status.tone, tone, reason: label);
      }
      expect(const RemoteHostOffline().showsDot, isTrue);
      expect(const RemoteHostInstalling().isBusy, isTrue);
      expect(const RemoteHostConnecting().isBusy, isTrue);
      expect(const RemoteHostConnected().isBusy, isFalse);
      expect(
        const RemoteHostError(detail: 'x').severity,
        greaterThan(const RemoteHostOffline().severity),
      );
      expect(
        const RemoteHostNeedsSetup().severity,
        greaterThan(const RemoteHostInstalling().severity),
      );
      expect(
        const RemoteHostConnecting().severity,
        greaterThan(const RemoteHostConnected().severity),
      );
    });
  });

  group('RemoteHostStatus.derive', () {
    test('a running install wins over everything else', () {
      final status = RemoteHostStatus.derive(
        _target(bootstrapStatus: .installed),
        _link(HostLinkPhase.attached),
        _progress(SshBootstrapStatus.installing, stage: 'upload'),
      );
      expect(
        status,
        isA<RemoteHostInstalling>().having((s) => s.stage, 'stage', 'upload'),
      );
    });

    test('a failed install is an install error with its reason', () {
      final status = RemoteHostStatus.derive(
        _target(bootstrapStatus: .failed, lastError: 'stored'),
        null,
        _progress(SshBootstrapStatus.failed, error: 'disk full'),
      );
      expect(
        status,
        isA<RemoteHostError>()
            .having((s) => s.detail, 'detail', 'disk full')
            .having((s) => s.origin, 'origin', RemoteHostErrorOrigin.install),
      );
    });

    test('progress for another host is ignored', () {
      final status = RemoteHostStatus.derive(
        _target(bootstrapStatus: .notInstalled),
        null,
        _progress(SshBootstrapStatus.installing, targetId: 'other'),
      );
      expect(status, isA<RemoteHostNeedsSetup>());
    });

    test('a host without the runtime needs setup', () {
      for (final bootstrap in <SshBootstrapStatus>[
        .notInstalled,
        .planned,
        .cancelled,
      ]) {
        expect(
          RemoteHostStatus.derive(
            _target(bootstrapStatus: bootstrap),
            null,
            null,
          ),
          isA<RemoteHostNeedsSetup>().having((s) => s.detail, 'detail', isNull),
          reason: bootstrap.name,
        );
      }
      expect(
        RemoteHostStatus.derive(
          _target(bootstrapStatus: .failed, lastError: 'mkdir failed'),
          null,
          null,
        ),
        isA<RemoteHostNeedsSetup>().having(
          (s) => s.detail,
          'detail',
          'mkdir failed',
        ),
      );
    });

    test('an installing record without a job is an interrupted install', () {
      final target = _target(bootstrapStatus: .installing);
      expect(
        RemoteHostStatus.derive(target, null, null),
        isA<RemoteHostInstalling>(),
      );
      expect(
        RemoteHostStatus.derive(target, null, null, hasInstallJob: false),
        isA<RemoteHostNeedsSetup>(),
      );
    });

    test('a finished install counts before the target refreshes', () {
      expect(
        RemoteHostStatus.derive(
          _target(bootstrapStatus: .installing),
          null,
          _progress(SshBootstrapStatus.installed),
        ),
        isA<RemoteHostDisconnected>(),
      );
    });

    test('maps an installed host by its link', () {
      final installed = _target(bootstrapStatus: .installed);
      expect(
        RemoteHostStatus.derive(installed, null, null),
        isA<RemoteHostDisconnected>(),
      );
      expect(
        RemoteHostStatus.derive(
          installed,
          _link(HostLinkPhase.disconnected),
          null,
        ),
        isA<RemoteHostDisconnected>(),
      );
      expect(
        RemoteHostStatus.derive(
          installed,
          _link(HostLinkPhase.connecting),
          null,
        ),
        isA<RemoteHostConnecting>(),
      );
      expect(
        RemoteHostStatus.derive(
          installed,
          _link(HostLinkPhase.attached, hostVersion: '1.4.0'),
          null,
        ),
        isA<RemoteHostConnected>()
            .having((s) => s.satelliteVersion, 'satelliteVersion', '1.4.0')
            .having((s) => s.updateAvailable, 'updateAvailable', isFalse),
      );
      expect(
        RemoteHostStatus.derive(
          installed,
          _link(HostLinkPhase.failed, error: 'Permission denied (publickey).'),
          null,
        ),
        isA<RemoteHostError>().having(
          (s) => s.origin,
          'origin',
          RemoteHostErrorOrigin.connect,
        ),
      );
    });

    test('a network failure or an unreachable probe is offline', () {
      final installed = _target(bootstrapStatus: .installed);
      expect(
        RemoteHostStatus.derive(
          installed,
          _link(
            HostLinkPhase.failed,
            error: 'ssh: connect to host mac port 22: Connection refused',
          ),
          null,
        ),
        isA<RemoteHostOffline>(),
      );
      expect(
        RemoteHostStatus.derive(
          installed,
          _link(
            HostLinkPhase.failed,
            error: 'boom',
            failureKind: 'unreachable',
          ),
          null,
        ),
        isA<RemoteHostOffline>(),
      );
      expect(
        RemoteHostStatus.derive(
          installed,
          _link(
            HostLinkPhase.failed,
            error: 'Connection refused',
            failureKind: 'authentication',
          ),
          null,
        ),
        isA<RemoteHostError>(),
      );
      final unreachable = _target(
        bootstrapStatus: .installed,
        lastStatus: 'unreachable',
      );
      expect(
        RemoteHostStatus.derive(unreachable, null, null),
        isA<RemoteHostOffline>(),
      );
      expect(
        RemoteHostStatus.derive(
          unreachable,
          _link(HostLinkPhase.failed, error: 'Permission denied'),
          null,
        ),
        isA<RemoteHostOffline>(),
      );
    });

    test('offers an update only when the host runtime is older', () {
      final installed = _target(bootstrapStatus: .installed);
      RemoteHostStatus connected(String? satellite, String? hub) =>
          RemoteHostStatus.derive(
            installed,
            _link(HostLinkPhase.attached, hostVersion: satellite),
            null,
            hubVersion: hub,
          );
      expect(
        (connected('1.4.0', '1.5.0') as RemoteHostConnected).updateAvailable,
        isTrue,
      );
      expect(
        (connected('1.5.0', '1.5.0') as RemoteHostConnected).updateAvailable,
        isFalse,
      );
      expect(
        (connected(
          '1.6.0',
          '1.5.0-dev',
        ) as RemoteHostConnected).updateAvailable,
        isFalse,
      );
      expect(
        (connected(null, '1.5.0') as RemoteHostConnected).updateAvailable,
        isFalse,
      );
      expect(
        RemoteHostStatus.derive(
          installed,
          _link(
            HostLinkPhase.attached,
            hostVersion: '1.4.0',
            runtimeUpdateAvailable: true,
          ),
          null,
        ),
        isA<RemoteHostConnected>().having(
          (s) => s.updateAvailable,
          'updateAvailable',
          isTrue,
        ),
      );
    });
  });

  test('runtimeVersionRelation compares numeric components', () {
    expect(
      runtimeVersionRelation('1.5.0', '1.4.9'),
      RuntimeVersionRelation.older,
    );
    expect(runtimeVersionRelation('1.5.0', '1.5'), RuntimeVersionRelation.same);
    expect(
      runtimeVersionRelation('v1.5.0', '1.5.0-rc.1'),
      RuntimeVersionRelation.same,
    );
    expect(
      runtimeVersionRelation('1.5.0', '1.10.0'),
      RuntimeVersionRelation.newer,
    );
    expect(
      runtimeVersionRelation('dev', '1.0.0'),
      RuntimeVersionRelation.unknown,
    );
    expect(
      runtimeVersionRelation(null, '1.0.0'),
      RuntimeVersionRelation.unknown,
    );
  });
}

Map<String, Object?> _targetJson() => <String, Object?>{
  'id': 'mac',
  'alias': 'Build Mac',
  'host': 'mac.local',
  'port': 22,
  'username': 'leynier',
  'authKind': 'agent',
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': '2026-10-01T00:00:00Z',
};

SshTarget _target({
  SshBootstrapStatus bootstrapStatus = SshBootstrapStatus.notInstalled,
  String? lastError,
  String? lastStatus,
}) {
  final now = DateTime.utc(2026, 10);
  return SshTarget(
    id: 'mac',
    alias: 'Build Mac',
    host: 'mac.local',
    port: 22,
    username: 'leynier',
    authKind: .agent,
    createdAt: now,
    updatedAt: now,
    bootstrapStatus: bootstrapStatus,
    lastError: lastError,
    lastStatus: lastStatus,
  );
}

HostLinkState _link(
  HostLinkPhase phase, {
  String? error,
  String? hostVersion,
  String? failureKind,
  bool? runtimeUpdateAvailable,
}) {
  return HostLinkState(
    hostId: 'mac',
    phase: phase,
    error: error,
    failureKind: failureKind,
    runtimeUpdateAvailable: runtimeUpdateAvailable,
    attachment: phase == HostLinkPhase.attached
        ? HostLinkAttachment(
            runtimeDir: '/home/leynier/.alera/data',
            platform: 'macos',
            arch: 'arm64',
            hostVersion: hostVersion,
          )
        : null,
  );
}

SshTargetBootstrapProgress _progress(
  SshBootstrapStatus status, {
  String stage = 'auth',
  String? error,
  String targetId = 'mac',
}) {
  return SshTargetBootstrapProgress(
    jobId: 'job-1',
    targetId: targetId,
    status: status,
    stage: stage,
    message: 'Working',
    error: error,
  );
}
