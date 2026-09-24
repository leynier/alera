import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String workflowJob(String yaml, String jobId) {
  final lines = yaml.replaceAll('\r\n', '\n').split('\n');
  final start = lines.indexWhere((line) => line == '  $jobId:');
  expect(start, greaterThanOrEqualTo(0), reason: 'missing job $jobId');
  var end = lines.length;
  final nextJob = RegExp(r'^  [A-Za-z0-9_-]+:\s*$');
  for (var i = start + 1; i < lines.length; i++) {
    if (nextJob.hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}

void main() {
  test('skips redundant PR Checks jobs and still gates on pr-ready', () {
    final pr = File('.github/workflows/pr.yml').readAsStringSync();
    final hostCompat = File('tool/ci/host_compatibility.sh').readAsStringSync();
    final rustChecks = File('.github/actions/setup-rust-checks/action.yml')
        .readAsStringSync();
    final rustTests = File('tool/ci/run_rust_workspace_tests.sh')
        .readAsStringSync();
    final selectJobs = File('.github/actions/select-ci-jobs/action.yml')
        .readAsStringSync();
    final rustTestJob = workflowJob(pr, 'rust-test');
    final rustClippyJob = workflowJob(pr, 'rust-clippy');

    expect(pr, contains('./.github/actions/select-ci-jobs'));
    expect(selectJobs, contains('tool/ci/select_ci_jobs.dart'));
    expect(pr, contains('needs.changes.outputs.rust == \'true\''));
    expect(pr, contains('needs.changes.outputs.test == \'true\''));
    expect(pr, contains('CHANGES_RESULT'));
    expect(pr, contains('RUST_TEST_RESULT'));
    expect(pr, contains('RUST_CLIPPY_RESULT'));
    expect(
      RegExp(r'^\s+needs:', multiLine: true).hasMatch(rustTestJob),
      isFalse,
      reason:
          'rust test is the create→done critical path and must not wait '
          'for the path-filter job or the Flutter fan-out',
    );
    expect(rustClippyJob, contains('needs: changes'));
    expect(
      pr,
      contains(r'[ "$result" != "success" ] && [ "$result" != "skipped" ]'),
    );
    expect(pr, contains('flutter test --no-pub --coverage'));
    expect(pr, contains('Previous host conformance'));
    expect(hostCompat, contains(r'alera-runtime-${previous_version}'));
    expect(
      hostCompat,
      contains(
        'd0f29c75c2163e3764d7fbf2bb4e605007f2447a890e5bf1190f359516d86d13',
      ),
    );
    expect(hostCompat, contains('reports crate version 0.1.0'));
    expect(hostCompat, isNot(contains('cargo build --locked -p alera-cli')));
    final hostCompatTest = File(
      'rust/alera-cli/tests/host_version_compatibility.rs',
    ).readAsStringSync();
    expect(
      hostCompatTest,
      contains('V049_PUBLISHED_HOST_VERSION: &str = "0.1.0"'),
    );
    expect(
      hostCompatTest,
      contains(
        'V049_PUBLISHED_HOST_COMMIT: &str = "17a183f51debfc29114c0e682bc917ed4cdc58ae"',
      ),
    );
    expect(rustChecks, contains('tool/ci/run_rust_workspace_tests.sh'));
    expect(rustTests, contains('--test-threads=1'));
    expect(rustTests, contains('orchestration_review_regressions'));
    expect(rustTests, contains('--lib --bins'));
    final cargoTests = rustTests
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('cargo test'))
        .toList(growable: false);
    expect(cargoTests, isNotEmpty);
    for (final command in cargoTests) {
      expect(command, contains('--workspace'));
      expect(command, contains('--locked'));
      expect(command, isNot(contains('--exclude')));
      expect(command, isNot(contains('--no-run')));
      expect(command, isNot(contains('--doc')));
      expect(command, isNot(contains('-p alera-cli')));
    }
    expect(
      cargoTests,
      contains(
        'cargo test --workspace --locked --test orchestration_review_regressions \\',
      ),
    );
    expect(hostCompat, contains('--workspace'));
    expect(hostCompat, isNot(contains('-p alera-cli')));
  });
}
