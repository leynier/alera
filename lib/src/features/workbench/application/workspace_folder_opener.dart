import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';

enum WorkspaceFolderPlatform { macos, windows, linux, other }

class WorkspaceFolderOpenResult {
  const WorkspaceFolderOpenResult._({required this.ok, this.message});

  const WorkspaceFolderOpenResult.success() : this._(ok: true);

  const WorkspaceFolderOpenResult.failure(String message)
    : this._(ok: false, message: message);

  final bool ok;
  final String? message;
}

class WorkspaceFolderOpener {
  WorkspaceFolderOpener({
    required this.processRunner,
    WorkspaceFolderPlatform? platform,
    Future<bool> Function(String path)? directoryExists,
  }) : _platform = platform ?? currentWorkspaceFolderPlatform(),
       _directoryExists =
           directoryExists ?? ((path) async => Directory(path).exists());

  final ProcessRunner processRunner;
  final WorkspaceFolderPlatform _platform;
  final Future<bool> Function(String path) _directoryExists;

  String get fileManagerLabel {
    switch (_platform) {
      case WorkspaceFolderPlatform.macos:
        return 'Finder';
      case WorkspaceFolderPlatform.windows:
        return 'Explorer';
      case WorkspaceFolderPlatform.linux:
      case WorkspaceFolderPlatform.other:
        return 'File Manager';
    }
  }

  Future<WorkspaceFolderOpenResult> open(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return const WorkspaceFolderOpenResult.failure(
        'Workspace path is empty.',
      );
    }
    if (!await _directoryExists(normalized)) {
      return const WorkspaceFolderOpenResult.failure(
        'Workspace folder was not found.',
      );
    }

    final commands = _commandsForPlatform(normalized);
    for (final command in commands) {
      try {
        final result = await processRunner.run(
          command.executable,
          command.arguments,
        );
        if (result.exitCode == 0) {
          return const WorkspaceFolderOpenResult.success();
        }
      } catch (_) {
        continue;
      }
    }
    return WorkspaceFolderOpenResult.failure(
      'Could not open workspace folder in $fileManagerLabel.',
    );
  }

  Future<WorkspaceFolderOpenResult> reveal(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return const WorkspaceFolderOpenResult.failure('Path is empty.');
    }
    if (!await FileSystemEntity.type(
      normalized,
    ).then((type) => type != FileSystemEntityType.notFound)) {
      return const WorkspaceFolderOpenResult.failure('Path was not found.');
    }

    final commands = _revealCommandsForPlatform(normalized);
    for (final command in commands) {
      try {
        final result = await processRunner.run(
          command.executable,
          command.arguments,
        );
        if (result.exitCode == 0) {
          return const WorkspaceFolderOpenResult.success();
        }
      } catch (_) {
        continue;
      }
    }
    return WorkspaceFolderOpenResult.failure(
      'Could not reveal item in $fileManagerLabel.',
    );
  }

  List<_WorkspaceFolderOpenCommand> _commandsForPlatform(String path) {
    switch (_platform) {
      case WorkspaceFolderPlatform.macos:
        return <_WorkspaceFolderOpenCommand>[
          _WorkspaceFolderOpenCommand('open', <String>[path]),
        ];
      case WorkspaceFolderPlatform.windows:
        return <_WorkspaceFolderOpenCommand>[
          _WorkspaceFolderOpenCommand('explorer.exe', <String>[path]),
        ];
      case WorkspaceFolderPlatform.linux:
        return <_WorkspaceFolderOpenCommand>[
          _WorkspaceFolderOpenCommand('xdg-open', <String>[path]),
          _WorkspaceFolderOpenCommand('gio', <String>['open', path]),
        ];
      case WorkspaceFolderPlatform.other:
        return <_WorkspaceFolderOpenCommand>[
          _WorkspaceFolderOpenCommand('xdg-open', <String>[path]),
        ];
    }
  }

  List<_WorkspaceFolderOpenCommand> _revealCommandsForPlatform(String path) {
    switch (_platform) {
      case WorkspaceFolderPlatform.macos:
        return <_WorkspaceFolderOpenCommand>[
          _WorkspaceFolderOpenCommand('open', <String>['-R', path]),
        ];
      case WorkspaceFolderPlatform.windows:
        return <_WorkspaceFolderOpenCommand>[
          _WorkspaceFolderOpenCommand('explorer.exe', <String>[
            '/select,$path',
          ]),
        ];
      case WorkspaceFolderPlatform.linux:
        final target = _fileManagerTargetForReveal(path);
        return <_WorkspaceFolderOpenCommand>[
          _showItemsCommand(path),
          _WorkspaceFolderOpenCommand('xdg-open', <String>[target]),
          _WorkspaceFolderOpenCommand('gio', <String>['open', target]),
        ];
      case WorkspaceFolderPlatform.other:
        final target = _fileManagerTargetForReveal(path);
        return <_WorkspaceFolderOpenCommand>[
          _WorkspaceFolderOpenCommand('xdg-open', <String>[target]),
        ];
    }
  }

  String _fileManagerTargetForReveal(String path) {
    return FileSystemEntity.isDirectorySync(path)
        ? path
        : File(path).parent.path;
  }
}

/// FreeDesktop FileManager1.ShowItems selects the path in the session file
/// manager (Nautilus, Dolphin, ...). The GVariant array is one argv token so
/// ProcessRunner shell-quoting leaves it intact for `gdbus`.
_WorkspaceFolderOpenCommand _showItemsCommand(String path) {
  final uri = Uri.file(path).toString();
  return _WorkspaceFolderOpenCommand('gdbus', <String>[
    'call',
    '--session',
    '--dest',
    'org.freedesktop.FileManager1',
    '--object-path',
    '/org/freedesktop/FileManager1',
    '--method',
    'org.freedesktop.FileManager1.ShowItems',
    "['$uri']",
    '',
  ]);
}

WorkspaceFolderPlatform currentWorkspaceFolderPlatform() {
  return workspaceFolderPlatformForOperatingSystem(Platform.operatingSystem);
}

WorkspaceFolderPlatform workspaceFolderPlatformForOperatingSystem(
  String operatingSystem,
) {
  return switch (operatingSystem) {
    'macos' => WorkspaceFolderPlatform.macos,
    'windows' => WorkspaceFolderPlatform.windows,
    'linux' => WorkspaceFolderPlatform.linux,
    _ => WorkspaceFolderPlatform.other,
  };
}

class _WorkspaceFolderOpenCommand {
  const _WorkspaceFolderOpenCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
