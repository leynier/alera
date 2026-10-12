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
