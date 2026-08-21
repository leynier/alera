import 'dart:io';

import 'package:build_tool/src/android_environment.dart';
import 'package:build_tool/src/target.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('provides the matching CMake ABI for every Android target', () async {
    final sdkDirectory = Directory.systemTemp.createTempSync(
      'alera-android-environment-test-',
    );
    addTearDown(() => sdkDirectory.deleteSync(recursive: true));

    const ndkVersion = '28.2.13676358';
    final hostArchitecture = Platform.isMacOS
        ? 'darwin-x86_64'
        : Platform.isLinux
            ? 'linux-x86_64'
            : 'windows-x86_64';
    final toolchainDirectory = Directory(
      path.join(
        sdkDirectory.path,
        'ndk',
        ndkVersion,
        'toolchains',
        'llvm',
        'prebuilt',
        hostArchitecture,
        'bin',
      ),
    )..createSync(recursive: true);
    File(
      path.join(
        toolchainDirectory.path,
        Platform.isWindows ? 'llvm-ar.exe' : 'llvm-ar',
      ),
    ).createSync();

    for (final target in Target.androidTargets()) {
      final environment = await AndroidEnvironment(
        sdkPath: sdkDirectory.path,
        ndkVersion: ndkVersion,
        minSdkVersion: 24,
        targetTempDir: path.join(sdkDirectory.path, 'target'),
        target: target,
      ).buildEnvironment();

      final toolchainFile = File(environment['CMAKE_TOOLCHAIN_FILE']!);
      expect(
        toolchainFile.readAsStringSync(),
        contains(
          'set(ANDROID_ABI [=[${target.android}]=] CACHE STRING [[]] FORCE)',
        ),
      );
    }
  });

  test('resolves the matching shared C++ runtime for every Android ABI', () {
    final sdkDirectory = Directory.systemTemp.createTempSync(
      'alera-android-cxx-runtime-test-',
    );
    addTearDown(() => sdkDirectory.deleteSync(recursive: true));

    const ndkVersion = '28.2.13676358';
    const expectedTriples = <String, String>{
      'armeabi-v7a': 'arm-linux-androideabi',
      'arm64-v8a': 'aarch64-linux-android',
      'x86': 'i686-linux-android',
      'x86_64': 'x86_64-linux-android',
    };

    for (final target in Target.androidTargets()) {
      final runtime = AndroidEnvironment(
        sdkPath: sdkDirectory.path,
        ndkVersion: ndkVersion,
        minSdkVersion: 24,
        targetTempDir: path.join(sdkDirectory.path, 'target'),
        target: target,
      ).sharedCxxRuntime();

      expect(
        path.normalize(runtime.path),
        endsWith(
          path.join(
            'sysroot',
            'usr',
            'lib',
            expectedTriples[target.android]!,
            'libc++_shared.so',
          ),
        ),
      );
    }
  });
}
