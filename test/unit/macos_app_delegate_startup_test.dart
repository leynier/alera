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
}
