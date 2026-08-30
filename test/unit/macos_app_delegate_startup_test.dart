import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS startup does not call the unimplemented superclass callback', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    // Swift accepts this optional Objective-C callback, but FlutterAppDelegate
    // does not implement it. AppKit catches the exception and skips our setup.
    expect(
      source,
      isNot(matches(r'super\s*\.\s*applicationDidFinishLaunching\s*\(')),
    );
  });

  test('macOS leaves process exit to the explicit close and quit flow', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    expect(
      source,
      matches(
        r'applicationShouldTerminateAfterLastWindowClosed[^}]+return false',
      ),
    );
  });
}
