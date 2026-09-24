import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the attached shape published by hostLink.status', () {
    final state = HostLinkState.fromJson(<String, Object?>{
      'hostId': 'lab',
      'state': 'attached',
      'attachment': <String, Object?>{
        'runtimeDir': '/home/dev/.alera/sidecar/data',
        'platform': 'linux',
        'arch': 'x86_64',
        'hostVersion': '1.2.3',
        'runtimeCapabilities': <Object?>[
          'runtimeStore',
          'remoteSatelliteV1',
          4,
        ],
      },
    });
    expect(state.hostId, 'lab');
    expect(state.phase, HostLinkPhase.attached);
    expect(state.isAttached, isTrue);
    expect(state.attachment?.hostVersion, '1.2.3');
    expect(state.attachment?.hasCapability('remoteSatelliteV1'), isTrue);
    expect(state.attachment?.hasCapability('4'), isFalse);
    expect(state.error, isNull);
  });

  test('parses failed, connecting and unknown states', () {
    final failed = HostLinkState.fromJson(<String, Object?>{
      'hostId': 'lab',
      'state': 'failed',
      'error': 'permission denied',
    });
    expect(failed.phase, HostLinkPhase.failed);
    expect(failed.error, 'permission denied');
    expect(failed.attachment, isNull);
    expect(
      HostLinkState.fromJson(<String, Object?>{
        'hostId': 'lab',
        'state': 'connecting',
      }).phase,
      HostLinkPhase.connecting,
    );
    expect(
      HostLinkState.fromJson(<String, Object?>{
        'hostId': 'lab',
        'state': 'something-newer',
      }).phase,
      HostLinkPhase.disconnected,
    );
  });

  test('indexes states by host id', () {
    final byId = hostLinkStatesById(<HostLinkState>[
      const HostLinkState(hostId: 'a', phase: HostLinkPhase.attached),
      const HostLinkState(hostId: 'b', phase: HostLinkPhase.failed),
    ]);
    expect(byId['a']?.phase, HostLinkPhase.attached);
    expect(byId['b']?.phase, HostLinkPhase.failed);
    expect(byId['c'], isNull);
    expect(() => byId['c'] = byId['a']!, throwsUnsupportedError);
  });
}
