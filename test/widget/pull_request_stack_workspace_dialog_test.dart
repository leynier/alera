import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_stack_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _one = ReviewStackWorkspaceCandidate(
  workspaceId: 'workspace-one',
  name: 'Workspace One',
  repoPath: '/repo-one',
  branch: 'feature/one',
  current: false,
);

const _two = ReviewStackWorkspaceCandidate(
  workspaceId: 'workspace-two',
  name: 'Workspace Two',
  repoPath: '/repo-two',
  branch: 'feature/two',
  current: true,
  sourceBranch: 'feature/one',
  parentWorkspaceId: 'workspace-one',
);

const _three = ReviewStackWorkspaceCandidate(
  workspaceId: 'workspace-three',
  name: 'Workspace Three',
  repoPath: '/repo-three',
  branch: 'feature/three',
  current: false,
  sourceBranch: 'feature/two',
  parentWorkspaceId: 'workspace-two',
);

Widget _launcher({
  required ValueChanged<ReviewStackWorkspaceRequest?> onResult,
  List<ReviewStackWorkspaceCandidate> candidates =
      const <ReviewStackWorkspaceCandidate>[_one, _two],
  bool defaultDraft = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            final result = await showDialog<ReviewStackWorkspaceRequest>(
              context: context,
              builder: (_) => PullRequestStackWorkspaceDialog(
                currentTitle: 'feat: second layer',
                currentDraft: defaultDraft,
                candidates: candidates,
                baseBranches: const <String>['main', 'develop'],
                suggestedBaseBranch: 'main',
                defaultDraft: defaultDraft,
              ),
            );
            onResult(result);
          },
          child: const Text('Open Dialog'),
        ),
      ),
    ),
  );
}

Finder _field(String label, int index) {
  return find
      .byWidgetPredicate(
        (widget) => widget is AleraTextField && widget.labelText == label,
      )
      .at(index);
}

void main() {
  testWidgets('preselects the current workspace ancestry chain', (
    tester,
  ) async {
    ReviewStackWorkspaceRequest? result;
    await tester.pumpWidget(_launcher(onResult: (value) => result = value));

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('1. Workspace One'), findsOneWidget);
    expect(find.text('feature/one → main'), findsOneWidget);
    final firstRemove = tester.widget<AleraIconButton>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is AleraIconButton &&
                widget.tooltip == 'Remove Workspace',
          )
          .first,
    );
    expect(firstRemove.onPressed, isNotNull);

    final firstTitle = tester.widget<AleraTextField>(
      _field('Pull Request Title', 0),
    );
    final firstBody = tester.widget<AleraTextField>(
      _field('Pull Request Description', 0),
    );
    firstTitle.controller!.text = 'feat: configured first layer';
    firstBody.controller!.text = 'Configured body';
    await tester.tap(find.text('Create As Draft').first);
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('2. Workspace Two'),
      220,
      scrollable: find.ancestor(
        of: find.text('1. Workspace One'),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('feature/two → feature/one'), findsOneWidget);
    final currentRemove = tester
        .widgetList<AleraIconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AleraIconButton &&
                widget.tooltip == 'Remove Workspace',
          ),
        )
        .last;
    expect(currentRemove.onPressed, isNull);

    await tester.tap(find.text('Create Stack'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.baseBranch, 'main');
    expect(result!.layers.map((layer) => layer.branch), <String>[
      'feature/one',
      'feature/two',
    ]);
    expect(result!.layers.first.title, 'feat: configured first layer');
    expect(result!.layers.first.body, 'Configured body');
    expect(result!.layers.first.draft, isFalse);
    expect(result!.layers.last.title, 'feat: second layer');
    expect(result!.layers.last.draft, isTrue);
  });

  testWidgets('adds and reorders workspace layers explicitly', (tester) async {
    ReviewStackWorkspaceRequest? result;
    await tester.pumpWidget(
      _launcher(
        candidates: const <ReviewStackWorkspaceCandidate>[_one, _two, _three],
        defaultDraft: false,
        onResult: (value) => result = value,
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    final addField = tester.widget<AleraDropdownField<String?>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AleraDropdownField<String?> &&
            widget.labelText == 'Add Workspace',
      ),
    );
    addField.onChanged('workspace-three');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('3. Workspace Three'),
      260,
      scrollable: find.ancestor(
        of: find.text('1. Workspace One'),
        matching: find.byType(Scrollable),
      ),
    );

    final moveUpButtons = tester
        .widgetList<AleraIconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AleraIconButton && widget.tooltip == 'Move Up',
          ),
        )
        .toList();
    moveUpButtons.last.onPressed!();
    await tester.pump();

    await tester.tap(find.text('Create Stack'));
    await tester.pumpAndSettle();

    expect(result!.layers.map((layer) => layer.branch), <String>[
      'feature/one',
      'feature/three',
      'feature/two',
    ]);
  });
}
