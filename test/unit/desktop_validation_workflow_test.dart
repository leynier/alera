import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final workflow =
      loadYaml(File('.github/workflows/desktop-build.yml').readAsStringSync())
          as YamlMap;
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

  test('every validation job uses the resolved immutable revision', () {
    for (final job in ['build', 'golden', 'desktop_e2e_linux']) {
      expect(jobs[job]['needs'], 'revision');
      final checkout = step(job, 'Checkout')['with'];
      expect(checkout['ref'], r'${{ needs.revision.outputs.sha }}');
      expect(checkout['submodules'], false);
      expect(checkout['persist-credentials'], false);
    }
    final revisionSteps = steps('revision');
    expect(revisionSteps.first['name'], 'Require an immutable revision');
    expect(
      step('revision', 'Checkout')['with']['ref'],
      r'${{ inputs.source_sha || github.sha }}',
    );
    expect(
      jobs['revision']['outputs']['sha'],
      r'${{ steps.revision.outputs.sha }}',
    );
  });

  test('uses native builds and the shared test prologues', () {
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
    for (final job in ['build', 'golden', 'desktop_e2e_linux']) {
      expect(
        step(job, 'Setup Flutter workspace')['uses'],
        './.github/actions/setup-flutter-workspace',
      );
    }
    expect(
      step('golden', 'Setup Flutter workspace')['with']['linux-toolchain'],
      'false',
    );
    for (final job in ['build', 'desktop_e2e_linux']) {
      expect(step(job, 'Setup Flutter workspace')['with']['rust'], 'true');
    }
    final e2e = step('desktop_e2e_linux', 'Desktop E2E')['run'] as String;
    expect(e2e, contains('for suite in integration_test/*_test.dart'));
    expect(e2e, contains(r'flutter test "${suite}" -d linux'));
  });

  test('full validation cannot skip a failed prerequisite', () {
    expect(jobs['validation_ready']['needs'], [
      'revision',
      'build',
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
      'GOLDEN_RESULT': 'golden',
      'E2E_RESULT': 'desktop_e2e_linux',
    }.entries) {
      expect(gateEnv[entry.key], '\${{ needs.${entry.value}.result }}');
    }
  });

  group(
    'ubuntu revision and completion guards',
    () {
      test('rejects mutable refs and malformed SHAs', () {
        final script =
            step('revision', 'Require an immutable revision')['run'] as String;
        final sha = '0123456789abcdef0123456789abcdef01234567';
        for (final value in [
          sha,
          'main',
          'v1.0.0',
          'abc123',
          '',
          '$sha\nmain',
        ]) {
          final result = Process.runSync(
            'bash',
            ['-c', script],
            environment: {'SOURCE_SHA': value},
          );
          expect(result.exitCode, value == sha ? 0 : 1, reason: value);
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
    },
    skip: Platform.isWindows ? 'These guards run on Ubuntu only.' : false,
  );
}
