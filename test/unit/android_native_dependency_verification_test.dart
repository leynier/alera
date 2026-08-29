import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final script = File('tool/release/verify_android_native_dependencies.sh');

  test(
    'release cuts verify Android native dependencies through the script',
    () {
      final workflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();

      expect(
        workflow,
        contains(
          'bash tool/release/verify_android_native_dependencies.sh '
          'mobile/build/app/outputs/flutter-apk',
        ),
      );
      expect(
        workflow,
        isNot(contains(r'find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt"')),
      );
    },
  );

  test('rejects a directory with no release APKs', () {
    if (Platform.isWindows) {
      return;
    }
    final temp = Directory.systemTemp.createTempSync(
      'alera-android-native-verify-empty-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));

    final result = Process.runSync('bash', <String>[script.path, temp.path]);
    expect(result.exitCode, isNot(0), reason: result.stderr.toString());
    expect(result.stderr, contains('No Android release APKs found'));
  });

  test('rejects an APK that omits the shared C++ runtime', () {
    if (Platform.isWindows) {
      return;
    }

    final temp = Directory.systemTemp.createTempSync(
      'alera-android-native-verify-missing-cxx-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final native = File(p.join(temp.path, 'libalera_mobile_native.so'))
      ..writeAsStringSync('not a real elf');
    final apk = File(p.join(temp.path, 'app-arm64-v8a-release.apk'));
    _zipApk(apk, <String, File>{
      'lib/arm64-v8a/libalera_mobile_native.so': native,
    });

    final result = Process.runSync('bash', <String>[script.path, temp.path]);
    expect(result.exitCode, isNot(0), reason: result.stderr.toString());
    expect(result.stderr, contains('missing lib/*/libc++_shared.so'));
  });

  test('rejects a native library that does not need libc++_shared.so', () {
    if (!Platform.isLinux) {
      return;
    }
    final gcc = _gcc();
    if (gcc == null) {
      return;
    }

    final temp = Directory.systemTemp.createTempSync(
      'alera-android-native-verify-unlinked-cxx-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final native = _compileSharedLibrary(
      gcc: gcc,
      directory: temp,
      name: 'libalera_mobile_native.so',
      needed: const <String>[],
    );
    final runtime = _compileSharedLibrary(
      gcc: gcc,
      directory: temp,
      name: 'libc++_shared.so',
      needed: const <String>[],
    );
    final apk = File(p.join(temp.path, 'app-arm64-v8a-release.apk'));
    _zipApk(apk, <String, File>{
      'lib/arm64-v8a/libalera_mobile_native.so': native,
      'lib/arm64-v8a/libc++_shared.so': runtime,
    });

    final result = Process.runSync('bash', <String>[script.path, temp.path]);
    expect(result.exitCode, isNot(0), reason: result.stderr.toString());
    expect(result.stderr, contains('does not declare NEEDED libc++_shared.so'));
  });

  test('accepts APKs that bundle libc++_shared.so for every ABI', () {
    if (!Platform.isLinux) {
      return;
    }
    final gcc = _gcc();
    if (gcc == null) {
      return;
    }

    final temp = Directory.systemTemp.createTempSync(
      'alera-android-native-verify-ok-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final runtime = _compileSharedLibrary(
      gcc: gcc,
      directory: temp,
      name: 'libc++_shared.so',
      needed: const <String>[],
    );
    final native = _compileSharedLibrary(
      gcc: gcc,
      directory: temp,
      name: 'libalera_mobile_native.so',
      needed: <String>[runtime.path],
    );

    for (final apkName in <String>[
      'app-release.apk',
      'app-arm64-v8a-release.apk',
    ]) {
      final apk = File(p.join(temp.path, apkName));
      _zipApk(apk, <String, File>{
        'lib/arm64-v8a/libalera_mobile_native.so': native,
        'lib/arm64-v8a/libc++_shared.so': runtime,
        'lib/armeabi-v7a/libalera_mobile_native.so': native,
        'lib/armeabi-v7a/libc++_shared.so': runtime,
      });
    }

    final result = Process.runSync('bash', <String>[script.path, temp.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('links against bundled libc++_shared.so'));
  });
}

String? _gcc() {
  final result = Process.runSync('gcc', const <String>['--version']);
  if (result.exitCode != 0) {
    return null;
  }
  return 'gcc';
}

File _compileSharedLibrary({
  required String gcc,
  required Directory directory,
  required String name,
  required List<String> needed,
}) {
  final marker = name.replaceAll(RegExp('[^A-Za-z]'), '_');
  final source = File(p.join(directory.path, '$name.c'))
    ..writeAsStringSync('void ${marker}_marker(void) {}\n');
  final output = File(p.join(directory.path, name));
  final args = <String>[
    '-fPIC',
    '-shared',
    '-Wl,-soname,$name',
    '-o',
    output.path,
    source.path,
  ];
  if (needed.isNotEmpty) {
    args.add('-Wl,--no-as-needed');
    for (final library in needed) {
      final fileName = p.basename(library);
      final linkName = fileName
          .replaceFirst(RegExp('^lib'), '')
          .replaceFirst(RegExp(r'\.so$'), '');
      args.addAll(<String>['-L${p.dirname(library)}', '-l$linkName']);
    }
  }
  final result = Process.runSync(gcc, args);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  expect(output.existsSync(), isTrue);
  return output;
}

void _zipApk(File apk, Map<String, File> entries) {
  final staging = Directory(p.join(apk.parent.path, '${apk.path}.staging'))
    ..createSync();
  for (final entry in entries.entries) {
    final destination = File(p.join(staging.path, entry.key))
      ..parent.createSync(recursive: true);
    entry.value.copySync(destination.path);
  }
  final result = Process.runSync('zip', <String>[
    '-qr',
    apk.path,
    '.',
  ], workingDirectory: staging.path);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}
