import 'package:alera/src/features/command_terminal/application/command_terminal_session.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('commandTerminalHomeDirectory', () {
    test('prefers HOME', () {
      expect(
        commandTerminalHomeDirectory(const <String, String>{
          'HOME': '/home/leynier',
          'USERPROFILE': r'C:\Users\leynier',
        }),
        '/home/leynier',
      );
    });

    test('falls back to USERPROFILE on Windows', () {
      expect(
        commandTerminalHomeDirectory(const <String, String>{
          'USERPROFILE': r'C:\Users\leynier',
        }),
        r'C:\Users\leynier',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        commandTerminalHomeDirectory(const <String, String>{
          'HOME': '  /home/leynier  ',
        }),
        '/home/leynier',
      );
    });

    test('skips a blank value instead of returning it', () {
      expect(
        commandTerminalHomeDirectory(const <String, String>{
          'HOME': '   ',
          'USERPROFILE': r'C:\Users\leynier',
        }),
        r'C:\Users\leynier',
      );
    });

    test('returns null when neither variable is set', () {
      expect(commandTerminalHomeDirectory(const <String, String>{}), isNull);
    });
  });

  group('isCommandTerminalWorkspaceId', () {
    test('matches the synthetic id', () {
      expect(isCommandTerminalWorkspaceId(commandTerminalWorkspaceId), isTrue);
    });

    test('does not match a real workspace id', () {
      expect(
        isCommandTerminalWorkspaceId('7f1c0a2e-5b3d-4a11-9f0e-2c8d6b4a1e33'),
        isFalse,
      );
    });
  });

  group('CommandTerminalRequest', () {
    test('keeps the working directory and description it was given', () {
      const request = CommandTerminalRequest(
        title: 'Update Alera',
        command: 'sudo apt-get install --only-upgrade alera',
        workingDirectory: '/opt/alera',
        description: 'Answer Any Prompt In The Terminal.',
      );
      expect(request.title, 'Update Alera');
      expect(request.command, 'sudo apt-get install --only-upgrade alera');
      expect(request.workingDirectory, '/opt/alera');
      expect(request.description, 'Answer Any Prompt In The Terminal.');
    });

    test('leaves the working directory and description absent by default', () {
      const request = CommandTerminalRequest(title: 'Run', command: 'echo hi');
      expect(request.workingDirectory, isNull);
      expect(request.description, isNull);
    });
  });

  group('command terminal session records', () {
    const request = CommandTerminalRequest(
      title: 'Install Alera CLI Skill',
      command: 'npx skills add https://github.com/leynier/alera --global',
    );

    test('the workspace carries the synthetic id and the shell cwd', () {
      final workspace = buildCommandTerminalWorkspace(
        workingDirectory: '/home/leynier',
      );
      expect(workspace.id, commandTerminalWorkspaceId);
      expect(workspace.projectId, commandTerminalWorkspaceId);
      expect(workspace.path, '/home/leynier');
      expect(workspace.kind, WorkspaceKind.linked);
      expect(workspace.status, WorkspaceStatus.active);
    });

    test('the tab carries the command and its own session id', () {
      final tab = buildCommandTerminalTab(tabId: 'tab-9', request: request);
      expect(tab.id, 'tab-9');
      expect(tab.workspaceId, commandTerminalWorkspaceId);
      expect(tab.title, 'Install Alera CLI Skill');
      expect(tab.terminalSessionId, 'tab-9');
      expect(tab.initialCommand, request.command);
      expect(tab.hasManualTitle, isTrue);
    });

    test('the tab claims no host-side spawn behavior', () {
      // `spawnOnCreate` and `initialCommandOnce` are read by the runtime host
      // off persisted tab records, and this one never reaches it.
      final tab = buildCommandTerminalTab(tabId: 'tab-9', request: request);
      expect(tab.spawnOnCreate, isFalse);
      expect(tab.initialCommandOnce, isFalse);
      expect(
        tab.payload.keys,
        containsAll(<String>[
          workspaceTabTerminalSessionIdPayloadKey,
          workspaceTabInitialCommandPayloadKey,
          workspaceTabManualTitlePayloadKey,
        ]),
      );
      expect(tab.payload, hasLength(3));
    });
  });
}
