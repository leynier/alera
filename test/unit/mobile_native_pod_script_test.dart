import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final throughSymlink in [false, true]) {
    test('mobile pod resolves Cargokit with symlink=$throughSymlink', () async {
      final root = Directory.systemTemp.createTempSync('alera ios pod ');
      addTearDown(() => root.deleteSync(recursive: true));
      final checkout = p.join(root.path, 'checkout with spaces');
      final plugin = Directory(p.join(checkout, 'mobile', 'rust_builder'));
      final ios = Directory(p.join(plugin.path, 'ios'))
        ..createSync(recursive: true);
      final cargo = File(
        p.join(checkout, 'rust', 'alera-mobile-native', 'Cargo.toml'),
      )..createSync(recursive: true);
      final captured = File(p.join(root.path, 'arguments.txt'));
      final buildScript = File(
        p.join(checkout, 'rust_builder', 'cargokit', 'build_pod.sh'),
      )..createSync(recursive: true);
      buildScript.writeAsStringSync(r'''
set -e
BASEDIR=$(cd "$(dirname "$0")" && pwd -P)
test -d "$BASEDIR"
test -f "$PODS_TARGET_SRCROOT/$1/Cargo.toml"
printf '%s\n' "$PODS_TARGET_SRCROOT" "$1" "$2" > "$CAPTURE_FILE"
''');
      var sourceRoot = ios.path;
      if (throughSymlink) {
        final link = Link(
          p.join(
            checkout,
            'mobile',
            'ios',
            '.symlinks',
            'plugins',
            'alera_mobile_native',
          ),
        );
        link.parent.createSync(recursive: true);
        link.createSync(plugin.path);
        sourceRoot = p.join(link.path, 'ios');
      }
      final podspec = File(
        'mobile/rust_builder/ios/alera_mobile_native.podspec',
      ).readAsStringSync();
      final script = RegExp(r":script => <<-'SCRIPT',\n([\s\S]*?)\nSCRIPT")
          .firstMatch(podspec)!
          .group(1)!;

      final result = await Process.run(
        'sh',
        ['-c', script],
        environment: {
          'PODS_TARGET_SRCROOT': sourceRoot,
          'CAPTURE_FILE': captured.path,
        },
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final arguments = captured.readAsLinesSync();
      expect(arguments.first, ios.resolveSymbolicLinksSync());
      expect(arguments[2], 'alera_mobile_native');
      expect(
        File(p.join(arguments[0], arguments[1], 'Cargo.toml'))
            .resolveSymbolicLinksSync(),
        cargo.resolveSymbolicLinksSync(),
      );
    }, skip: Platform.isWindows ? 'CocoaPods runs on POSIX hosts.' : false);
  }
}
