import 'dart:io';

/// Decides which PR Checks jobs a change set actually needs.
///
/// Unknown paths enable every job. That is the safe default: skipping a job
/// is only allowed when every changed path maps to a known family.
class const CiJobs({
  required final bool staticDart,
  required final bool packages,
  required final bool generation,
  required final bool test,
  required final bool mobile,
  required final bool rust,
}) {
  static const all = CiJobs(
    staticDart: true,
    packages: true,
    generation: true,
    test: true,
    mobile: true,
    rust: true,
  );

  static const none = CiJobs(
    staticDart: false,
    packages: false,
    generation: false,
    test: false,
    mobile: false,
    rust: false,
  );

  CiJobs union(CiJobs other) {
    return CiJobs(
      staticDart: staticDart || other.staticDart,
      packages: packages || other.packages,
      generation: generation || other.generation,
      test: test || other.test,
      mobile: mobile || other.mobile,
      rust: rust || other.rust,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CiJobs &&
        other.staticDart == staticDart &&
        other.packages == packages &&
        other.generation == generation &&
        other.test == test &&
        other.mobile == mobile &&
        other.rust == rust;
  }

  @override
  int get hashCode =>
      Object.hash(staticDart, packages, generation, test, mobile, rust);

  Map<String, String> get githubOutput {
    return <String, String>{
      'static_dart': '$staticDart',
      'packages': '$packages',
      'generation': '$generation',
      'test': '$test',
      'mobile': '$mobile',
      'rust': '$rust',
    };
  }
}

void main(List<String> args) {
  CiJobs jobs;
  try {
    jobs = selectCiJobs(CiJobsArgs.parse(args).files);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exitCode = 64;
    return;
  }

  for (final entry in jobs.githubOutput.entries) {
    stdout.writeln('${entry.key}=${entry.value}');
  }
  stderr.writeln(
    'PR jobs: static_dart=${jobs.staticDart} packages=${jobs.packages} '
    'generation=${jobs.generation} test=${jobs.test} '
    'mobile=${jobs.mobile} rust=${jobs.rust}',
  );
}

class const CiJobsArgs({required final List<String> files}) {
  static CiJobsArgs parse(List<String> args) {
    var all = false;
    String? filesFrom;
    final files = <String>[];

    for (var cursor = 0; cursor < args.length; cursor += 1) {
      final arg = args[cursor];
      String requireValue() {
        if (cursor + 1 >= args.length) {
          throw FormatException('Missing value for $arg');
        }
        cursor += 1;
        return args[cursor];
      }

      if (arg == '--all') {
        all = true;
      } else if (arg == '--files-from') {
        filesFrom = requireValue();
      } else if (arg == '-h' || arg == '--help') {
        _printUsage();
        exit(0);
      } else {
        throw FormatException('Unknown argument: $arg');
      }
    }

    if (all) {
      return const CiJobsArgs(files: <String>['.github/workflows/pr.yml']);
    }
    if (filesFrom != null) {
      files.addAll(
        File(filesFrom)
            .readAsStringSync()
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty),
      );
    }
    return CiJobsArgs(files: files);
  }
}

/// Returns the PR Checks jobs required by [files].
///
/// An empty list is treated as unknown, so every job runs. A renamed path
/// should be passed twice (old and new) by the caller.
CiJobs selectCiJobs(Iterable<String> files) {
  final paths = files
      .map((path) => path.replaceAll(r'\', '/'))
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  if (paths.isEmpty) {
    return CiJobs.all;
  }

  var jobs = CiJobs.none;
  for (final path in paths) {
    final selected = jobsForPath(path);
    if (selected == null) {
      return CiJobs.all;
    }
    jobs = jobs.union(selected);
  }
  return jobs;
}

/// Maps one repository path onto the jobs it requires.
///
/// Returns `null` when the path is unknown so the caller can fail open.
CiJobs? jobsForPath(String path) {
  if (_isForceAll(path)) {
    return CiJobs.all;
  }
  if (_isDocs(path) || _isLanding(path) || _isCloud(path)) {
    return CiJobs.none;
  }

  var jobs = CiJobs.none;
  var matched = false;

  if (_isStaticDart(path)) {
    jobs = jobs.union(
      const CiJobs(
        staticDart: true,
        packages: false,
        generation: false,
        test: false,
        mobile: false,
        rust: false,
      ),
    );
    matched = true;
  }
  if (_isPackages(path)) {
    jobs = jobs.union(
      const CiJobs(
        staticDart: false,
        packages: true,
        generation: false,
        test: true,
        mobile: false,
        rust: false,
      ),
    );
    matched = true;
  }
  if (_isGeneration(path)) {
    jobs = jobs.union(
      const CiJobs(
        staticDart: false,
        packages: false,
        generation: true,
        test: false,
        mobile: false,
        rust: false,
      ),
    );
    matched = true;
  }
  if (_isTest(path)) {
    jobs = jobs.union(
      const CiJobs(
        staticDart: false,
        packages: false,
        generation: false,
        test: true,
        mobile: false,
        rust: false,
      ),
    );
    matched = true;
  }
  if (_isMobile(path)) {
    jobs = jobs.union(
      const CiJobs(
        staticDart: false,
        packages: false,
        generation: false,
        test: false,
        mobile: true,
        rust: false,
      ),
    );
    matched = true;
  }
  if (_isRust(path)) {
    jobs = jobs.union(
      const CiJobs(
        staticDart: false,
        packages: false,
        generation: false,
        test: false,
        mobile: false,
        rust: true,
      ),
    );
    matched = true;
  }

  return matched ? jobs : null;
}

bool _isForceAll(String path) {
  return path.startsWith('.github/workflows/') ||
      path.startsWith('.github/actions/') ||
      path == '.github/dependabot.yml' ||
      path == 'tool/ci/select_ci_jobs.dart' ||
      path == 'tool/ci/run_rust_workspace_tests.sh';
}

bool _isDocs(String path) {
  if (path.endsWith('.md') || path.endsWith('.mdx')) {
    return true;
  }
  return path.startsWith('docs/') ||
      path.startsWith('reference_projects/') ||
      path.startsWith('.github/ISSUE_TEMPLATE/') ||
      path == '.github/pull_request_template.md' ||
      path == 'LICENSE' ||
      path.startsWith('LICENSE.');
}

bool _isLanding(String path) => path.startsWith('landing/');

bool _isCloud(String path) {
  return path.startsWith('cloud/') ||
      path.startsWith('edge/') ||
      path.startsWith('infra/') ||
      path.startsWith('tool/cloud/');
}

bool _isStaticDart(String path) {
  return path.endsWith('.dart') ||
      path == 'analysis_options.yaml' ||
      path == 'dart_test.yaml' ||
      path == 'pubspec.yaml' ||
      path == 'pubspec.lock' ||
      path == 'tool/quality/max_lines_baseline.txt';
}

bool _isPackages(String path) {
  return path.startsWith('packages/') ||
      path.startsWith('rust_builder/') ||
      path.startsWith('mobile/rust_builder/') ||
      path.startsWith('tool/release/runtime_packager/') ||
      path == 'tool/ci/verify_runtime_packager.dart';
}

bool _isGeneration(String path) {
  return path.startsWith('lib/') ||
      path.startsWith('mobile/lib/') ||
      path == 'pubspec.yaml' ||
      path == 'pubspec.lock' ||
      path == 'mobile/pubspec.yaml' ||
      path == 'mobile/pubspec.lock' ||
      path == 'build.yaml' ||
      path == 'mobile/build.yaml';
}

bool _isTest(String path) {
  return path.startsWith('lib/') ||
      path.startsWith('test/') ||
      path.startsWith('integration_test/') ||
      path.startsWith('third_party/') ||
      path.startsWith('packages/') ||
      path == 'pubspec.yaml' ||
      path == 'pubspec.lock' ||
      path == 'analysis_options.yaml' ||
      path == 'dart_test.yaml' ||
      path == 'tool/ci/select_test_shard.dart' ||
      path == 'tool/quality/coverage_report.dart' ||
      path == 'tool/ci/patch_native_asset_ci_workarounds.dart';
}

bool _isMobile(String path) {
  return path.startsWith('mobile/') ||
      path.startsWith('packages/alera_configuration/') ||
      path.startsWith('third_party/xterm');
}

bool _isRust(String path) {
  return path.startsWith('rust/') ||
      path.startsWith('rust_builder/') ||
      path.startsWith('mobile/rust_builder/') ||
      path.startsWith('lib/src/rust/') ||
      path.startsWith('lib/src/features/workbench/infra/terminal_host/') ||
      path == 'tool/ci/host_compatibility.sh' ||
      path == 'tool/ci/run_rust_workspace_tests.sh';
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/ci/select_ci_jobs.dart '
    '(--all | --files-from PATH)',
  );
}
