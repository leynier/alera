import 'dart:io';
import 'dart:ui' as ui;

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/domain/workflow_run_controls.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_run_control_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_controls_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, asset) in [
      ('Inter', 'assets/fonts/Inter-Variable.ttf'),
      ('JetBrains Mono', 'assets/fonts/JetBrainsMono-Variable.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
  for (final compact in [false, true]) {
    testWidgets('execution controls visual compact=$compact', (tester) async {
      await tester.binding.setSurfaceSize(Size(compact ? 420 : 760, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAleraDarkTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(compact ? 2 : 1),
            ),
            child: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(AleraTokens.space16),
                  child: WorkflowRunControlPanel(
                    controls: WorkflowRunControls.fromJson(
                      workflowControlsFixture(executionStatus: 'running'),
                    ),
                    onControl: (_) {},
                    onReview: (_) {},
                    onRefresh: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ALERA_WORKFLOW_VISUAL_DIR'];
      if (directory == null) return;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/controls-${compact ? 'compact' : 'desktop'}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
