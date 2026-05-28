import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/codex_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

part 'codex_runtime_home_service_test_harness.dart';

part 'codex_runtime_home_service_core_test_cases.dart';
part 'codex_runtime_home_service_advanced_test_cases.dart';

late Directory root;
late Directory home;
late Directory support;
late CodexRuntimeHomeService service;

void main() {
  group('CodexRuntimeHomeService', () {
    setUp(() async {
      root = await Directory.systemTemp.createTemp('alera-codex-runtime-');
      home = Directory(p.join(root.path, 'home'))..createSync(recursive: true);
      support = Directory(p.join(root.path, 'support'))
        ..createSync(recursive: true);
      service = CodexRuntimeHomeService(
        homeDirectory: home.path,
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': home.path},
      );
    });

    tearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    _registerCodexRuntimeHomeServiceCoreTests();
    _registerCodexRuntimeHomeServiceAdvancedTests();
  });
}
