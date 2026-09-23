import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _setupScript = 'tool/development/setup_windows.ps1';
const String _vulkanHelper = 'tool/development/setup_windows_vulkan.ps1';
const String _vulkanHelperTest = 'test/fixtures/setup_windows_vulkan_test.ps1';

String? _findPwsh() {
  final name = Platform.isWindows ? 'pwsh.exe' : 'pwsh';
  final separator = Platform.isWindows ? ';' : ':';
  for (final directory in (Platform.environment['PATH'] ?? '').split(
    separator,
  )) {
    if (directory.isEmpty) {
      continue;
    }
    final candidate = p.join(directory, name);
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

void main() {
  final pwsh = _findPwsh();

  test(
    'Vulkan SDK discovery keeps every candidate and waits for the installer',
    () async {
      final result = await Process.run(pwsh!, <String>[
        '-NoProfile',
        '-NonInteractive',
        '-File',
        _vulkanHelperTest,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: pwsh == null ? 'PowerShell 7 (pwsh) is not on PATH.' : false,
  );

  test('setup script waits for the Vulkan SDK after installing it', () {
    final source = File(_setupScript).readAsStringSync();

    expect(
      source,
      contains(r". (Join-Path $PSScriptRoot 'setup_windows_vulkan.ps1')"),
    );
    // The old inline discovery is gone; the helper owns it.
    expect(source, isNot(contains('function Get-VulkanSdkDirectory')));
    expect(source, isNot(contains(r'$candidates +=')));
    expect(
      source,
      matches(
        RegExp(
          r'if \(\$null -eq \$vulkanSdkDirectory -and -not \$CheckOnly\) \{\r?\n'
          r'\s+Install-VulkanSdk\r?\n'
          r'[\s\S]*?'
          r'\s+\$vulkanSdkDirectory = Wait-VulkanSdkDirectory -RequiredVersion \$requiredVulkanSdkVersion\r?\n'
          r'\}',
        ),
      ),
    );
  });

  test('Vulkan helper collects candidates without scalar concatenation', () {
    final helper = File(_vulkanHelper).readAsStringSync();

    expect(helper, contains('System.Collections.Generic.List[string]'));
    expect(helper, contains("GetEnvironmentVariable('VULKAN_SDK', 'Machine')"));
    expect(helper, isNot(contains('+= Get-ChildItem')));
  });

  test(
    'Windows setup points direct cargo builds at the documented settings',
    () {
      final source = File(_setupScript).readAsStringSync();
      final contributing = File('.github/CONTRIBUTING.md').readAsStringSync();

      expect(source, contains('Direct Cargo builds on Windows'));
      expect(contributing, contains('### Direct Cargo builds on Windows'));
      for (final setting in <String>[
        r"$env:CMAKE_GENERATOR = 'Ninja'",
        r"$env:CMAKE_GENERATOR_x86_64_pc_windows_msvc = 'Ninja'",
        r"$env:_CL_ = '/Z7 /FS'",
        r"$env:GGML_CCACHE = 'OFF'",
        r'$env:CARGO_TARGET_DIR',
      ]) {
        expect(contributing, contains(setting));
      }
    },
  );
}
