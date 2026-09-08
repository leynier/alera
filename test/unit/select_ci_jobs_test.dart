import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/select_ci_jobs.dart';

void main() {
  test('an empty change set fails open and enables every job', () {
    expect(selectCiJobs(const <String>[]), CiJobs.all);
  });

  test('docs-only changes skip every heavy PR Checks job', () {
    expect(
      selectCiJobs(const <String>[
        'docs/testing.md',
        'AGENTS.md',
        'readme.md',
        '.github/CONTRIBUTING.md',
        '.github/ISSUE_TEMPLATE/bug_report.yml',
        'reference_projects/orca/README.md',
        'LICENSE',
      ]),
      CiJobs.none,
    );
  });

  test('landing-only and cloud-only changes skip PR Checks heavy jobs', () {
    expect(selectCiJobs(const <String>['landing/src/index.tsx']), CiJobs.none);
    expect(
      selectCiJobs(const <String>['cloud/src/main.rs', 'edge/src/index.ts']),
      CiJobs.none,
    );
  });

  test('a Dart library change runs generation and tests without Rust', () {
    final jobs = selectCiJobs(const <String>[
      'lib/src/features/workbench/presentation/workbench_page.dart',
    ]);
    expect(jobs.staticDart, isTrue);
    expect(jobs.generation, isTrue);
    expect(jobs.test, isTrue);
    expect(jobs.rust, isFalse);
    expect(jobs.mobile, isFalse);
    expect(jobs.packages, isFalse);
  });

  test('a Rust-only change skips Flutter tests and generation', () {
    final jobs = selectCiJobs(const <String>['rust/alera-cli/src/main.rs']);
    expect(jobs.rust, isTrue);
    expect(jobs.staticDart, isFalse);
    expect(jobs.test, isFalse);
    expect(jobs.generation, isFalse);
    expect(jobs.mobile, isFalse);
    expect(jobs.packages, isFalse);
  });

  test('terminal-host protocol Dart still requires the Rust job', () {
    final jobs = selectCiJobs(const <String>[
      'lib/src/features/workbench/infra/terminal_host/terminal_host_client.dart',
    ]);
    expect(jobs.rust, isTrue);
    expect(jobs.test, isTrue);
    expect(jobs.staticDart, isTrue);
  });

  test('generated FRB bindings require Rust and Flutter tests', () {
    final jobs = selectCiJobs(const <String>['lib/src/rust/api/git.dart']);
    expect(jobs.rust, isTrue);
    expect(jobs.test, isTrue);
    expect(jobs.generation, isTrue);
  });

  test('mobile Dart does not run desktop test shards or native Rust', () {
    final jobs = selectCiJobs(const <String>['mobile/lib/main.dart']);
    expect(jobs.mobile, isTrue);
    expect(jobs.staticDart, isTrue);
    expect(jobs.generation, isTrue);
    expect(jobs.test, isFalse);
    expect(jobs.rust, isFalse);
  });

  test('shared configuration package runs packages, tests, and mobile', () {
    final jobs = selectCiJobs(const <String>[
      'packages/alera_configuration/lib/src/configuration_sync.dart',
    ]);
    expect(jobs.packages, isTrue);
    expect(jobs.test, isTrue);
    expect(jobs.mobile, isTrue);
    expect(jobs.staticDart, isTrue);
    expect(jobs.rust, isFalse);
  });

  test('workflow and selector changes fail open', () {
    expect(
      selectCiJobs(const <String>['.github/workflows/pr.yml']),
      CiJobs.all,
    );
    expect(
      selectCiJobs(const <String>['tool/ci/select_ci_jobs.dart']),
      CiJobs.all,
    );
    expect(
      selectCiJobs(const <String>[
        '.github/actions/setup-rust-checks/action.yml',
      ]),
      CiJobs.all,
    );
  });

  test('unknown native paths fail open', () {
    expect(
      selectCiJobs(const <String>['linux/runner/status_notifier_item.cc']),
      CiJobs.all,
    );
  });

  test('docs mixed with Dart still run the Dart jobs', () {
    final jobs = selectCiJobs(const <String>[
      'docs/testing.md',
      'lib/src/core/build_flavor.dart',
    ]);
    expect(jobs.staticDart, isTrue);
    expect(jobs.test, isTrue);
    expect(jobs.generation, isTrue);
    expect(jobs.rust, isFalse);
  });

  test('a renamed path keeps jobs for both old and new names', () {
    final jobs = selectCiJobs(const <String>[
      'rust/alera-cli/src/old.rs',
      'docs/moved.md',
    ]);
    expect(jobs.rust, isTrue);
    expect(jobs.test, isFalse);
  });
}
