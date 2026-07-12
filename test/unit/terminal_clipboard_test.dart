import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.leynier.alera/clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('uses the GTK image clipboard channel on Linux', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return '/tmp/alera-paste-test.png';
    });

    final path = await const NativeTerminalClipboard().saveImageAsTempFile();

    expect(path, '/tmp/alera-paste-test.png');
    expect(calls, hasLength(1));
    expect(calls.single.method, 'saveImageAsTempFile');
  }, skip: !Platform.isLinux);
}
