import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('uses explicit CLI path override', () async {
    final resolver = DefaultAleraCliResolver(
      environment: const <String, String>{'ALERA_CLI_PATH': ' /opt/alera '},
    );

    final command = await resolver.resolve(runtimeDir: '/tmp/alera/runtime');

    expect(command.executable, '/opt/alera');
    expect(command.prefixArguments, isEmpty);
    expect(command.workingDirectory, isNull);
  });

  test('finds direct Windows sidecar from bundle directory', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-cli-sidecar-windows-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final bundleDir = Directory(p.join(tempDir.path, 'bundle'));
    final binDir = Directory(p.join(bundleDir.path, 'bin'));
    await binDir.create(recursive: true);
    final executable = File(p.join(binDir.path, 'alera.exe'));
    await executable.writeAsString('exe');
    final resolver = DefaultAleraCliResolver(
      environment: <String, String>{'ALERA_CLI_BUNDLE_DIR': bundleDir.path},
      operatingSystem: 'windows',
      resolvedExecutable: p.join(tempDir.path, 'Alera.exe'),
      currentDirectoryPath: tempDir.path,
    );

    final command = await resolver.resolve(
      runtimeDir: p.join(tempDir.path, 'runtime'),
    );

    expect(command.executable, executable.path);
    expect(command.prefixArguments, isEmpty);
  });

  test('falls back to cargo run after checking bundle candidates', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-cli-sidecar-fallback-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final bundleDir = Directory(p.join(tempDir.path, 'missing-bundle'));
    final resolver = DefaultAleraCliResolver(
      environment: <String, String>{
        'ALERA_CLI_BUNDLE_DIR': bundleDir.path,
        'CARGO': ' /usr/local/bin/cargo ',
      },
      operatingSystem: 'macos',
      resolvedExecutable: p.join(
        tempDir.path,
        'Alera.app',
        'Contents',
        'MacOS',
        'Alera',
      ),
      currentDirectoryPath: tempDir.path,
    );

    final command = await resolver.resolve(
      runtimeDir: p.join(tempDir.path, 'support', 'terminal_host'),
    );

    expect(command.executable, '/usr/local/bin/cargo');
    expect(command.prefixArguments, const <String>[
      'run',
      '--quiet',
      '--locked',
      '--manifest-path',
      'rust/Cargo.toml',
      '-p',
      'alera-cli',
      '--',
    ]);
    expect(command.workingDirectory, tempDir.path);
  });

  test('falls back when a macOS executable is not in an app bundle', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-cli-sidecar-no-bundle-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final resolver = DefaultAleraCliResolver(
      environment: const <String, String>{'CARGO': '   '},
      operatingSystem: 'macos',
      resolvedExecutable: p.join(tempDir.path, 'Alera'),
      currentDirectoryPath: tempDir.path,
    );

    final command = await resolver.resolve(
      runtimeDir: p.join(tempDir.path, 'support', 'terminal_host'),
    );

    expect(command.executable, 'cargo');
    expect(command.workingDirectory, tempDir.path);
  });

  test('extracts and reuses compressed sidecar archives', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-cli-sidecar-archive-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final bundleDir = Directory(p.join(tempDir.path, 'bundle'));
    await bundleDir.create();
    final archive = File(p.join(bundleDir.path, 'alera.gz'));
    final executableBytes = utf8.encode('#!/bin/sh\necho alera\n');
    await archive.writeAsBytes(gzip.encode(executableBytes), flush: true);
    final resolver = DefaultAleraCliResolver(
      environment: <String, String>{'ALERA_CLI_BUNDLE_DIR': bundleDir.path},
      operatingSystem: 'linux',
      resolvedExecutable: p.join(tempDir.path, 'alera-app'),
      currentDirectoryPath: tempDir.path,
    );

    final first = await resolver.resolve(
      runtimeDir: p.join(tempDir.path, 'support', 'terminal_host'),
    );
    final second = await resolver.resolve(
      runtimeDir: p.join(tempDir.path, 'support', 'terminal_host'),
    );

    expect(await File(first.executable).readAsBytes(), executableBytes);
    expect(second.executable, first.executable);
    expect((await File(first.executable).stat()).mode & 0x40, isNot(0));
  });
}
