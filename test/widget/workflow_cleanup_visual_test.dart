import 'dart:io';
import 'dart:ui' as ui;

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_cleanup_session.dart';
import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/workflow_cleanup_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_review_panel.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_selection_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_cleanup_fixture.dart';
import '../support/workflow_cleanup_catalog_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, asset) in [
      ('Inter', 'assets/fonts/Inter-Variable.ttf'),
      ('JetBrains Mono', 'assets/fonts/JetBrainsMono-Variable.ttf'),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
  for (final compact in [false, true]) {
    for (final state in ['selection', 'preview', 'attention']) {
      testWidgets('cleanup visual $state compact=$compact', (tester) async {
        await tester.binding.setSurfaceSize(Size(compact ? 420 : 760, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final session = WorkflowCleanupSession(_UnusedRepository(), 'run');
        addTearDown(session.dispose);
        session.resources = WorkflowCleanupPage.fromJson(
          cleanupResourcesFixture(),
          WorkflowCleanupResource.fromJson,
        ).items;
        session.history = WorkflowCleanupPage.fromJson(
          cleanupHistoryFixture(),
          WorkflowCleanupSummary.fromJson,
        ).items;
        session.loading = false;
        session.select('workspace', true);
        final key = GlobalKey();
        final status = cleanupStatusFixture(
          state == 'selection' ? 'preview' : state,
        );
        (status['preview']! as Map)['id'] =
            '00000000-0000-4000-8000-000000000001';
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
                  body: state == 'selection'
                      ? WorkflowCleanupSelectionPanel(
                          session: session,
                          allowPrepare: true,
                          onBack: () {},
                          onOpen: (_) {},
                          onWorkspace: (_) {},
                        )
                      : WorkflowCleanupReviewPanel(
                          status: WorkflowCleanupStatus.fromJson(status),
                          now: DateTime.utc(2026),
                          onBack: () {},
                          onRefresh: () {},
                          onApply: (_) {},
                          onOpenWorkspace: (_) {},
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['ALERA_WORKFLOW_VISUAL_DIR'];
        if (directory != null) {
          await _capture(
            tester,
            key,
            '$directory/cleanup-$state-${compact ? 'compact' : 'desktop'}.png',
          );
          if (compact && state == 'preview') {
            await tester.scrollUntilVisible(
              find.text('Clean Selected Resources'),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await _capture(
              tester,
              key,
              '$directory/cleanup-preview-compact-footer.png',
            );
          }
        }
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _UnusedRepository implements WorkflowCleanupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
