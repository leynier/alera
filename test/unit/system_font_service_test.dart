import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IoSystemFontService', () {
    test('parses macOS system profiler font families', () async {
      final runner = _FakeProcessRunner(
        stdout: '''
{
  "SPFontsDataType": [
    {
      "typefaces": [
        { "family": "Menlo" },
        { "family": "SF Mono" },
        { "family": "Menlo" },
        { "family": ".Hidden" }
      ]
    }
  ]
}
''',
      );
      final service = IoSystemFontService(runner, platform: 'darwin');

      final fonts = await service.listFontFamilies();

      expect(fonts, <String>['Menlo', 'SF Mono']);
      expect(runner.calls.single.executable, 'system_profiler');
      expect(runner.calls.single.arguments, <String>[
        'SPFontsDataType',
        '-json',
      ]);
    });

    test('parses Linux fc-list font families', () async {
      final runner = _FakeProcessRunner(
        stdout: '''
JetBrains Mono,JetBrains Mono NL
Fira Code
JetBrains Mono
''',
      );
      final service = IoSystemFontService(runner, platform: 'linux');

      final fonts = await service.listFontFamilies();

      expect(fonts, <String>[
        'Fira Code',
        'JetBrains Mono',
        'JetBrains Mono NL',
      ]);
      expect(runner.calls.single.executable, 'fc-list');
    });

    test('falls back and caches when platform command fails', () async {
      final runner = _FakeProcessRunner(exitCode: 1, stderr: 'missing command');
      final service = IoSystemFontService(runner, platform: 'windows');

      final first = await service.listFontFamilies();
      final second = await service.listFontFamilies();

      expect(first, fallbackTerminalFontFamilies('windows'));
      expect(second, same(first));
      expect(runner.calls, hasLength(1));
    });

    test(
      'falls back when a platform command returns no font families',
      () async {
        final runner = _FakeProcessRunner(stdout: '\n');
        final service = IoSystemFontService(runner, platform: 'linux');

        final fonts = await service.listFontFamilies();

        expect(fonts, fallbackTerminalFontFamilies('linux'));
        expect(runner.calls.single.executable, 'fc-list');
      },
    );

    test('parses Windows font families from powershell output', () async {
      final runner = _FakeProcessRunner(
        stdout: '''
Consolas
JetBrains Mono
Consolas

''',
      );
      final service = IoSystemFontService(runner, platform: 'windows');

      final fonts = await service.listFontFamilies();

      expect(fonts, <String>['Consolas', 'JetBrains Mono']);
      expect(runner.calls.single.executable, 'powershell.exe');
    });
  });
}

class _ProcessRunCall {
  const _ProcessRunCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner({this.stdout = '', this.stderr = '', this.exitCode = 0});

  final String stdout;
  final String stderr;
  final int exitCode;
  final List<_ProcessRunCall> calls = <_ProcessRunCall>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(_ProcessRunCall(executable, arguments));
    return ProcessRunOutput(exitCode: exitCode, stdout: stdout, stderr: stderr);
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) {
    throw UnimplementedError();
  }
}
