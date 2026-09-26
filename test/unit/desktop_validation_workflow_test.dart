import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final workflow = loadYaml(
    File('.github/workflows/desktop-build.yml').readAsStringSync(),
  ) as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;
  List<YamlMap> steps(String job) =>
      ((jobs[job] as YamlMap)['steps'] as YamlList).cast<YamlMap>();
  YamlMap step(String job, String name) =>
      steps(job).singleWhere((step) => step['name'] == name);

  test('manual and reusable calls preserve the build-only default', () {
    final triggers = workflow['on'] as YamlMap;
    for (final trigger in ['workflow_call', 'workflow_dispatch']) {
      final inputs = triggers[trigger]['inputs'] as YamlMap;
      expect(inputs['source_sha']['type'], 'string');
      expect(inputs['source_sha']['default'], '');
      expect(inputs['full_validation']['type'], 'boolean');
      expect(inputs['full_validation']['default'], false);
    }
    expect(workflow['permissions'], {'contents': 'read'});
    expect(jobs['golden']['if'], 'inputs.full_validation');
    expect(jobs['desktop_e2e_linux']['if'], 'inputs.full_validation');
  });

  test(
    'explicit validation concurrency follows the actual triggering commit',
    () {
      expect(
        workflow['concurrency']['group'],
        r"desktop-builds-${{ github.event.pull_request.number || github.ref }}-${{ inputs.source_sha && github.sha || '' }}-${{ inputs.full_validation }}",
      );
      expect(workflow['concurrency']['cancel-in-progress'], isTrue);
    },
  );

  test('every validation job uses the resolved immutable revision', () {
    for (final job in [
      'build',
      'windows_native_smoke',
      'golden',
      'desktop_e2e_linux',
    ]) {
      expect(jobs[job]['needs'], 'revision');
      final checkout = step(job, 'Checkout')['with'];
      expect(checkout['ref'], r'${{ github.sha }}');
      expect(checkout['submodules'], false);
      expect(checkout['persist-credentials'], false);
    }
    final revisionSteps = steps('revision');
    expect(revisionSteps.first['name'], 'Require an immutable revision');
    expect(step('revision', 'Checkout')['with']['ref'], r'${{ github.sha }}');
    expect(
      jobs['revision']['outputs']['sha'],
      r'${{ steps.revision.outputs.sha }}',
    );
  });

  test('uses native builds and the shared test prologues', () {
    expect(workflow['env']['ALERA_FLAVOR'], 'release');
    expect(jobs['desktop_e2e_linux']['env']['ALERA_FLAVOR'], 'dev');
    final platforms =
        (jobs['build']['strategy']['matrix']['include'] as YamlList)
            .cast<YamlMap>();
    expect(
      {for (final row in platforms) row['platform']: row['os']},
      {
        'linux': 'ubuntu-latest',
        'macos': 'macos-latest',
        'windows': 'windows-latest',
      },
    );
    for (final job in [
      'build',
      'windows_native_smoke',
      'golden',
      'desktop_e2e_linux',
    ]) {
      expect(
        step(job, 'Setup Flutter workspace')['uses'],
        './.github/actions/setup-flutter-workspace',
      );
    }
    expect(
      step('golden', 'Setup Flutter workspace')['with']['linux-toolchain'],
      'false',
    );
    for (final job in ['build', 'windows_native_smoke', 'desktop_e2e_linux']) {
      expect(step(job, 'Setup Flutter workspace')['with']['rust'], 'true');
    }
    final e2e = step('desktop_e2e_linux', 'Desktop E2E')['run'] as String;
    expect(e2e, contains('for suite in integration_test/*_test.dart'));
    expect(e2e, contains(r'flutter test "${suite}" -d linux'));
  });

  test('native build budgets include separate integration suite rebuilds', () {
    expect(jobs['build']['timeout-minutes'], r'${{ matrix.timeout_minutes }}');
    final platforms =
        (jobs['build']['strategy']['matrix']['include'] as YamlList)
            .cast<YamlMap>();
    expect(
      {for (final row in platforms) row['platform']: row['timeout_minutes']},
      {'macos': 180, 'windows': 120, 'linux': 90},
    );
    expect(jobs['build']['strategy']['fail-fast'], false);
  });

  test('full validation cannot skip a failed prerequisite', () {
    expect(jobs['validation_ready']['needs'], [
      'revision',
      'build',
      'windows_native_smoke',
      'golden',
      'desktop_e2e_linux',
    ]);
    expect(
      jobs['validation_ready']['if'],
      r'${{ always() && inputs.full_validation }}',
    );
    final gateEnv = step(
      'validation_ready',
      'Require all validation jobs',
    )['env'];
    for (final entry in {
      'REVISION_RESULT': 'revision',
      'BUILD_RESULT': 'build',
      'WINDOWS_NATIVE_RESULT': 'windows_native_smoke',
      'GOLDEN_RESULT': 'golden',
      'E2E_RESULT': 'desktop_e2e_linux',
    }.entries) {
      expect(gateEnv[entry.key], '\${{ needs.${entry.value}.result }}');
    }
  });

  test('native desktop validation has bounded platform budgets', () {
    final build = jobs['build'] as YamlMap;
    expect(build['timeout-minutes'], r'${{ matrix.timeout_minutes }}');
    final platforms = (build['strategy']['matrix']['include'] as YamlList)
        .cast<YamlMap>();
    expect(
      {for (final row in platforms) row['platform']: row['timeout_minutes']},
      {'macos': 180, 'windows': 120, 'linux': 90},
    );
    expect(build['continue-on-error'], isNull);
  });

  test('desktop builds execute workflow tests on every platform', () {
    final workflows = step(
      'build',
      'Verify workflow contracts and native Git integration',
    );
    expect(workflows['if'], isNull);
    expect(workflows['continue-on-error'], isNull);
    expect(workflows['run'], contains('-p alera-core --features runtime'));
    expect(workflows['run'], contains('--lib workflow_'));
    expect(workflows['run'], contains('--locked'));
  });

  test(
    'native clipboard coverage opts in only on disposable runner desktops',
    () {
      final e2e = step('desktop_e2e_linux', 'Desktop E2E');
      expect(e2e['env']['ALERA_NATIVE_TEST_CLIPBOARD'], '1');
      expect(e2e['run'], contains('xvfb-run -a flutter test'));
      final native = step(
        'build',
        'Verify native process boundary and workbench flow',
      );
      expect(native['env']['ALERA_NATIVE_TEST_CLIPBOARD'], '1');
      expect(native['if'], "matrix.platform != 'windows'");
      expect(
        native['run'],
        contains(
          'rust_process_runner_test alera_smoke_flow_test terminal_input_native_test',
        ),
      );
      expect(native['run'], contains('xvfb-run -a flutter test'));
      final windows = jobs['windows_native_smoke'] as YamlMap;
      expect(windows['runs-on'], 'windows-latest');
      expect(windows['strategy']['fail-fast'], false);
      expect(windows['strategy']['matrix']['suite'], [
        'rust_process_runner_test',
        'alera_smoke_flow_test',
        'terminal_input_native_test',
      ]);
      expect(windows['env']['ALERA_NATIVE_TEST_CLIPBOARD'], '1');
      expect(
        step(
          'windows_native_smoke',
          'Verify native suite on a fresh runner',
        )['run'],
        r'flutter test integration_test/${{ matrix.suite }}.dart -d windows --reporter expanded',
      );
      expect(
        workflow['env'].containsKey('ALERA_NATIVE_TEST_CLIPBOARD'),
        isFalse,
      );
    },
  );

  test('exact revision builds retain native visual and runner checks', () {
    expect(step('build', 'Setup Flutter workspace')['with']['xvfb'], 'true');
    final typography = step(
      'build',
      'Capture native typography at three scales',
    );
    expect(typography['env']['ALERA_FLAVOR'], 'dev');
    expect(
      typography['run'],
      contains('integration_test/typography_rendering_test.dart'),
    );
    expect(
      step(
        'build',
        'Upload native typography captures',
      )['with']['if-no-files-found'],
      'error',
    );
    final macos = step('build', 'Verify macOS startup and desktop presence');
    expect(macos['if'], "matrix.platform == 'macos'");
    expect(macos['env']['ALERA_FLAVOR'], 'dev');
    expect(
      step('build', 'Verify Windows single-instance runner')['if'],
      "matrix.platform == 'windows'",
    );
  });

  group('ubuntu revision and completion guards', () {
    test('rejects mutable refs and malformed SHAs', () {
      final script =
          step('revision', 'Require an immutable revision')['run'] as String;
      final sha = '0123456789abcdef0123456789abcdef01234567';
      for (final value in [
        sha,
        'ffffffffffffffffffffffffffffffffffffffff',
        'main',
        'v1.0.0',
        'abc123',
        '',
        '$sha\nmain',
      ]) {
        final result = Process.runSync(
          'bash',
          ['-c', script],
          environment: {
            'SOURCE_SHA': value,
            'TRIGGER_SHA': sha,
            'FULL_VALIDATION': 'true',
          },
        );
        expect(result.exitCode, value == sha ? 0 : 1, reason: value);
      }
    });

    test('only build-only runs allow an unnamed triggering revision', () {
      final revision = step('revision', 'Require an immutable revision');
      expect(revision['env']['SOURCE_SHA'], r'${{ inputs.source_sha }}');
      expect(
        revision['env']['FULL_VALIDATION'],
        r'${{ inputs.full_validation }}',
      );
      for (final fullValidation in ['true', 'false']) {
        final result = Process.runSync(
          'bash',
          ['-c', revision['run'] as String],
          environment: {
            'SOURCE_SHA': '',
            'TRIGGER_SHA': '0123456789abcdef0123456789abcdef01234567',
            'FULL_VALIDATION': fullValidation,
          },
        );
        expect(result.exitCode, fullValidation == 'true' ? 1 : 0);
      }
    });

    test('fails closed for failure, cancelled, skipped and missing jobs', () {
      final script =
          step('validation_ready', 'Require all validation jobs')['run']
              as String;
      final directory = Directory.systemTemp.createTempSync('alera-ci-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final results = {
        'REVISION_RESULT': 'success',
        'BUILD_RESULT': 'success',
        'WINDOWS_NATIVE_RESULT': 'success',
        'GOLDEN_RESULT': 'success',
        'E2E_RESULT': 'success',
      };
      for (final key in results.keys) {
        for (final status in [
          'success',
          'failure',
          'cancelled',
          'skipped',
          '',
        ]) {
          final result = Process.runSync(
            'bash',
            ['-c', script],
            environment: {
              ...results,
              key: status,
              'SOURCE_SHA': '0123456789abcdef0123456789abcdef01234567',
              'GITHUB_STEP_SUMMARY': '${directory.path}/summary',
            },
          );
          expect(result.exitCode, status == 'success' ? 0 : 1);
        }
      }
    });
  }, skip: Platform.isWindows ? 'These guards run on Ubuntu only.' : false);
}
