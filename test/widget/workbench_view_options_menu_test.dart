import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workbench_view_options_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'workbench_view_options_menu_test_support.dart';

void main() {
  group('WorkbenchViewOptionsButton', () {
    testWidgets(
      'Section grouping exposes independent sort controls when supported',
      (tester) async {
        final controller = _ViewOptionsTestController(
          const WorkbenchState(supportsSections: true),
        );
        await _pumpButton(tester, controller);
        await tester.tap(_viewOptionsButton());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Section'));
        await tester.pumpAndSettle();
        expect(controller.state.viewPrefs.groupBy, WorkbenchGroupBy.section);
        expect(find.text('Sort Sections By'), findsOneWidget);
        expect(find.text('Then Workspaces By'), findsOneWidget);
      },
    );

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
      await tester.testTextInput.receiveAction(.done);
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

    testWidgets(
      'retired workspace filters are absent and do not activate the indicator',
      (tester) async {
        final controller = _ViewOptionsTestController(
          WorkbenchState(
            projects: <Project>[_project('project-1', 'Alera')],
            viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
              workspaceKindFilter: .defaultOnly,
            ),
          ),
        );
        await _pumpButton(tester, controller);
        expect(_activeDot(), findsNothing);
        await tester.tap(_viewOptionsButton());
        await tester.pumpAndSettle();
        expect(find.text('Show Workspaces'), findsOneWidget);
        expect(find.text('Active Workspaces Only'), findsOneWidget);
        expect(find.text('Default'), findsNothing);
        expect(find.text('Non-Default'), findsNothing);
      },
    );

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

      await tester.ensureVisible(_optionSwitch('Repeat Pinned Workspaces'));
      await tester.tap(_optionSwitch('Repeat Pinned Workspaces'));
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

      await tester.ensureVisible(_optionSwitch('Active Workspaces Only'));
      await tester.tap(_optionSwitch('Active Workspaces Only'));
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

      final mouse = await tester.createGesture(kind: .mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: .zero);
      await tester.pump();

      await tester.ensureVisible(find.text('Orca').last);
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.text('Orca').last));
      await tester.pumpAndSettle();
      expect(decorationOf().color, AleraTokens.surface);

      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(decorationOf().color, Colors.transparent);
    });

    testWidgets('filters by sections when supported', (tester) async {
      final now = DateTime.utc(2026, 5, 25);
      final controller = _ViewOptionsTestController(
        WorkbenchState(
          supportsSections: true,
          sections: <WorkspaceSection>[
            WorkspaceSection(
              id: 'sec-1',
              name: 'Alpha',
              createdAt: now,
              updatedAt: now,
            ),
            WorkspaceSection(
              id: 'sec-2',
              name: 'Beta',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );

      await _pumpButton(tester, controller);
      await tester.tap(_viewOptionsButton());
      await tester.pumpAndSettle();

      expect(find.text('Sections'), findsOneWidget);
      await tester.ensureVisible(find.text('Alpha').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha').last);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.selectedSectionIds, <String>{'sec-1'});

      final field = _sectionSearchField();
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'be');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.state.viewPrefs.selectedSectionIds, <String>{
        'sec-1',
        'sec-2',
      });

      await tester.tap(find.byIcon(AleraIcons.close).last);
      await tester.pumpAndSettle();
      expect(controller.state.viewPrefs.selectedSectionIds, <String>{'sec-1'});

      final sectionsHeaderRow = find.ancestor(
        of: find.text('Sections'),
        matching: find.byType(Row),
      );
      final sectionsClear = find.descendant(
        of: sectionsHeaderRow,
        matching: find.text('Clear'),
      );
      await tester.tap(sectionsClear);
      await tester.pumpAndSettle();
      expect(controller.state.viewPrefs.selectedSectionIds, isEmpty);
    });
  });
}
