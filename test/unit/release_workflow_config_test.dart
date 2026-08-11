import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('release workflow configuration', () {
    test('packages the system browser engines required by desktop tabs', () {
      final setup = File(
        '.github/actions/setup-flutter-workspace/action.yml',
      ).readAsStringSync();
      final linuxPackage = File(
        'tool/release/package_linux.sh',
      ).readAsStringSync();
      final podfile = File('macos/Podfile').readAsStringSync();
      final xcodeProject = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final macInfo = File('macos/Runner/Info.plist').readAsStringSync();
      final windowsBrowserCmake = File(
        'packages/alera_browser/windows/CMakeLists.txt',
      ).readAsStringSync();
      final windowsBrowserValues = File(
        'packages/alera_browser/windows/browser_value.cpp',
      ).readAsStringSync();
      final macBrowserCore = File(
        'packages/alera_browser/macos/Classes/BrowserCore.swift',
      ).readAsStringSync();

      expect(setup, contains('libwebkit2gtk-4.1-dev'));
      expect(linuxPackage, contains('libwebkit2gtk-4.1-0'));
      expect(linuxPackage, contains('libjson-glib-1.0-0'));
      expect(linuxPackage, contains('libsecret-1-0'));
      expect(linuxPackage, contains('libsqlite3-0'));
      expect(linuxPackage, contains('libssl3'));
      expect(linuxPackage, contains('Requires: webkit2gtk4.1'));
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
      expect(windowsBrowserCmake, contains('ALERA_BROWSER_STORAGE_NAME'));
      expect(windowsBrowserValues, contains('ALERA_BROWSER_STORAGE_NAME'));
      expect(macBrowserCore, contains('Bundle.main.bundleIdentifier'));
    });

    test('enables autonomous updates everywhere a package manager does not', () {
      final workflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');

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
      final workflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();
      final config = File('desktop_updater.yaml').readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final updaterSources = Directory(
        'lib/src/features/updater',
      ).listSync(recursive: true).whereType<File>();

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
      final workflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
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
      expect(packageJob, contains('Expected 6 runtime input archives'));
      expect(packageJob, contains('package_runtime_sidecars.dart'));
      expect(packageJob, contains('name: release-runtime'));
    });

    test('caches both standard and shortened Cargokit build layouts', () {
      final desktopBuild = File(
        '.github/workflows/desktop-build.yml',
      ).readAsStringSync();
      final warmCache = File(
        '.github/workflows/warm-cache.yml',
      ).readAsStringSync();
      final release = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();
      final cachePaths = RegExp(
        r'path: \|\s+build/\*\*/cargokit_build\s+build/\*\*/ck',
      );

      expect(cachePaths.allMatches(desktopBuild), hasLength(1));
      expect(cachePaths.allMatches(warmCache), hasLength(2));
      expect(cachePaths.allMatches(release), hasLength(1));
      expect(desktopBuild, contains(r'-name ck'));
    });

    test('gates publishing on complete desktop runtime packaging', () {
      final workflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();
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
      final appInfo = File(
        'macos/Runner/Configs/AppInfo.xcconfig',
      ).readAsStringSync();
      final podfile = File('macos/Podfile').readAsStringSync();
      final xcodeProject = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final helperAssets = File(
        'tool/native_helpers/native_helper_assets.json',
      ).readAsStringSync();
      final releaseWorkflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();
      final buildWorkflow = File(
        '.github/workflows/desktop-build.yml',
      ).readAsStringSync();

      expect(appInfo, contains('ARCHS = arm64'));
      expect(appInfo, contains('EXCLUDED_ARCHS[sdk=macosx*] = x86_64'));
      expect(podfile, contains("config.build_settings['ARCHS'] = 'arm64'"));
      // The sidecar is pinned to the triple instead of inheriting the build
      // machine, so the shipped binary cannot depend on which runner ran.
      expect(xcodeProject, contains('aarch64-apple-darwin'));
      expect(helperAssets, isNot(contains('"x86_64"')));
      for (final workflow in <String>[releaseWorkflow, buildWorkflow]) {
        expect(workflow, contains('verify_macos_arm64_only.sh'));
      }
    });

    test('uses dedicated R2 sccache credentials with local fallback', () {
      final workflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();
      final buildJobs = workflow.substring(
        workflow.indexOf('  build_desktop_app:'),
        workflow.indexOf('  build_android:'),
      );
      final setup = File(
        '.github/actions/setup-rust-sccache/action.yml',
      ).readAsStringSync();

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
      final workflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();
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

    test('cleans closed pull request caches without a checkout', () {
      final cleanup = File(
        '.github/workflows/cache-cleanup.yml',
      ).readAsStringSync();

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
