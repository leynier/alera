import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
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

      expect(find.text('View options'), findsOneWidget);
      expect(find.text('Sort projects by'), findsOneWidget);

      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.groupBy, WorkbenchGroupBy.none);
      expect(find.text('Sort workspaces by'), findsOneWidget);

      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent').last);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.workspaceSort, WorkbenchSortBy.recent);

      await tester.enterText(find.byType(TextField).last, 'orca');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Orca').last);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.selectedProjectIds, <String>{
        'project-2',
      });
      expect(find.text('Clear'), findsOneWidget);

      await tester.tap(find.text('Clear'));
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

      final field = find.byType(TextField).last;
      await tester.enterText(field, 'or');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.selectedProjectIds, <String>{
        'project-2',
      });
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);

      await tester.tap(find.byIcon(Icons.close).last);
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

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('View options'), findsNothing);

      final filteredController = _ViewOptionsTestController(
        WorkbenchState(projects: <Project>[_project('project-1', 'Alera')]),
      );
      await _pumpButton(tester, filteredController);

      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No projects match "missing"'), findsOneWidget);
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

Finder _viewOptionsButton() {
  return find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'View options',
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
}
