part of 'agent_runtime_overlay_service.dart';

extension _AgentRuntimeOverlayShell on AgentRuntimeOverlayService {
  String? _readShellStartupEnvVar(String name) {
    if (_platform == ManagedAgentHookPlatform.windows) {
      return null;
    }
    final shell = _trimmedEnvironmentValue('SHELL');
    final paths = _shellStartupFilePaths(shell);
    String? last;
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      try {
        final match = _parseExportedValue(file.readAsStringSync(), name);
        if (match != null) {
          last = match;
        }
      } catch (_) {}
    }
    return last;
  }

  List<String> _shellStartupFilePaths(String? shell) {
    final name = shell?.replaceAll(r'\', '/').split('/').last.toLowerCase();
    if (name == null || name == 'zsh') {
      final zshEnvPath = p.join(_homeDirectory, '.zshenv');
      final zshEnv = File(zshEnvPath).existsSync()
          ? File(zshEnvPath).readAsStringSync()
          : '';
      final zdotdir = _parseExportedValue(zshEnv, 'ZDOTDIR') ?? _homeDirectory;
      return <String>[
        zshEnvPath,
        for (final file in const <String>['.zprofile', '.zshrc', '.zlogin'])
          p.join(zdotdir, file),
      ];
    }
    if (name == 'bash') {
      return <String>[
        p.join(_homeDirectory, '.bash_profile'),
        p.join(_homeDirectory, '.bash_login'),
        p.join(_homeDirectory, '.profile'),
        p.join(_homeDirectory, '.bashrc'),
      ];
    }
    return const <String>[];
  }

  String? _parseExportedValue(String content, String name) {
    final assignment = RegExp('^export\\s+$name=(.+)\$');
    String? last;
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final match = assignment.firstMatch(rawLine.trim());
      if (match == null) {
        continue;
      }
      final decommented = _stripTrailingComment(match.group(1) ?? '');
      final unquoted = _unquoteShellValue(decommented.trim());
      final expanded = unquoted.quoted == "'"
          ? unquoted.text
          : _expandHome(unquoted.text);
      if (expanded.isNotEmpty) {
        last = expanded;
      }
    }
    return last;
  }

  _ShellValue _unquoteShellValue(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return _ShellValue(value.substring(1, value.length - 1), value[0]);
    }
    return _ShellValue(value, null);
  }

  String _stripTrailingComment(String value) {
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < value.length; i += 1) {
      final ch = value[i];
      if (ch == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (ch == '#' && !inSingle && !inDouble) {
        final previous = i == 0 ? null : value[i - 1];
        if (previous == null || previous == ' ' || previous == '\t') {
          return value.substring(0, i).trimRight();
        }
      }
    }
    return value;
  }

  String _expandHome(String value) {
    return value
        .replaceFirst(RegExp(r'^~(?=$|/)'), _homeDirectory)
        .replaceAll(r'${HOME}', _homeDirectory)
        .replaceAll(RegExp(r'\$HOME(?![A-Za-z0-9_])'), _homeDirectory);
  }

  String _shQuote(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _cmdEnvValue(String value) {
    return value.replaceAll('"', '""');
  }
}
