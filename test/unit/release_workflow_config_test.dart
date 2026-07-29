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
      ).readAsStringSync();

      expect(
        workflow,
        contains(
          '--dart-define "ALERA_UPDATE_AUTO_INSTALL_ENABLED=\$auto_install_enabled"',
        ),
      );
      // Scoped to the block that decides auto-install. The signing steps still
      // check these secrets, and must, to decide whether they can sign at all.
      final decision = workflow.substring(
        workflow.indexOf('auto_install_enabled=false'),
        workflow.indexOf('dart run desktop_updater:release'),
      );

      expect(
        decision,
        contains('if [[ "\$PLATFORM" != "linux" ]]; then'),
        reason: 'Linux updates go through apt or dnf so dependencies resolve',
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
  });
}
