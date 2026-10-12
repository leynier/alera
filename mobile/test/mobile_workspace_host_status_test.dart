import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host_status.dart';
import 'package:flutter_test/flutter_test.dart';

MobileWorkspaceHost _host(
  MobileWorkspaceHostStatus status, {
  bool updateAvailable = false,
}) => MobileWorkspaceHost(
  id: 'ssh-mac',
  alias: 'Studio Mac',
  status: status,
  updateAvailable: updateAvailable,
);

void main() {
  test('parses every reported state and falls back to unknown', () {
    expect(
      MobileWorkspaceHostStatus.parse('needsSetup'),
      MobileWorkspaceHostStatus.needsSetup,
    );
    expect(
      MobileWorkspaceHostStatus.parse('installing'),
      MobileWorkspaceHostStatus.installing,
    );
    expect(
      MobileWorkspaceHostStatus.parse('disconnected'),
      MobileWorkspaceHostStatus.disconnected,
    );
    expect(
      MobileWorkspaceHostStatus.parse(' offline '),
      MobileWorkspaceHostStatus.offline,
    );
    expect(
      MobileWorkspaceHostStatus.parse('connecting'),
      MobileWorkspaceHostStatus.connecting,
    );
    expect(
      MobileWorkspaceHostStatus.parse('connected'),
      MobileWorkspaceHostStatus.connected,
    );
    expect(
      MobileWorkspaceHostStatus.parse('error'),
      MobileWorkspaceHostStatus.error,
    );
    expect(
      MobileWorkspaceHostStatus.parse('hibernating'),
      MobileWorkspaceHostStatus.unknown,
    );
    expect(
      MobileWorkspaceHostStatus.parse(null),
      MobileWorkspaceHostStatus.unknown,
    );
  });

  test('labels use the shared host vocabulary', () {
    expect(
      <String?>[
        for (final status in MobileWorkspaceHostStatus.values) status.label,
      ],
      <String?>[
        'Needs Setup',
        'Installing…',
        'Not Connected',
        'Offline',
        'Connecting…',
        'Connected',
        'Error',
        null,
      ],
    );
  });

  test('only a host without a working runtime blocks creation', () {
    expect(
      <MobileWorkspaceHostStatus>[
        for (final status in MobileWorkspaceHostStatus.values)
          if (!status.isReady) status,
      ],
      <MobileWorkspaceHostStatus>[
        MobileWorkspaceHostStatus.needsSetup,
        MobileWorkspaceHostStatus.installing,
        MobileWorkspaceHostStatus.error,
      ],
    );
  });

  test('an older runtime without status leaves the host ready', () {
    final host = MobileWorkspaceHost.fromJson(const <String, Object?>{
      'id': 'ssh-mac',
      'alias': 'Studio Mac',
      'platform': 'darwin',
    });
    expect(host.status, MobileWorkspaceHostStatus.unknown);
    expect(host.isReady, isTrue);
    expect(host.updateAvailable, isFalse);
    expect(host.runtimeVersion, isNull);
    expect(host.pickerLabel, 'Studio Mac');
    expect(host.pickerNotice, isNull);
  });

  test('parses status, runtime version and pending update', () {
    final host = MobileWorkspaceHost.fromJson(const <String, Object?>{
      'id': 'ssh-tux',
      'alias': 'Rack',
      'status': 'needsSetup',
      'runtimeVersion': '0.104.0',
      'updateAvailable': true,
    });
    expect(host.status, MobileWorkspaceHostStatus.needsSetup);
    expect(host.runtimeVersion, '0.104.0');
    expect(host.updateAvailable, isTrue);
    expect(host.isReady, isFalse);
  });

  test('picker label names every state other than connected', () {
    expect(_host(.connected).pickerLabel, 'Studio Mac');
    expect(_host(.offline).pickerLabel, 'Studio Mac (Offline)');
    expect(_host(.disconnected).pickerLabel, 'Studio Mac (Not Connected)');
    expect(_host(.connecting).pickerLabel, 'Studio Mac (Connecting…)');
    expect(_host(.needsSetup).pickerLabel, 'Studio Mac (Needs Setup)');
    expect(_host(.installing).pickerLabel, 'Studio Mac (Installing…)');
    expect(_host(.error).pickerLabel, 'Studio Mac (Error)');
    final outdated = _host(.connected, updateAvailable: true);
    expect(outdated.pickerLabel, 'Studio Mac (Update Available)');
    expect(outdated.isReady, isTrue);
    expect(outdated.pickerNotice, isNull);
    // A blocking state wins over the update hint.
    expect(
      _host(.needsSetup, updateAvailable: true).pickerLabel,
      'Studio Mac (Needs Setup)',
    );
  });

  test('picker notice explains blocking states and reassures otherwise', () {
    expect(_host(.needsSetup).pickerNotice, (
      message: 'The Alera runtime is not installed on Studio Mac. Set it up from the desktop.',
      blocksCreation: true,
    ));
    expect(_host(.installing).pickerNotice, (
      message: 'Studio Mac is still installing the Alera runtime.',
      blocksCreation: true,
    ));
    expect(_host(.error).pickerNotice, (
      message: 'Studio Mac has a connection error. Check it from the desktop.',
      blocksCreation: true,
    ));
    for (final status in <MobileWorkspaceHostStatus>[
      .offline,
      .disconnected,
      .connecting,
    ]) {
      expect(_host(status).pickerNotice, (
        message: 'Alera connects to Studio Mac when the workspace needs it.',
        blocksCreation: false,
      ));
    }
    expect(_host(.connected).pickerNotice, isNull);
  });
}
