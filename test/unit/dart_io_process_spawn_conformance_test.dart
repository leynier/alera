import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spawns that may stay, with the reason they are safe.
const Map<String, String> _allowedSpawnSites = <String, String>{
  // `ProcessStartMode.detached` double-forks, so the sidecar never becomes a
  // child the VM's reaper thread can wait on. Measured: 0 of 10 probes hit
  // ECHILD with a detached child alive, against 4 of 10 with a normal one.
  'lib/src/features/workbench/infra/terminal_host/terminal_host_process_launcher.dart':
      'ProcessStartMode.detached',
};

final RegExp _spawnPattern = RegExp(r'\bProcess\.(run|runSync|start)\s*\(');

void main() {
  group('app process spawns', () {
    test('never start a dart:io child outside the allowed sites', () {
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final path = entity.path.replaceAll(r'\', '/');
        // Generated bridge code is not hand-written app code.
        if (path.startsWith('lib/src/rust/')) {
          continue;
        }
        final lines = entity.readAsLinesSync();
        for (var index = 0; index < lines.length; index += 1) {
          final line = lines[index];
          if (line.trimLeft().startsWith('//')) {
            continue;
          }
          if (!_spawnPattern.hasMatch(line)) {
            continue;
          }
          if (_allowedSpawnSites.containsKey(path)) {
            continue;
          }
          offenders.add('$path:${index + 1}: ${line.trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These call sites spawn a child with dart:io. A live dart:io child '
            'wakes the VM reaper thread, which waits on any child of the '
            'process and reaps pids it does not own, so the next waitpid from '
            'the Rust side fails with ECHILD and the app reports '
            '"No child processes (os error 10)". Run commands through '
            'ProcessRunner, and plain syscalls such as chmod through dart:ffi.\n'
            '${offenders.join('\n')}',
      );
    });

    test('keeps the allowed sites on the mode that makes them safe', () {
      for (final entry in _allowedSpawnSites.entries) {
        expect(
          File(entry.key).readAsStringSync(),
          contains(entry.value),
          reason:
              '${entry.key} is allowed to spawn only because of '
              '${entry.value}.',
        );
      }
    });
  });
}
