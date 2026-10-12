import 'dart:io';
import 'dart:ui' as ui;

import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../test/support/runs_fake_repository.dart';
import '../test/support/runs_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native Runs preserves workspace, inspection and recovery', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(Size.zero);
    final repository = FakeRunRepository();
    final container = runsContainer(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    final navigation = container.read(activityNavigationProvider.notifier)
      ..open();
    final captureKey = GlobalKey();
    await windowManager.setSize(const Size(1100, 800));
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: RunsTestApp(container: container),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add OAuth login to the settings page'));
    await tester.pumpAndSettle();
    expect(
      container.read(workbenchControllerProvider).activeWorkspaceId,
      'ws-2',
    );
    await _capture(tester, captureKey, 'overview');
    navigation.selectTask('task-2');
    await tester.pumpAndSettle();
    await _capture(tester, captureKey, 'inspector');
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      find.text('Worker-reported evidence is not an independent review.'),
      findsOneWidget,
    );
    await _capture(tester, captureKey, 'evidence');
    await tester.tap(find.text('Return to Workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Activity'));
    await tester.pumpAndSettle();
    expect(container.read(activityNavigationProvider).runs.taskId, 'task-2');
    navigation.selectTask(null);
    await windowManager.setSize(const Size(420, 640));
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: RunsTestApp(container: container, scale: 2),
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
        child: RunsTestApp(container: container),
      ),
    );
    repository.board = const RunBoardPage(revision: 2);
    repository.changed();
    await tester.pumpAndSettle();
    await _capture(tester, captureKey, 'empty');
    repository.error = const RunsUpdateRequired();
    repository.changed();
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
        p.join(directory.path, 'runs-${Platform.operatingSystem}-$name.png'),
      ).writeAsBytes(bytes!.buffer.asUint8List());
    }
  } finally {
    image.dispose();
  }
}
