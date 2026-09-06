import 'dart:io';
import 'dart:ui' as ui;

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_catalog_pane.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_widget_harness.dart';
import '../support/workflow_catalog_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'))).load();
    await (FontLoader('JetBrains Mono')
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Variable.ttf')))
        .load();
  });
  for (final (width, recovery) in [
    (1100.0, false),
    (420.0, false),
    (420.0, true),
  ]) {
    testWidgets('catalog visual at $width recovery=$recovery', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workflowCatalogRepositoryProvider.overrideWithValue(
              CatalogTestRepository()
                ..personalReview = {
                  'id': 'feature-delivery',
                  'record': {...workflowCatalogRecord, 'catalogRevision': 4},
                  'document': 'Current definition',
                  'diff': '-Purpose: Review the foundation\n+Purpose: Validate the complete product',
                  'matches': false,
                },
            ),
            workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAleraDarkTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(width == 420 ? 1.5 : 1),
              ),
              child: RepaintBoundary(
                key: boundaryKey,
                child: const Scaffold(body: WorkflowCatalogPane()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feature Delivery'));
      await tester.pumpAndSettle();
      if (recovery) {
        await tester.ensureVisible(find.text('Edit Personal'));
        await tester.tap(find.text('Edit Personal'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Review Current Recipe'));
        await tester.tap(find.text('Review Current Recipe'));
        await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('feature-delivery'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ALERA_WORKFLOW_VISUAL_DIR'];
      if (directory == null) return;
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/catalog-${recovery ? 'recovery-' : ''}${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
