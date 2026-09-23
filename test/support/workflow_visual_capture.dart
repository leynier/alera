import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ValueKey('workflow-visual-boundary');

Widget workflowVisualBoundary(BuildContext context, Widget? child) =>
    RepaintBoundary(key: _key, child: child!);

Future<void> loadWorkflowVisualFonts() async {
  if (Platform.environment['ALERA_WORKFLOW_VISUAL_DIR'] == null) return;
  for (final (family, asset) in [
    ('Inter', 'assets/fonts/Inter-Variable.ttf'),
    ('JetBrains Mono', 'assets/fonts/JetBrainsMono-Variable.ttf'),
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    (
      'packages/lucide_icons_flutter/Lucide',
      'packages/lucide_icons_flutter/assets/lucide.ttf',
    ),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
  }
}

/// Optional readable evidence from the same fixture-backed interaction tests.
/// This does not claim live-provider execution or replace golden assertions.
Future<void> captureWorkflowVisual(WidgetTester tester, String name) async {
  final directory = Platform.environment['ALERA_WORKFLOW_VISUAL_DIR'];
  if (directory == null) return;
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
