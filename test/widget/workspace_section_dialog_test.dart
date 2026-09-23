// ignore_for_file: riverpod_lint/avoid_public_notifier_properties

import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:alera/src/features/workbench/presentation/background_operation_cards.dart';
import 'package:alera/src/features/workbench/presentation/workspace_section_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 30);
final _workspace = Workspace(
  id: 'w',
  projectId: 'p',
  name: 'Workspace',
  path: '/w',
  createdAt: _now,
  updatedAt: _now,
  kind: WorkspaceKind.linked,
  status: WorkspaceStatus.active,
);

class _Controller extends WorkbenchController {
  int saves = 0;
  String? name;
  String? section;
  bool fail = false;
  bool tree = false;
  Completer<void>? pending;
  @override
  Future<List<WorkspaceSection>> listWorkspaceSections() async => [
    WorkspaceSection(
      id: 'existing',
      name: 'Existing',
      createdAt: _now,
      updatedAt: _now,
    ),
  ];
  @override
  Future<void> saveWorkspaceSection(
    String workspaceId, {
    String? sectionId,
    String? newName,
  }) async {
    await pending?.future;
    if (fail) throw StateError('Section no longer exists');
    saves++;
    name = newName;
    section = sectionId;
  }

  @override
  Future<void> saveWorkspaceSectionTree(
    String workspaceId, {
    String? sectionId,
    String? newName,
  }) async {
    tree = true;
    await saveWorkspaceSection(
      workspaceId,
      sectionId: sectionId,
      newName: newName,
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  _Controller controller, {
  bool applyToTree = false,
  bool createMode = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: aleraDarkTheme,
        builder: (context, child) => Stack(
          children: [
            child!,
            const Align(
              alignment: Alignment.bottomRight,
              child: BackgroundOperationCards(),
            ),
          ],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWorkspaceSectionDialog(
                context,
                controller,
                _workspace,
                applyToTree: applyToTree,
                createMode: createMode,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String name) async {
  await tester.tap(find.text('No Section'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a refused section save retains its draft and remains editable', (
    tester,
  ) async {
    final controller = _Controller()..pending = Completer<void>();
    await _open(tester, controller, createMode: true);
    await tester.enterText(find.byType(TextField), 'First section');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField), 'Second section');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Set Section'), findsOneWidget);
    expect(find.text('Second section'), findsOneWidget);
    expect(find.text('This operation is already running.'), findsOneWidget);
    controller.pending!.complete();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Updated section');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.saves, 2);
    expect(controller.name, 'Updated section');
    expect(find.text('Set Section'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section save releases the dialog before the request finishes', (
    tester,
  ) async {
    final controller = _Controller()..pending = Completer<void>();
    await _open(tester, controller);
    await _choose(tester, 'Existing');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Set Section'), findsNothing);
    expect(find.text('You can keep using the app.'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    controller.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Set Section'), findsOneWidget);
    expect(controller.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creating is deferred until Save and Cancel creates nothing', (
    tester,
  ) async {
    final controller = _Controller();
    await _open(tester, controller);
    await _choose(tester, 'New Section');
    await tester.enterText(find.byType(TextField), ' New Work ');
    expect(controller.saves, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.saves, 0);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _choose(tester, 'New Section');
    await tester.enterText(find.byType(TextField), ' New Work ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.name, 'New Work');
    expect(controller.saves, 1);
    expect(find.text('Set Section'), findsNothing);
  });
  testWidgets(
    'selects an existing section and restores the form after a failed background save',
    (tester) async {
      final controller = _Controller()..fail = true;
      await _open(tester, controller);
      await _choose(tester, 'Existing');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Section no longer exists'), findsOneWidget);
      expect(find.text('Set Section'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Set Section'), findsOneWidget);
      controller.fail = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.section, 'existing');
      expect(controller.saves, 1);
    },
  );

  testWidgets('create mode shows the name field without picking New Section', (
    tester,
  ) async {
    final controller = _Controller();
    await _open(tester, controller, createMode: true);
    await tester.enterText(find.byType(TextField), 'Fresh');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.name, 'Fresh');
    expect(controller.tree, isFalse);
  });

  testWidgets('tree mode saves through saveWorkspaceSectionTree', (
    tester,
  ) async {
    final controller = _Controller();
    await _open(tester, controller, applyToTree: true);
    expect(find.text('Set Section Tree'), findsOneWidget);
    await _choose(tester, 'Existing');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.tree, isTrue);
    expect(controller.section, 'existing');
  });
}
