import 'dart:io';

import 'package:alera/src/features/agent_status/infra/agent_runtime_overlay_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AgentRuntimeOverlayService', () {
    late Directory home;
    late Directory support;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('alera-overlay-home-');
      support = await Directory.systemTemp.createTemp('alera-overlay-support-');
    });

    tearDown(() {
      if (home.existsSync()) {
        home.deleteSync(recursive: true);
      }
      if (support.existsSync()) {
        support.deleteSync(recursive: true);
      }
    });

    AgentRuntimeOverlayService service({
      Map<String, String>? environment,
      AgentOverlayResourceLinkCreator? resourceLinkCreator,
    }) {
      return AgentRuntimeOverlayService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{
          'HOME': home.path,
          'SHELL': '/bin/zsh',
          ...?environment,
        },
        applicationSupportDirectory: () async => support,
        resourceLinkCreator: resourceLinkCreator,
      );
    }

    test('creates an OpenCode overlay with only the Alera plugin', () async {
      final preparation = await service().prepareOpenCodeForTerminalLaunch(
        terminalSessionId: 'session-1',
      );

      final overlay = preparation.overlayPath;
      expect(overlay, isNotNull);
      expect(
        preparation.environment,
        containsPair('OPENCODE_CONFIG_DIR', overlay),
      );
      expect(
        preparation.environment,
        containsPair('ALERA_OPENCODE_CONFIG_DIR', overlay),
      );

      final plugin = File(
        p.join(overlay!, 'plugins', 'alera-agent-status.js'),
      ).readAsStringSync();
      expect(plugin, contains('ALERA_AGENT_STATUS_MANAGED_FILE'));
      expect(plugin, contains('AleraOpenCodeStatusPlugin'));
    });

    test(
      'mirrors OpenCode user config without overwriting same-name plugin',
      () async {
        final userConfig = Directory(p.join(home.path, 'opencode-user'))
          ..createSync(recursive: true);
        File(
          p.join(userConfig.path, 'opencode.json'),
        ).writeAsStringSync('{"theme":"solarized"}');
        final plugins = Directory(p.join(userConfig.path, 'plugins'))
          ..createSync();
        File(
          p.join(plugins.path, 'user-plugin.js'),
        ).writeAsStringSync('export default function userPlugin() {}\n');
        File(
          p.join(plugins.path, 'alera-agent-status.js'),
        ).writeAsStringSync('USER OWNED PLUGIN\n');

        final preparation = await service(
          environment: <String, String>{'OPENCODE_CONFIG_DIR': userConfig.path},
        ).prepareOpenCodeForTerminalLaunch(terminalSessionId: 'session-2');

        final overlay = preparation.overlayPath!;
        expect(preparation.sourcePath, userConfig.path);
        expect(
          File(p.join(overlay, 'opencode.json')).readAsStringSync(),
          '{"theme":"solarized"}',
        );
        expect(
          File(p.join(overlay, 'plugins', 'user-plugin.js')).readAsStringSync(),
          'export default function userPlugin() {}\n',
        );
        final overlayPlugin = File(
          p.join(overlay, 'plugins', 'alera-agent-status.js'),
        ).readAsStringSync();
        expect(overlayPlugin, contains('AleraOpenCodeStatusPlugin'));
        expect(overlayPlugin, isNot('USER OWNED PLUGIN\n'));
        expect(
          File(
            p.join(plugins.path, 'alera-agent-status.js'),
          ).readAsStringSync(),
          'USER OWNED PLUGIN\n',
        );
      },
    );

    test('preserves an explicit missing OpenCode config path', () async {
      final missing = p.join(home.path, 'missing-opencode');

      final preparation = await service(
        environment: <String, String>{'OPENCODE_CONFIG_DIR': missing},
      ).prepareOpenCodeForTerminalLaunch(terminalSessionId: 'session-3');

      expect(preparation.overlayPath, isNull);
      expect(preparation.environment, <String, String>{
        'OPENCODE_CONFIG_DIR': missing,
      });
      expect(Directory(missing).existsSync(), isFalse);
    });

    test('uses bash startup exports as the OpenCode source', () async {
      final userConfig = Directory(p.join(home.path, 'custom-opencode'))
        ..createSync(recursive: true);
      File(p.join(userConfig.path, 'opencode.json')).writeAsStringSync('{}');
      File(p.join(home.path, '.bashrc')).writeAsStringSync(
        'export OPENCODE_CONFIG_DIR="\${HOME}/custom-opencode" # user config\n',
      );

      final preparation = await service(
        environment: <String, String>{'SHELL': '/bin/bash'},
      ).prepareOpenCodeForTerminalLaunch(terminalSessionId: 'session-bash');

      final overlay = preparation.overlayPath!;
      expect(preparation.sourcePath, userConfig.path);
      expect(
        preparation.environment,
        containsPair('ALERA_OPENCODE_SOURCE_CONFIG_DIR', userConfig.path),
      );
      expect(File(p.join(overlay, 'opencode.json')).readAsStringSync(), '{}');
    });

    test('mirrors Pi agent state and installs the status extension', () async {
      final piAgent = Directory(p.join(home.path, '.pi', 'agent'))
        ..createSync(recursive: true);
      File(p.join(piAgent.path, 'auth.json')).writeAsStringSync('secret token');
      Directory(p.join(piAgent.path, 'sessions')).createSync();
      File(
        p.join(piAgent.path, 'sessions', 'session.json'),
      ).writeAsStringSync('{}');
      final extensions = Directory(p.join(piAgent.path, 'extensions'))
        ..createSync();
      File(
        p.join(extensions.path, 'user-extension.ts'),
      ).writeAsStringSync('export default function userExtension() {}\n');
      File(
        p.join(extensions.path, 'alera-agent-status.ts'),
      ).writeAsStringSync('USER OWNED EXTENSION\n');

      final preparation = await service().preparePiForTerminalLaunch(
        terminalSessionId: 'session-4',
      );

      final overlay = preparation.overlayPath!;
      expect(
        preparation.environment,
        containsPair('PI_CODING_AGENT_DIR', overlay),
      );
      expect(
        File(p.join(overlay, 'auth.json')).readAsStringSync(),
        'secret token',
      );
      expect(
        File(p.join(overlay, 'sessions', 'session.json')).readAsStringSync(),
        '{}',
      );
      expect(
        File(
          p.join(overlay, 'extensions', 'user-extension.ts'),
        ).readAsStringSync(),
        'export default function userExtension() {}\n',
      );
      final statusExtension = File(
        p.join(overlay, 'extensions', 'alera-agent-status.ts'),
      ).readAsStringSync();
      expect(statusExtension, contains('ALERA_AGENT_STATUS_MANAGED_FILE'));
      expect(statusExtension, contains("pi.on('agent_start'"));
      expect(
        File(
          p.join(extensions.path, 'alera-agent-status.ts'),
        ).readAsStringSync(),
        'USER OWNED EXTENSION\n',
      );
    });

    test(
      'clearTerminalOverlays removes overlays without touching sources',
      () async {
        final userConfig = Directory(p.join(home.path, 'opencode-user'))
          ..createSync(recursive: true);
        File(p.join(userConfig.path, 'auth.json')).writeAsStringSync('auth');

        final overlayService = service(
          environment: <String, String>{'OPENCODE_CONFIG_DIR': userConfig.path},
        );
        final preparation = await overlayService
            .prepareOpenCodeForTerminalLaunch(terminalSessionId: 'session-5');
        expect(Directory(preparation.overlayPath!).existsSync(), isTrue);

        await overlayService.clearTerminalOverlays('session-5');

        expect(Directory(preparation.overlayPath!).existsSync(), isFalse);
        expect(
          File(p.join(userConfig.path, 'auth.json')).readAsStringSync(),
          'auth',
        );
      },
    );
  });
}
