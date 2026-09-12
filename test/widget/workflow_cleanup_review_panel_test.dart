import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_review_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_cleanup_fixture.dart';

void main() {
  testWidgets(
    'cleanup requires explicit selection confirmation and retains branch by default',
    (tester) async {
      final calls = <bool>[];
      await tester.pumpWidget(
        _panel(cleanupStatusFixture('preview'), calls.add),
      );
      await tester.scrollUntilVisible(
        find.text('Clean Selected Resources'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Clean Selected Resources'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(AleraCheckbox));
      await tester.pump();
      await tester.tap(find.text('Clean Selected Resources'));
      expect(calls, [false]);
      await tester.scrollUntilVisible(
        find.text('Keep Branch'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Keep Branch'), findsOneWidget);
    },
  );
  testWidgets('dirty and expired previews cannot be confirmed', (tester) async {
    await tester.pumpWidget(
      _panel(
        cleanupStatusFixture('preview', dirty: true),
        (_) => fail('Must not apply'),
      ),
    );
    await tester.scrollUntilVisible(
      find.byType(AleraCheckbox),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<AleraCheckbox>(find.byType(AleraCheckbox)).enabled,
      false,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    final expired = cleanupStatusFixture('preview');
    (expired['preview']! as Map)['expiresAt'] = 0;
    await tester.pumpWidget(_panel(expired, (_) => fail('Expired preview')));
    await tester.scrollUntilVisible(
      find.byType(AleraCheckbox),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<AleraCheckbox>(find.byType(AleraCheckbox)).enabled,
      false,
    );
  });
  testWidgets(
    'attention retry is explicit and completed receipt has no destructive action',
    (tester) async {
      final calls = <bool>[];
      await tester.pumpWidget(
        _panel(cleanupStatusFixture('attention'), calls.add),
      );
      await tester.scrollUntilVisible(
        find.text('Retry Cleanup'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.widgetWithText(FilledButton, 'Retry Cleanup')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry Cleanup'));
      expect(calls, [true]);
      await tester.pumpWidget(
        _panel(cleanupStatusFixture('retired'), calls.add),
      );
      await tester.pump();
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Open Workspace'), findsNothing);
    },
  );
  testWidgets('compact large text layout stays scrollable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _panel(cleanupStatusFixture('attention'), (_) {}, scale: 2),
    );
    await tester.scrollUntilVisible(
      find.text('Retry Cleanup'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(320, 600));
    await tester.pumpWidget(
      _panel(cleanupStatusFixture('preview'), (_) {}, scale: 2),
    );
    await tester.scrollUntilVisible(
      find.byType(AleraCheckbox),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Widget _panel(
  Map<String, Object?> json,
  ValueChanged<bool> onApply, {
  double scale = 1,
}) => MaterialApp(
  theme: aleraDarkTheme,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: WorkflowCleanupReviewPanel(
        status: WorkflowCleanupStatus.fromJson(json),
        now: DateTime.utc(2026),
        onBack: () {},
        onRefresh: () {},
        onApply: onApply,
        onOpenWorkspace: (_) {},
      ),
    ),
  ),
);
