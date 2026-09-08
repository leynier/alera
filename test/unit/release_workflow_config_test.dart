import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('release workflow configuration', () {
    test('packages GTK and system libraries without a browser engine', () {
      final setup = File('.github/actions/setup-flutter-workspace/action.yml')
          .readAsStringSync();
      final linuxPackage = File('tool/release/package_linux.sh')
          .readAsStringSync();
      final podfile = File('macos/Podfile').readAsStringSync();
      final xcodeProject = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final macInfo = File('macos/Runner/Info.plist').readAsStringSync();

      expect(setup, isNot(contains('libwebkit2gtk-4.1-dev')));
      expect(setup, isNot(contains('libmpv-dev')));
      expect(setup, contains('sdk.lunarg.com/sdk/download/'));
      expect(
        setup,
        contains(
          '855b27ba05d2d8119c5114c5d4ff870ca38f2c632b11e1bb9923b9b7e6ecfe7b',
        ),
      );
      expect(
        setup,
        isNot(contains('KhronosGroup.VulkanSDK')),
        reason: 'Windows CI must not install Vulkan through WinGet',
      );
      expect(linuxPackage, isNot(contains('libwebkit2gtk-4.1-0')));
      expect(linuxPackage, isNot(contains('webkit2gtk4.1')));
      expect(linuxPackage, contains('libjson-glib-1.0-0'));
      expect(linuxPackage, contains('libsecret-1-0'));
      expect(linuxPackage, contains('libsqlite3-0'));
      expect(linuxPackage, contains('libssl3'));
      expect(linuxPackage, contains('Requires: json-glib'));
      expect(linuxPackage, contains('Requires: libsecret'));
      expect(linuxPackage, contains('Requires: sqlite'));
      expect(linuxPackage, contains('Requires: openssl-libs'));
      expect(podfile, contains("platform :osx, '14.0'"));
      expect(xcodeProject, isNot(contains('MACOSX_DEPLOYMENT_TARGET = 10.15')));
      expect(xcodeProject, contains('MACOSX_DEPLOYMENT_TARGET = 14.0'));
      expect(macInfo, contains('NSCameraUsageDescription'));
      expect(macInfo, contains('NSLocationUsageDescription'));
      expect(macInfo, contains('NSMicrophoneUsageDescription'));
    });

    test('enables autonomous updates everywhere a package manager does not', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');

      expect(
        workflow,
        contains(
          '--dart-define="ALERA_UPDATE_AUTO_INSTALL_ENABLED=\$auto_install_enabled"',
        ),
      );
      // Scoped to the block that decides auto-install. The signing steps still
      // check these secrets, and must, to decide whether they can sign at all.
      final decision = workflow.substring(
        workflow.indexOf('auto_install_enabled=true'),
        workflow.indexOf('dart run desktop_updater:release'),
      );

      expect(
        workflow,
        isNot(contains('if [[ "\$PLATFORM" != "linux" ]]; then')),
        reason:
            'which installation may be replaced is decided at runtime, by '
            'whether a package manager owns it and whether Alera can write '
            'to it, not by the platform it was built for',
      );
      expect(
        decision,
        isNot(
          anyOf(
            contains('APPLE_DEVELOPER_ID_APPLICATION'),
            contains('WINDOWS_CERTIFICATE_PFX_BASE64'),
          ),
        ),
        reason:
            'update integrity comes from the signed manifest, not from '
            'Developer ID or Authenticode, so auto-install no longer waits '
            'on a certificate',
      );
      expect(workflow, contains('ALERA_LINUX_GPG_PRIVATE_KEY_BASE64'));
      expect(
        workflow,
        isNot(
          contains('--dart-define "ALERA_UPDATE_AUTO_INSTALL_ENABLED=false"'),
        ),
      );
    });

    test('uses only the desktop_updater 2.7 release format', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();
      final config = File('desktop_updater.yaml').readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final updaterSources = Directory('lib/src/features/updater')
          .listSync(recursive: true)
          .whereType<File>();

      expect(pubspec, contains('desktop_updater: ^2.7.0'));
      expect(
        updaterSources.map((file) => file.readAsStringSync()).join('\n'),
        isNot(contains('package:desktop_updater/src/')),
      );
      expect(workflow, contains('dart run desktop_updater:release publish'));
      expect(workflow, contains('--output "pages/updates/\$CHANNEL"'));
      expect(workflow, contains('merge_desktop_update_indexes.dart'));
      expect(workflow, contains('verify_desktop_update_channel.dart'));
      expect(workflow, isNot(contains('tool/release/build_app_archive.dart')));
      expect(config, contains('desktop_updater:release sign'));
      expect(config, contains('hooks:'));
      expect(config, contains('prePackage:'));
      expect(config, contains('postPackage:'));
    });

    test('builds native apps and cross runtimes in parallel', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final appJob = workflow.substring(
        workflow.indexOf('  build_desktop_app:'),
        workflow.indexOf('  build_runtime_cross:'),
      );
      final crossJob = workflow.substring(
        workflow.indexOf('  build_runtime_cross:'),
        workflow.indexOf('  package_runtime:'),
      );
      final packageJob = workflow.substring(
        workflow.indexOf('  package_runtime:'),
        workflow.indexOf('  build_android:'),
      );

      expect(appJob, contains('timeout-minutes: 75'));
      expect(
        appJob,
        contains(
          'platform: macos\n            os: macos-latest\n            native_arch: arm64',
        ),
      );
      expect(
        appJob,
        contains(
          'platform: windows\n            os: windows-latest\n            native_arch: x64',
        ),
      );
      expect(
        appJob,
        contains(
          'platform: linux\n            os: ubuntu-latest\n            native_arch: x64',
        ),
      );
      expect(
        appJob.indexOf('Restore cargokit build'),
        lessThan(appJob.indexOf('Build release bundle')),
      );
      expect(appJob, contains('uses: ./.github/actions/tune-windows-build'));
      expect(appJob, contains('Stage native runtime input'));
      expect(
        appJob,
        contains(
          r'runtime-native-${{ matrix.platform }}-${{ matrix.native_arch }}',
        ),
      );
      expect(appJob, isNot(contains('runtime_targets=')));
      expect(appJob, isNot(contains('cargo build')));

      expect(crossJob, contains('timeout-minutes: 45'));
      expect(crossJob, contains('target: x86_64-apple-darwin'));
      expect(crossJob, contains('target: aarch64-pc-windows-msvc'));
      expect(crossJob, contains('target: aarch64-unknown-linux-gnu'));
      expect(crossJob, contains('uses: ./.github/actions/setup-rust-sccache'));
      expect(crossJob, isNot(contains('setup-flutter-workspace')));
      expect(crossJob, isNot(contains('setup-zig')));
      expect(crossJob, contains('retention-days: 1'));

      expect(packageJob, contains('- build_desktop_app'));
      expect(packageJob, contains('- build_runtime_cross'));
      expect(packageJob, contains('uses: dart-lang/setup-dart@'));
      expect(packageJob, contains('working-directory: tool/release'));
      expect(packageJob, contains('dart pub get'));
      expect(packageJob, isNot(contains('setup-flutter-workspace')));
      expect(packageJob, contains('Expected 6 runtime input archives'));
      expect(packageJob, contains('package_runtime_sidecars.dart'));
      expect(packageJob, contains('name: release-runtime'));
    });

    test('caches both standard and shortened Cargokit build layouts', () {
      final desktopBuild = File('.github/workflows/desktop-build.yml')
          .readAsStringSync();
      final warmCache = File('.github/workflows/warm-cache.yml')
          .readAsStringSync();
      final release = File('.github/workflows/release-cut.yml')
          .readAsStringSync();
      final cachePaths = RegExp(
        r'path: \|\s+build/\*\*/cargokit_build\s+build/\*\*/ck',
      );

      expect(cachePaths.allMatches(desktopBuild), hasLength(1));
      expect(cachePaths.allMatches(warmCache), hasLength(2));
      expect(cachePaths.allMatches(release), hasLength(1));
      expect(desktopBuild, contains(r'-name ck'));
    });

    test('gates publishing on complete desktop runtime packaging', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();
      final publish = workflow.substring(workflow.indexOf('  publish:'));

      expect(publish, contains('- build_desktop_app'));
      expect(publish, contains('- package_runtime'));
      expect(publish, contains('- build_android'));
      expect(
        publish,
        contains(
          "needs.build_desktop_app.result == 'success' && needs.package_runtime.result == 'success'",
        ),
      );
    });

    test('builds and ships macOS for Apple Silicon only', () {
      final appInfo = File('macos/Runner/Configs/AppInfo.xcconfig')
          .readAsStringSync();
      final podfile = File('macos/Podfile').readAsStringSync();
      final xcodeProject = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final releaseWorkflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();
      final buildWorkflow = File('.github/workflows/desktop-build.yml')
          .readAsStringSync();

      expect(appInfo, contains('ARCHS = arm64'));
      expect(appInfo, contains('EXCLUDED_ARCHS[sdk=macosx*] = x86_64'));
      expect(podfile, contains("config.build_settings['ARCHS'] = 'arm64'"));
      // The sidecar is pinned to the triple instead of inheriting the build
      // machine, so the shipped binary cannot depend on which runner ran.
      expect(xcodeProject, contains('aarch64-apple-darwin'));
      for (final workflow in <String>[releaseWorkflow, buildWorkflow]) {
        expect(workflow, contains('verify_macos_arm64_only.sh'));
      }
    });

    test('uses dedicated R2 sccache credentials with local fallback', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();
      final buildJobs = workflow.substring(
        workflow.indexOf('  build_desktop_app:'),
        workflow.indexOf('  build_android:'),
      );
      final setup = File('.github/actions/setup-rust-sccache/action.yml')
          .readAsStringSync();

      expect(buildJobs, contains(r'vars.SCCACHE_R2_ACCOUNT_ID'));
      expect(buildJobs, contains(r'vars.SCCACHE_R2_BUCKET'));
      expect(buildJobs, contains(r'secrets.SCCACHE_R2_ACCESS_KEY_ID'));
      expect(buildJobs, contains(r'secrets.SCCACHE_R2_SECRET_ACCESS_KEY'));
      expect(buildJobs, isNot(contains(r'secrets.R2_ACCESS_KEY_ID')));
      expect(buildJobs, isNot(contains('ALERA_R2_BUCKET')));
      expect(setup, contains('RUSTC_WRAPPER=sccache'));
      expect(setup, contains('CARGO_INCREMENTAL=0'));
      expect(setup, contains('SCCACHE_BASEDIRS=\$GITHUB_WORKSPACE'));
      expect(setup, contains('SCCACHE_IGNORE_SERVER_IO_ERROR=1'));
      expect(setup, contains('SCCACHE_S3_KEY_PREFIX=alera/rust-v1'));
      expect(setup, contains('using the runner-local cache'));
      expect(setup, contains('if sccache --start-server; then'));
      expect(setup, contains('could not authenticate to R2'));
      expect(setup, contains('export SCCACHE_BUCKET='));
      expect(setup, isNot(contains('echo "SCCACHE_BUCKET="')));
      expect(setup, isNot(contains('Swatinem/rust-cache')));
    });

    test('skips Chocolatey only while its first version is in moderation', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();
      final chocolateyJob = workflow.substring(
        workflow.indexOf('  publish_chocolatey:'),
      );

      expect(chocolateyJob, isNot(contains('continue-on-error')));
      expect(chocolateyJob, contains('CHOCOLATEY_API_KEY'));
      expect(chocolateyJob, contains('api/v2/Packages()'));
      expect(chocolateyJob, contains(r'$pendingModeration'));
      expect(chocolateyJob, contains(r'$hasApprovedVersion'));
      expect(
        chocolateyJob,
        contains(r'if ($pendingModeration -and -not $hasApprovedVersion) {'),
      );
      expect(chocolateyJob, contains('choco push \$package'));
    });

    test('publishes desktop packages when the mobile build is skipped', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();
      final packageJob = workflow.substring(
        workflow.indexOf('  publish_packages:'),
        workflow.indexOf('  publish_chocolatey:'),
      );
      final chocolateyJob = workflow.substring(
        workflow.indexOf('  publish_chocolatey:'),
      );

      expect(packageJob, contains('!cancelled()'));
      expect(packageJob, contains("needs.publish.result == 'success'"));
      expect(chocolateyJob, contains('!cancelled()'));
      expect(
        chocolateyJob,
        contains("needs.publish_packages.result == 'success'"),
      );
    });

    test('publishes only after the prepared version pull request merges', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();
      final publish = workflow.substring(workflow.indexOf('  publish:'));

      expect(workflow, contains('pull_request:'));
      expect(workflow, contains('- closed'));
      expect(workflow, contains('prepare_version_pr:'));
      expect(workflow, contains('prepared_release.dart write'));
      expect(workflow, contains('prepared_release.dart inspect'));
      expect(workflow, contains('--state open'));
      expect(workflow, contains('--force-with-lease='));
      expect(
        workflow,
        isNot(contains('closed, merged, or has an unexpected head')),
      );
      expect(workflow, contains("ready_to_publish == 'true'"));
      expect(workflow, contains('gh workflow run pr.yml'));
      expect(workflow, contains('gh workflow run landing.yml'));
      expect(workflow, isNot(contains('HEAD:refs/heads/main')));
      expect(
        workflow,
        isNot(contains('--force-with-lease origin HEAD~1:refs/heads/main')),
      );
      expect(publish, contains('ref: \${{ needs.plan.outputs.target_sha }}'));
      expect(publish, contains('--verify-tag'));
    });

    test(
      'dispatches exact-head checks for automation-created pull requests',
      () {
        final pr = File('.github/workflows/pr.yml').readAsStringSync();
        final release = File('.github/workflows/release-cut.yml')
            .readAsStringSync();

        expect(pr, contains('workflow_dispatch:'));
        expect(pr, contains('base_sha:'));
        expect(pr, contains('head_sha:'));
        expect(pr, contains(r'git diff --check "$BASE_SHA...$HEAD_SHA"'));
        expect(File('.mergify.yml').existsSync(), isFalse);
        expect(File('.github/workflows/merge-queue.yml').existsSync(), isFalse);
        expect(release, isNot(contains('Mergify')));
        expect(release, contains('Squash-merge this pull request after'));
      },
    );

    test('skips redundant PR Checks jobs and still gates on pr-ready', () {
      final pr = File('.github/workflows/pr.yml').readAsStringSync();
      final hostCompat = File('tool/ci/host_compatibility.sh')
          .readAsStringSync();
      final rustChecks = File('.github/actions/setup-rust-checks/action.yml')
          .readAsStringSync();
      final rustTests = File('tool/ci/run_rust_workspace_tests.sh')
          .readAsStringSync();

      expect(pr, contains('tool/ci/select_ci_jobs.dart'));
      expect(pr, contains('needs.changes.outputs.rust == \'true\''));
      expect(pr, contains('needs.changes.outputs.test == \'true\''));
      expect(pr, contains('CHANGES_RESULT'));
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
      expect(rustTests, contains('--lib --bins --doc'));
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

    test('desktop builds opt disposable native tests into clipboard access', () {
      final workflow = File('.github/workflows/desktop-build.yml')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final nativeFlow = workflow.substring(
        workflow.indexOf(
          '      - name: Verify native process boundary and workbench flow',
        ),
        workflow.indexOf(
          '      - name: Verify macOS startup and desktop presence',
        ),
      );

      expect(
        nativeFlow,
        contains(
          "        env:\n          ALERA_FLAVOR: dev\n          ALERA_NATIVE_TEST_CLIPBOARD: '1'",
        ),
        reason:
            'terminal_input_native_test owns the clipboard and only runs when '
            'the disposable desktop job explicitly opts in',
      );
    });

    test('keeps main ruleset activation behind a merged dry-run preflight', () {
      final script = File('tool/github/main_ruleset.dart').readAsStringSync();
      final contributing = File('.github/CONTRIBUTING.md').readAsStringSync();

      expect(script, isNot(contains('mergify')));
      expect(script, isNot(contains('queue-ready')));
      expect(script, contains("'context': 'pr-ready'"));
      expect(script, contains("'bypass_actors'"));
      expect(script, contains("'required_review_thread_resolution': true"));
      expect(script, contains("'type': 'deletion'"));
      expect(script, contains("'type': 'non_fast_forward'"));
      expect(script, contains('if (!options.apply)'));
      expect(script, contains("method: 'PUT'"));
      expect(contributing, contains('### Main Ruleset Rollout'));
      expect(contributing, contains('--dry-run-run-id <run-id>'));
      expect(contributing, contains('squash-merge'));
      expect(contributing, isNot(contains('Mergify')));
      expect(contributing, isNot(contains('Keep issue #489 open')));
    });

    test('cleans closed pull request caches without a checkout', () {
      final cleanup = File('.github/workflows/cache-cleanup.yml')
          .readAsStringSync();

      expect(cleanup, contains('pull_request:'));
      expect(cleanup, contains('- closed'));
      expect(cleanup, contains('actions: write'));
      expect(
        cleanup,
        contains(
          r'CACHE_REF: refs/pull/${{ github.event.pull_request.number }}/merge',
        ),
      );
      expect(cleanup, contains('gh cache delete'));
      expect(cleanup, isNot(contains('actions/checkout')));
    });
  });
}
