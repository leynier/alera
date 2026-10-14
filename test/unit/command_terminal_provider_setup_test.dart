import 'package:alera/src/features/command_terminal/application/command_terminal_session.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'setup selection is opaque and is never delivered as a typed command',
    () {
      const setup = CommandTerminalProviderSetup(
        providerInstanceId: 'work',
        action: 'signIn',
      );
      final tab = buildCommandTerminalTab(
        tabId: 'setup',
        request: const CommandTerminalRequest(
          title: 'Sign In',
          command: 'Display text only',
          providerSetup: setup,
        ),
      );
      expect(tab.workspaceId, commandTerminalWorkspaceId);
      expect(tab.initialCommand, isNull);
      expect(tab.payload[commandTerminalProviderSetupPayloadKey], {
        'providerInstanceId': 'work',
        'action': 'signIn',
      });
      expect(tab.payload.toString(), isNot(contains('Display text only')));
      final launch = TerminalHostLaunch(
        label: 'display',
        shell: 'ignored',
        arguments: const [],
        environment: const {},
        providerSetup: setup,
      );
      expect(launch.toJson()['providerSetup'], setup.toJson());
      expect(
        TerminalHostLaunch.fromJson(launch.toJson())
            .providerSetup
            ?.providerInstanceId,
        'work',
      );
    },
  );

  test('ordinary command terminals preserve startup command delivery', () {
    final tab = buildCommandTerminalTab(
      tabId: 'command',
      request: const CommandTerminalRequest(title: 'Run', command: 'example'),
    );
    expect(tab.initialCommand, 'example');
    expect(
      tab.payload.containsKey(commandTerminalProviderSetupPayloadKey),
      isFalse,
    );
    expect(tab.payload[workspaceTabInitialCommandPayloadKey], 'example');
  });

  test(
    'remote setup preserves its owner separately from the opaque selection',
    () {
      final tab = buildCommandTerminalTab(
        tabId: 'setup',
        request: const CommandTerminalRequest(
          title: 'Sign In',
          command: 'Display text only',
          hostId: 'owner',
          providerSetup: CommandTerminalProviderSetup(
            providerInstanceId: 'codex',
            action: 'signIn',
          ),
        ),
      );
      expect(
        tab.terminalSessionId,
        '${commandTerminalRemoteSetupSessionPrefix}setup',
      );
      expect(tab.payload[commandTerminalHostIdPayloadKey], 'owner');
      expect(tab.payload[commandTerminalProviderSetupPayloadKey], {
        'providerInstanceId': 'codex',
        'action': 'signIn',
      });
      expect(tab.initialCommand, isNull);
    },
  );

  test('setup DTO rejects extra recipe fields and unknown actions', () {
    for (final value in [
      {'providerInstanceId': 'codex', 'action': 'run'},
      {
        'providerInstanceId': 'codex',
        'action': 'signIn',
        'command': 'arbitrary',
      },
      {
        'providerInstanceId': 'codex',
        'action': 'signIn',
        'environment': {'TOKEN': 'secret'},
      },
    ]) {
      expect(
        () => CommandTerminalProviderSetup.fromJson(value),
        throwsFormatException,
      );
    }
  });
}
