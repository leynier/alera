import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/claude_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/codex_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Captured with Flutter 3.44.8 / Dart 3.12.2 for a file containing
// "plugin contents" with mtime 2026-01-02T03:04:05.123456Z. The services use
// different JSON key ordering, so their persisted hashes are distinct.
const _legacyFingerprints = <String, String>{
  'codex':
      'sha256:b105eea1dcbe75b3f192a566236a62ae9cad43cbea0f2b74231bea442e66dd6c',
  'claude':
      'sha256:a9fa862cdec6b7d664d8dee2faf80f3828f66ecfcbddcb67848eca9d6bfd4f59',
};

void main() {
  for (final agent in _legacyFingerprints.keys) {
    group('$agent resource fingerprint compatibility', () {
      late Directory root;
      late Directory home;
      late Directory support;
      late File source;
      final modified = DateTime.utc(2026, 1, 2, 3, 4, 5, 123, 456);

      setUp(() {
        root = Directory.systemTemp.createTempSync('alera-resource-upgrade-');
        home = Directory(p.join(root.path, 'home'))..createSync();
        support = Directory(p.join(root.path, 'support'))..createSync();
        source = File(p.join(home.path, '.$agent', 'plugins'))
          ..createSync(recursive: true)
          ..writeAsStringSync('plugin contents')
          ..setLastModifiedSync(modified);
      });

      tearDown(() => root.deleteSync(recursive: true));

      Future<String> prepare() => _prepareRuntime(agent, home, support);

      test('retains a copied resource with a pre-upgrade marker', () async {
        final runtimeHome = await prepare();
        final target = File(p.join(runtimeHome, 'plugins'))
          ..writeAsStringSync('local runtime customization');
        final marker = File(p.join(runtimeHome, '.alera-copied-plugins.json'))
          ..writeAsStringSync(
            jsonEncode(<String, String>{
              'sourcePath': source.path,
              'sourceFingerprint': _legacyFingerprints[agent]!,
            }),
          );
        final markerBefore = marker.readAsStringSync();

        await prepare();

        expect(target.readAsStringSync(), 'local runtime customization');
        expect(marker.readAsStringSync(), markerBefore);
        expect(source.readAsStringSync(), 'plugin contents');
      });

      test('still refreshes a changed source with the same length', () async {
        final runtimeHome = await prepare();
        final target = File(p.join(runtimeHome, 'plugins'));
        final marker = File(p.join(runtimeHome, '.alera-copied-plugins.json'));
        final markerBefore = marker.readAsStringSync();
        source
          ..writeAsStringSync('changed content')
          ..setLastModifiedSync(modified.add(const Duration(milliseconds: 1)));

        await prepare();

        expect(target.readAsStringSync(), 'changed content');
        expect(marker.readAsStringSync(), isNot(markerBefore));
      });

      test('never replaces a resource without an ownership marker', () async {
        final runtimeHome = await prepare();
        final target = File(p.join(runtimeHome, 'plugins'))
          ..writeAsStringSync('unmanaged resource');
        final marker = File(p.join(runtimeHome, '.alera-copied-plugins.json'))
          ..deleteSync();
        source.writeAsStringSync('source changed');

        await prepare();

        expect(target.readAsStringSync(), 'unmanaged resource');
        expect(marker.existsSync(), isFalse);
      });
    });
  }
}

Future<String> _prepareRuntime(
  String agent,
  Directory home,
  Directory support,
) async {
  void failLinks({required String sourcePath, required String targetPath}) {
    throw const FileSystemException('symlinks disabled');
  }

  if (agent == 'codex') {
    final preparation = await CodexRuntimeHomeService(
      homeDirectory: home.path,
      applicationSupportDirectory: () async => support,
      platform: ManagedAgentHookPlatform.posix,
      environment: <String, String>{'HOME': home.path},
      resourceLinkCreator: failLinks,
    ).prepareForTerminalLaunch();
    return preparation.runtimeHomePath;
  }
  final preparation = await ClaudeRuntimeHomeService(
    homeDirectory: home.path,
    applicationSupportDirectory: () async => support,
    platform: ManagedAgentHookPlatform.posix,
    environment: <String, String>{'HOME': home.path},
    resourceLinkCreator: failLinks,
    syncMacOSKeychainCredentials: false,
  ).prepareForTerminalLaunch();
  return preparation.runtimeHomePath;
}
