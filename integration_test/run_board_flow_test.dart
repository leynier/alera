import 'dart:io';
import 'dart:ui' as ui;
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../test/support/run_board_fixtures.dart';
import '../test/support/run_board_widget_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native Run Board preserves workspace, inspection and recovery', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(Size.zero);
    final repository = BoardTestRepository();
    final container = boardContainer(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    final navigation = container.read(runBoardNavigationProvider.notifier)
      ..open();
    final captureKey = GlobalKey();
    await windowManager.setSize(const Size(1100, 800));
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: BoardTestApp(container: container),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deliver reviewed workflow plans'));
    await tester.pumpAndSettle();
    expect(
      container.read(workbenchControllerProvider).activeWorkspaceId,
      'ws-2',
    );
    await _capture(tester, captureKey, 'overview');
    await tester.ensureVisible(find.text('Build the review surface'));
    await tester.tap(find.text('Build the review surface'));
    await tester.pumpAndSettle();
    await _capture(tester, captureKey, 'inspector');
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Worker-reported evidence. This is not an independent review or a human gate approval.',
      ),
      findsOneWidget,
    );
    await _capture(tester, captureKey, 'evidence');
    await tester.tap(find.text('Return to Workspace'));
    await tester.pumpAndSettle();
    expect(repository.watchers, 0);
    await tester.tap(find.text('Open Run Board'));
    await tester.pumpAndSettle();
    expect(container.read(runBoardNavigationProvider).taskId, 'task-2');
    navigation.selectTask(null);
    await windowManager.setSize(const Size(420, 640));
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: BoardTestApp(container: container, scale: 2),
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, captureKey, 'compact-2x');
    navigation.selectRun(null);
    await tester.pumpAndSettle();
    await _capture(tester, captureKey, 'compact-filters-2x');
    await windowManager.setSize(const Size(1100, 800));
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: BoardTestApp(container: container),
      ),
    );
    repository.board = RunBoardSnapshot(
      revision: 2,
      counts: const RunBoardCounts(attention: 0, active: 0, history: 0),
      items: [],
    );
    repository.events.add(null);
    await tester.pumpAndSettle();
    await _capture(tester, captureKey, 'empty');
    repository.error = const RunBoardUpdateRequired();
    repository.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Update Required'), findsOneWidget);
    await _capture(tester, captureKey, 'update-required');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  expect(tester.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(
    pixelRatio: tester.view.devicePixelRatio,
  );
  try {
    expect(image.width, greaterThan(0));
    final output = Platform.environment['ALERA_VISUAL_REVIEW_DIR'];
    if (output != null) {
      final directory = await Directory(output).create(recursive: true);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        p.join(
          directory.path,
          'run-board-${Platform.operatingSystem}-$name.png',
        ),
      ).writeAsBytes(bytes!.buffer.asUint8List());
    }
  } finally {
    image.dispose();
  }
}
