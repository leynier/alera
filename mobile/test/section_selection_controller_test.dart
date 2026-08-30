import 'package:flutter/material.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/presentation/section_picker_sheet.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/section_selection_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client implements MobileWorkspaceClient, MobileWorkspaceSectionClient {
  int writes = 0;
  String? name;
  String? sectionId;
  bool fail = false;
  List<WorkspaceSectionSummary> sections = [
    WorkspaceSectionSummary(
      id: 's',
      name: 'Work',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ];
  @override
  bool get supportsWorkspaceSections => true;
  @override
  Future<List<WorkspaceSectionSummary>> listWorkspaceSections() async =>
      sections;
  @override
  Future<void> createWorkspaceSection(String name, String workspaceId) async {
    writes++;
    this.name = name;
  }

  @override
  Future<void> setWorkspaceSection(
    String workspaceId,
    String? sectionId,
  ) async {
    if (fail) {
      sections = [];
      throw StateError('Section no longer exists');
    }
    writes++;
    this.sectionId = sectionId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'mobile selection sheet saves and closes after creating a section',
    (tester) async {
      final client = _Client();
      const workspace = WorkspaceSummary(
        id: 'workspace',
        projectId: 'project',
        name: 'Workspace',
        path: '/workspace',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceClientProvider('host').overrideWith((ref) async => client),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showSectionPickerSheet(
                    context,
                    hostId: 'host',
                    workspace: workspace,
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
      await tester.tap(find.text('No Section'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Section'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New Work');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(client.writes, 1);
      expect(client.name, 'New Work');
      expect(find.text('Set Section'), findsNothing);
    },
  );

  test('selection edits are local until Save and creation validates reserved names', () async {
    final client = _Client();
    final container = ProviderContainer.test(
      overrides: [
        workspaceClientProvider('host').overrideWith((ref) async => client),
      ],
    );
    final provider = sectionSelectionControllerProvider(
      'host',
      'workspace',
      null,
    );
    container.listen(provider, (_, _) {});
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    controller.select('__new__');
    controller.nameChanged('Others');
    expect(client.writes, 0);
    expect(await controller.save(), isFalse);
    expect(client.writes, 0);
    controller.nameChanged('  New Work  ');
    expect(await controller.save(), isTrue);
    expect(client.name, 'New Work');
    expect(client.writes, 1);
    expect(container.read(provider).requireValue.saving, isFalse);
  });
  test(
    'missing section refreshes options without closing and allows retry',
    () async {
      final client = _Client()..fail = true;
      final container = ProviderContainer.test(
        overrides: [
          workspaceClientProvider('host').overrideWith((ref) async => client),
        ],
      );
      final provider = sectionSelectionControllerProvider(
        'host',
        'workspace',
        's',
      );
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final controller = container.read(provider.notifier);
      expect(await controller.save(), isFalse);
      expect(container.read(provider).requireValue.sections, isEmpty);
      expect(container.read(provider).requireValue.selected, '');
      expect(
        container.read(provider).requireValue.error,
        contains('Section no longer exists'),
      );
      client.fail = false;
      expect(await controller.save(), isTrue);
      expect(client.sectionId, isNull);
    },
  );
}
