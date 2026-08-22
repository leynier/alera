import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workbench_view_options_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkbenchViewOptionsButton', () {
    testWidgets('opens the dialog and updates grouping, sorting, and filters', (
      tester,
    ) async {
      final controller = _ViewOptionsTestController(
        WorkbenchState(
          projects: <Project>[
            _project('project-1', 'Alera'),
            _project('project-2', 'Orca'),
          ],
        ),
      );

      await _pumpButton(tester, controller);

      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      expect(find.text('View Options'), findsOneWidget);
      expect(find.text('Sort Projects By'), findsOneWidget);

      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.groupBy, WorkbenchGroupBy.none);
      expect(find.text('Sort Workspaces By'), findsOneWidget);

      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent').last);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.workspaceSort, WorkbenchSortBy.recent);

      await tester.enterText(_projectSearchField(), 'orca');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Orca').last);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.selectedProjectIds, <String>{
        'project-2',
      });
      expect(find.text('Clear'), findsNWidgets(2));

      await tester.tap(find.text('Clear').first);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.selectedProjectIds, isEmpty);
    });

    testWidgets('submits the first project match and removes its chip', (
      tester,
    ) async {
      final controller = _ViewOptionsTestController(
        WorkbenchState(
          projects: <Project>[
            _project('project-1', 'Alera'),
            _project('project-2', 'Orca'),
          ],
        ),
      );

      await _pumpButton(tester, controller);

      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      final field = _projectSearchField();
      await tester.enterText(field, 'or');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.selectedProjectIds, <String>{
        'project-2',
      });
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);

      await tester.tap(find.byIcon(AleraIcons.close).last);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.selectedProjectIds, isEmpty);
    });

    testWidgets('shows empty project states and can dismiss the dialog', (
      tester,
    ) async {
      final emptyController = _ViewOptionsTestController(
        const WorkbenchState(),
      );
      await _pumpButton(tester, emptyController);

      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();
      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.text('No tags yet'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('View Options'), findsNothing);

      final filteredController = _ViewOptionsTestController(
        WorkbenchState(projects: <Project>[_project('project-1', 'Alera')]),
      );
      await _pumpButton(tester, filteredController);

      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      await tester.enterText(_projectSearchField(), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No projects match "missing"'), findsOneWidget);
    });

    testWidgets('updates the workspace kind filter and shows the active dot', (
      tester,
    ) async {
      final controller = _ViewOptionsTestController(
        WorkbenchState(projects: <Project>[_project('project-1', 'Alera')]),
      );

      await _pumpButton(tester, controller);

      expect(_activeDot(), findsNothing);

      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      expect(find.text('Show Workspaces'), findsOneWidget);
      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();

      expect(
        controller.state.viewPrefs.workspaceKindFilter,
        WorkspaceKindFilter.defaultOnly,
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(_activeDot(), findsOneWidget);

      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('All').first);
      await tester.pumpAndSettle();

      expect(
        controller.state.viewPrefs.workspaceKindFilter,
        WorkspaceKindFilter.all,
      );
    });

    testWidgets('toggles pinned workspace copies below the pinned section', (
      tester,
    ) async {
      final controller = _ViewOptionsTestController(
        WorkbenchState(projects: <Project>[_project('project-1', 'Alera')]),
      );

      await _pumpButton(tester, controller);
      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      final option = find.text('Repeat Pinned Workspaces');
      expect(option, findsOneWidget);
      expect(controller.state.viewPrefs.showPinnedWorkspacesBelow, isTrue);

      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(controller.state.viewPrefs.showPinnedWorkspacesBelow, isFalse);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(_activeDot(), findsOneWidget);
    });

    testWidgets('toggles the active workspaces filter', (tester) async {
      final controller = _ViewOptionsTestController(
        WorkbenchState(projects: <Project>[_project('project-1', 'Alera')]),
      );

      await _pumpButton(tester, controller);
      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      final option = find.text('Active Workspaces Only');
      expect(option, findsOneWidget);
      expect(controller.state.viewPrefs.showActiveWorkspacesOnly, isFalse);

      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(controller.state.viewPrefs.showActiveWorkspacesOnly, isTrue);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(_activeDot(), findsOneWidget);
    });

    testWidgets('available project rows animate their hover state', (
      tester,
    ) async {
      final controller = _ViewOptionsTestController(
        WorkbenchState(
          projects: <Project>[
            _project('project-1', 'Alera'),
            _project('project-2', 'Orca'),
          ],
        ),
      );

      await _pumpButton(tester, controller);
      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      final rowContainer = find.ancestor(
        of: find.text('Orca').last,
        matching: find.byType(AnimatedContainer),
      );
      BoxDecoration decorationOf() =>
          tester.widget<AnimatedContainer>(rowContainer.first).decoration!
              as BoxDecoration;

      expect(decorationOf().color, Colors.transparent);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();

      await mouse.moveTo(tester.getCenter(find.text('Orca').last));
      await tester.pumpAndSettle();
      expect(decorationOf().color, AleraTokens.surface);

      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(decorationOf().color, Colors.transparent);
    });
  });
}

Future<void> _pumpButton(
  WidgetTester tester,
  _ViewOptionsTestController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [workbenchControllerProvider.overrideWith(() => controller)],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: WorkbenchViewOptionsButton())),
      ),
    ),
  );
  await tester.pump();
}

Finder _projectSearchField() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Add project\u2026',
  );
}

Finder _viewOptionsButton() {
  return find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'View options',
  );
}

Finder _activeDot() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).shape == BoxShape.circle &&
        (widget.decoration! as BoxDecoration).color == AleraTokens.accent,
  );
}

Project _project(String id, String name) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/$id',
    createdAt: now,
    updatedAt: now,
  );
}

class _ViewOptionsTestController extends WorkbenchController {
  _ViewOptionsTestController(this._seed);

  final WorkbenchState _seed;

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<List<WorkspaceTag>> listWorkspaceTags() async =>
      const <WorkspaceTag>[];

  @override
  void setGroupBy(WorkbenchGroupBy groupBy) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(groupBy: groupBy),
    );
  }

  @override
  void setProjectSort(WorkbenchSortBy sort) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(projectSort: sort),
    );
  }

  @override
  void setWorkspaceSort(WorkbenchSortBy sort) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(workspaceSort: sort),
    );
  }

  @override
  void addProjectFilter(String projectId) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        selectedProjectIds: <String>{
          ...state.viewPrefs.selectedProjectIds,
          projectId,
        },
      ),
    );
  }

  @override
  void removeProjectFilter(String projectId) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        selectedProjectIds: state.viewPrefs.selectedProjectIds
            .where((id) => id != projectId)
            .toSet(),
      ),
    );
  }

  @override
  void clearProjectFilters() {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(selectedProjectIds: <String>{}),
    );
  }

  @override
  void setWorkspaceKindFilter(WorkspaceKindFilter filter) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(workspaceKindFilter: filter),
    );
  }

  @override
  void setShowActiveWorkspacesOnly(bool show) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(showActiveWorkspacesOnly: show),
    );
  }

  @override
  void setShowPinnedWorkspacesBelow(bool show) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(showPinnedWorkspacesBelow: show),
    );
  }
}
