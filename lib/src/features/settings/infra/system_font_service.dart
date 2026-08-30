import 'dart:convert';
import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';

abstract interface class SystemFontService {
  Future<List<String>> listFontFamilies();
}

class IoSystemFontService(
  final ProcessRunner _processRunner, {
  String? platform,
}) implements SystemFontService {
  this : _platform = platform ?? Platform.operatingSystem;

  final String _platform;
  List<String>? _cache;
  Future<List<String>>? _pending;

  @override
  Future<List<String>> listFontFamilies() {
    final cached = _cache;
    if (cached != null) {
      return Future<List<String>>.value(cached);
    }
    final pending = _pending;
    if (pending != null) {
      return pending;
    }
    final next = _loadFontFamilies()
        .then((fonts) {
          final resolved = fonts.isEmpty
              ? fallbackTerminalFontFamilies(_platform)
              : fonts;
          _cache = resolved;
          return resolved;
        })
        .catchError((_) {
          final fallback = fallbackTerminalFontFamilies(_platform);
          _cache = fallback;
          return fallback;
        })
        .whenComplete(() => _pending = null);
    _pending = next;
    return next;
  }

  Future<List<String>> _loadFontFamilies() async {
    return switch (_platform) {
      'macos' || 'darwin' => _listMacFonts(),
      'windows' => _listWindowsFonts(),
      _ => _listLinuxFonts(),
    };
  }

  Future<List<String>> _listMacFonts() async {
    final output = await _run('system_profiler', <String>[
      'SPFontsDataType',
      '-json',
    ]);
    final decoded = jsonDecode(output);
    if (decoded is! Map) {
      return const <String>[];
    }
    final fonts = decoded['SPFontsDataType'];
    if (fonts is! List) {
      return const <String>[];
    }
    return _uniqueSorted(
      fonts.expand((font) {
        if (font is! Map) {
          return const Iterable<String?>.empty();
        }
        final typefaces = font['typefaces'];
        if (typefaces is! List) {
          return const Iterable<String?>.empty();
        }
        return typefaces.map((typeface) {
          if (typeface is! Map) {
            return null;
          }
          return typeface['family'] as String?;
        });
      }),
    );
  }

  Future<List<String>> _listLinuxFonts() async {
    final output = await _run('fc-list', const <String>[':', 'family']);
    return _uniqueSorted(
      output
          .split('\n')
          .expand((line) => line.split(','))
          .map((value) => value.trim()),
    );
  }

  Future<List<String>> _listWindowsFonts() async {
    const script = '''
Add-Type -AssemblyName System.Drawing
\$fonts = New-Object System.Drawing.Text.InstalledFontCollection
\$fonts.Families | ForEach-Object { \$_.Name }
''';
    final output = await _run('powershell.exe', const <String>[
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    return _uniqueSorted(output.split('\n').map((value) => value.trim()));
  }

  Future<String> _run(String executable, List<String> arguments) async {
    final result = await _processRunner.run(executable, arguments);
    if (result.exitCode != 0) {
      throw StateError(result.stderr.trim());
    }
    return result.stdout;
  }
}

List<String> fallbackTerminalFontFamilies([String? platform]) {
  return switch (platform ?? Platform.operatingSystem) {
    'macos' || 'darwin' => const <String>[
      'SF Mono',
      'Menlo',
      'Monaco',
      'JetBrains Mono',
      'Fira Code',
      'monospace',
    ],
    'windows' => const <String>[
      'Cascadia Mono',
      'Consolas',
      'Lucida Console',
      'JetBrains Mono',
      'Fira Code',
      'monospace',
    ],
    _ => const <String>[
      'JetBrains Mono',
      'Fira Code',
      'DejaVu Sans Mono',
      'Liberation Mono',
      'Ubuntu Mono',
      'Noto Sans Mono',
      'monospace',
    ],
  };
}

List<String> _uniqueSorted(Iterable<String?> values) {
  return List<String>.unmodifiableOf(
    Set<String>.from(
      values
          .map((value) => value?.trim() ?? '')
          .where((value) => value.isNotEmpty && !value.startsWith('.')),
    ).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
  );
}
