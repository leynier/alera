import 'dart:io';

import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses open on macOS', () async {
    final processRunner = _FakeProcessRunner();
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.macos,
      directoryExists: (_) async => true,
    );

    final result = await opener.open('/repo/alera');

    expect(result.ok, isTrue);
    expect(processRunner.calls, <_ProcessCall>[
      const _ProcessCall('open', <String>['/repo/alera']),
    ]);
    expect(opener.fileManagerLabel, 'Finder');
  });

  test('uses the default directory probe when none is injected', () async {
    final processRunner = _FakeProcessRunner();
    final directory = await Directory.systemTemp.createTemp(
      'alera-open-folder-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.macos,
    );

    final result = await opener.open(directory.path);

    expect(result.ok, isTrue);
    expect(processRunner.calls, <_ProcessCall>[
      _ProcessCall('open', <String>[directory.path]),
    ]);
  });

  test('uses explorer on Windows', () async {
    final processRunner = _FakeProcessRunner();
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.windows,
      directoryExists: (_) async => true,
    );

    final result = await opener.open(r'C:\repo\alera');

    expect(result.ok, isTrue);
    expect(processRunner.calls, <_ProcessCall>[
      const _ProcessCall('explorer.exe', <String>[r'C:\repo\alera']),
    ]);
    expect(opener.fileManagerLabel, 'Explorer');
  });

  test('reveals an item in Finder on macOS', () async {
    final processRunner = _FakeProcessRunner();
    final directory = await Directory.systemTemp.createTemp(
      'alera-reveal-item-',
    );
    final file = File('${directory.path}/note.txt');
    await file.writeAsString('note');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.macos,
    );

    final result = await opener.reveal(file.path);

    expect(result.ok, isTrue);
    expect(processRunner.calls, <_ProcessCall>[
      _ProcessCall('open', <String>['-R', file.path]),
    ]);
  });

  test('reveals an item in Explorer on Windows', () async {
    final processRunner = _FakeProcessRunner();
    final directory = await Directory.systemTemp.createTemp(
      'alera-reveal-item-',
    );
    final file = File('${directory.path}/note.txt');
    await file.writeAsString('note');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.windows,
    );

    final result = await opener.reveal(file.path);

    expect(result.ok, isTrue);
    expect(processRunner.calls, <_ProcessCall>[
      _ProcessCall('explorer.exe', <String>['/select,${file.path}']),
    ]);
  });

  test('reveals the parent folder on Linux for files', () async {
    final processRunner = _FakeProcessRunner();
    final directory = await Directory.systemTemp.createTemp(
      'alera-reveal-item-',
    );
    final file = File('${directory.path}/note.txt');
    await file.writeAsString('note');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.linux,
    );

    final result = await opener.reveal(file.path);

    expect(result.ok, isTrue);
    expect(processRunner.calls, <_ProcessCall>[
      _ProcessCall('xdg-open', <String>[directory.path]),
    ]);
  });

  test('falls back to gio on Linux when xdg-open fails', () async {
    final processRunner = _FakeProcessRunner(exitCodes: <int>[1, 0]);
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.linux,
      directoryExists: (_) async => true,
    );

    final result = await opener.open('/repo/alera');

    expect(result.ok, isTrue);
    expect(processRunner.calls, <_ProcessCall>[
      const _ProcessCall('xdg-open', <String>['/repo/alera']),
      const _ProcessCall('gio', <String>['open', '/repo/alera']),
    ]);
    expect(opener.fileManagerLabel, 'File Manager');
  });

  test('does not launch when the workspace folder is missing', () async {
    final processRunner = _FakeProcessRunner();
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.linux,
      directoryExists: (_) async => false,
    );

    final result = await opener.open('/repo/missing');

    expect(result.ok, isFalse);
    expect(result.message, 'Workspace folder was not found.');
    expect(processRunner.calls, isEmpty);
  });

  test('rejects blank workspace paths before probing the filesystem', () async {
    final processRunner = _FakeProcessRunner();
    final opener = WorkspaceFolderOpener(
      processRunner: processRunner,
      platform: WorkspaceFolderPlatform.linux,
      directoryExists: (_) async => true,
    );

    final result = await opener.open('   ');

    expect(result.ok, isFalse);
    expect(result.message, 'Workspace path is empty.');
    expect(processRunner.calls, isEmpty);
  });

  test(
    'reports a clean failure on other platforms when opening fails',
    () async {
      final processRunner = _FakeProcessRunner(exitCodes: <int>[1]);
      final opener = WorkspaceFolderOpener(
        processRunner: processRunner,
        platform: WorkspaceFolderPlatform.other,
        directoryExists: (_) async => true,
      );

      final result = await opener.open('/repo/alera');

      expect(result.ok, isFalse);
      expect(
        result.message,
        'Could not open workspace folder in File Manager.',
      );
      expect(processRunner.calls, <_ProcessCall>[
        const _ProcessCall('xdg-open', <String>['/repo/alera']),
      ]);
      expect(opener.fileManagerLabel, 'File Manager');
    },
  );

  test(
    'detects the current workspace-folder platform for this environment',
    () {
      expect(
        currentWorkspaceFolderPlatform(),
        workspaceFolderPlatformForOperatingSystem(Platform.operatingSystem),
      );
    },
  );

  test('maps operating-system strings to folder platforms', () {
    expect(
      workspaceFolderPlatformForOperatingSystem('windows'),
      WorkspaceFolderPlatform.windows,
    );
    expect(
      workspaceFolderPlatformForOperatingSystem('linux'),
      WorkspaceFolderPlatform.linux,
    );
    expect(
      workspaceFolderPlatformForOperatingSystem('plan9'),
      WorkspaceFolderPlatform.other,
    );
  });
}

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner({List<int>? exitCodes})
    : _exitCodes = exitCodes ?? <int>[0];

  final List<int> _exitCodes;
  final List<_ProcessCall> calls = <_ProcessCall>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(_ProcessCall(executable, arguments));
    final exitCode = calls.length <= _exitCodes.length
        ? _exitCodes[calls.length - 1]
        : _exitCodes.last;
    return ProcessRunOutput(exitCode: exitCode, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

class _ProcessCall {
  const _ProcessCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  @override
  bool operator ==(Object other) {
    return other is _ProcessCall &&
        other.executable == executable &&
        _listEquals(other.arguments, arguments);
  }

  @override
  int get hashCode => Object.hash(executable, Object.hashAll(arguments));
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
