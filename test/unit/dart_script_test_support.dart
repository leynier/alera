import 'dart:io';

import 'package:path/path.dart' as p;

String dartScriptTestExecutable() {
  final resolvedExecutable = Platform.resolvedExecutable;
  final resolvedName = p.basenameWithoutExtension(resolvedExecutable);
  if (resolvedName.toLowerCase().startsWith('dart')) {
    return resolvedExecutable;
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT']?.trim();
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final executable = p.join(
      flutterRoot,
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      Platform.isWindows ? 'dart.exe' : 'dart',
    );
    if (File(executable).existsSync()) {
      return executable;
    }
  }
  return 'dart';
}
