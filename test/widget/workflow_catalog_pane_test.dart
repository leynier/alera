import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_catalog_pane.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_widget_harness.dart';
import '../support/workflow_catalog_fixture.dart';

void main() {
  testWidgets('Open File uses the source workspace without a preview', (
    tester,
  ) async {
    final workbench = _FileOpenWorkbench();
    await _pumpProjectRecipe(tester, workbench);
    await tester.tap(find.text('Open File'));
    await tester.pumpAndSettle();
    expect(workbench.actions, contains('workspace:ws-1'));
    expect(workbench.opens, [(false, false)]);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('Mod+Open File previews opposite panel on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final workbench = _FileOpenWorkbench()
        ..pendingSelection = Completer<void>();
      await _pumpProjectRecipe(tester, workbench);
      final key = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(key);
      await tester.tap(find.text('Open File'));
      await tester.pump();
      expect(workbench.opens, isEmpty);
      await tester.sendKeyUpEvent(key);
      workbench.pendingSelection!.complete();
      await tester.pumpAndSettle();
      expect(workbench.opens, [(true, true)]);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('compact navigation preserves visible search and clear', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = CatalogTestRepository()
      ..entries = [
        {'source': workflowCatalogRecord['source'], 'name': 'Feature Delivery'},
        {
          'source': {'origin': 'builtin', 'id': 'quick-fix'},
          'name': 'Quick Fix',
        },
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workflowCatalogRepositoryProvider.overrideWithValue(repository),
          workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(body: WorkflowCatalogPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quick Fix'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Feature');
    await tester.pumpAndSettle();
    expect(find.text('Quick Fix'), findsNothing);
    await tester.tap(find.text('Feature Delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    expect(find.text('Feature'), findsOneWidget);
    expect(find.text('Quick Fix'), findsNothing);
    expect(find.byTooltip('Clear'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Quick Fix'), findsOneWidget);
    expect(find.text('Feature Delivery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (newerDraft, copy, renamed) in [
    (false, false, false),
    (true, false, false),
    (true, true, false),
    (true, true, true),
  ]) {
    testWidgets(
      'save after closing reconciles draft, newer=$newerDraft copy=$copy renamed=$renamed',
      (tester) async {
        final pending = Completer<Map<String, Object?>>();
        final repository = CatalogTestRepository()..pendingSave = pending;
        final container = ProviderContainer(
          overrides: [
            workflowCatalogRepositoryProvider.overrideWithValue(repository),
            workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
          ],
        );
        addTearDown(container.dispose);
        Widget app(Widget child) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAleraDarkTheme(),
            home: Scaffold(body: child),
          ),
        );
        await tester.pumpWidget(app(const WorkflowCatalogPane()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Feature Delivery'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(copy ? 'Copy To Personal' : 'Edit Personal'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Personal'));
        await tester.pump();
        expect(repository.saves, 1);
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpWidget(app(const WorkflowCatalogPane()));
        await tester.pumpAndSettle();
        if (newerDraft) {
          await tester.enterText(
            find.widgetWithText(TextField, 'portable document'),
            'newer draft',
          );
        }
        if (renamed) repository.validatedId = 'renamed-copy';
        pending.complete({...workflowCatalogRecord, 'catalogRevision': 4});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          container.read(workflowCatalogDraftProvider)!.revision,
          renamed ? null : 4,
        );
        expect(
          find.textContaining('Catalog Revision ${renamed ? 3 : 4}'),
          findsOneWidget,
        );
        if (newerDraft) expect(find.text('newer draft'), findsOneWidget);
        repository.pendingSave = null;
        repository.requiredRevision = renamed ? null : 4;
        await tester.tap(find.text('Save Personal'));
        await tester.pumpAndSettle();
        expect(repository.savedRevisions, [
          copy ? null : 3,
          renamed ? null : 4,
        ]);
        expect(find.text('Personal recipe saved.'), findsOneWidget);
        expect(container.read(workflowCatalogDraftProvider), isNull);
      },
    );
  }

  testWidgets('failed save preserves edit and navigation retains draft', (
    tester,
  ) async {
    final repository = CatalogTestRepository();
    final container = ProviderContainer(
      overrides: [
        workflowCatalogRepositoryProvider.overrideWithValue(repository),
        workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
      ],
    );
    addTearDown(container.dispose);
    Widget app(Widget child) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpWidget(app(const WorkflowCatalogPane()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feature Delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Personal'));
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, 'portable document');
    await tester.enterText(input, 'retained draft');
    repository.failure = StateError(
      'The recipe changed. Refresh before saving.',
    );
    await tester.tap(find.text('Save Personal'));
    await tester.pumpAndSettle();
    expect(find.text('retained draft'), findsOneWidget);
    expect(repository.saves, 1);
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpWidget(app(const WorkflowCatalogPane()));
    await tester.pumpAndSettle();
    expect(find.text('retained draft'), findsOneWidget);
    await tester.tap(find.text('Discard Edit'));
    await tester.pumpAndSettle();
    expect(container.read(workflowCatalogDraftProvider), isNull);
  });

  testWidgets('editing cannot overwrite a different personal id', (
    tester,
  ) async {
    final repository = CatalogTestRepository()..validatedId = 'another-id';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workflowCatalogRepositoryProvider.overrideWithValue(repository),
          workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(body: WorkflowCatalogPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feature Delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Personal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Personal'));
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    expect(find.textContaining('Keep the recipe id'), findsOneWidget);
  });
}

const _projectSource = <String, Object?>{
  'origin': 'project',
  'id': 'feature-delivery',
  'workspaceId': 'ws-1',
  'path': '.alera/workflows/feature-delivery.yaml',
};

Future<void> _pumpProjectRecipe(
  WidgetTester tester,
  _FileOpenWorkbench workbench,
) async {
  final repository = _ProjectCatalogTestRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workflowCatalogRepositoryProvider.overrideWithValue(repository),
        workbenchControllerProvider.overrideWith(() => workbench),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(body: WorkflowCatalogPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Feature Delivery'));
  await tester.pumpAndSettle();
  expect(find.text('Open File'), findsOneWidget);
}

class _ProjectCatalogTestRepository extends CatalogTestRepository {
  _ProjectCatalogTestRepository() {
    entries = [
      {'source': _projectSource, 'name': 'Feature Delivery'},
    ];
  }

  @override
  Future<Map<String, Object?>> read(Map<String, Object?> source) async => {
    ...workflowCatalogRecord,
    'source': _projectSource,
  };
}

class _FileOpenWorkbench extends BoardTestWorkbench {
  Completer<void>? pendingSelection;
  final opens = <(bool, bool)>[];

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    if (pendingSelection != null) await pendingSelection!.future;
    await super.selectWorkspace(project: project, workspace: workspace);
  }

  @override
  Future<WorkspaceTabRecord> openEditorTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
    bool oppositePanel = false,
  }) async {
    opens.add((preview, oppositePanel));
    final now = DateTime.utc(2026);
    return WorkspaceTabRecord(
      id: 'recipe-file',
      workspaceId: workspace.id,
      title: relativePath,
      createdAt: now,
      updatedAt: now,
    );
  }
}
