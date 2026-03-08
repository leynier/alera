import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/presentation/widgets/composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpComposer(
  WidgetTester tester, {
  required TextEditingController controller,
  List<AleraCommand> availableCommands = const <AleraCommand>[],
  List<ComposerDraftItem> draftItems = const <ComposerDraftItem>[],
  ValueChanged<AleraCommand>? onImmediateCommandSelected,
  ValueChanged<String>? onRemoveDraftItem,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Composer(
          controller: controller,
          textFieldEnabled: true,
          canSend: true,
          canStop: false,
          canChangeModel: true,
          isBusy: false,
          isInterrupting: false,
          activeModelId: 'gpt-5.3-codex',
          availableModels: const <CodexModelOption>[
            CodexModelOption(id: 'gpt-5.3-codex', label: 'GPT-5.3 Codex'),
          ],
          onModelChanged: (_) {},
          activeReasoningEffort: 'high',
          supportedReasoningEfforts: const <String>['low', 'medium', 'high'],
          onReasoningEffortChanged: (_) {},
          onSend: () {},
          onInterrupt: () {},
          availableCommands: availableCommands,
          draftItems: draftItems,
          onImmediateCommandSelected: onImmediateCommandSelected,
          onRemoveDraftItem: onRemoveDraftItem,
          onPermissionModeSelected: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('selecting built-in slash command triggers native callback', (
    tester,
  ) async {
    final controller = TextEditingController();
    AleraCommand? selectedCommand;
    addTearDown(controller.dispose);

    await _pumpComposer(
      tester,
      controller: controller,
      availableCommands: builtinAleraCommands(),
      onImmediateCommandSelected: (command) => selectedCommand = command,
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '/re');
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('/review'), findsOneWidget);

    await tester.tap(find.text('/review'));
    await tester.pump();

    expect(selectedCommand?.builtinId, BuiltinCommandId.review);
    expect(controller.text, isEmpty);
  });

  testWidgets('selecting custom slash command inserts command text', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpComposer(
      tester,
      controller: controller,
      availableCommands: const <AleraCommand>[
        AleraCommand(
          name: 'deploy',
          description: 'Deploy the current branch',
          kind: AleraCommandKind.custom,
          scope: CustomCommandScope.repo,
          content: 'Deploy \$ARGUMENTS',
        ),
      ],
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '/dep');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.tap(find.text('/deploy'));
    await tester.pump();

    expect(controller.text, '/deploy ');
  });

  testWidgets('draft chips render and can be removed', (tester) async {
    final controller = TextEditingController();
    String? removedId;
    addTearDown(controller.dispose);

    await _pumpComposer(
      tester,
      controller: controller,
      draftItems: const <ComposerDraftItem>[
        ComposerDraftItem(
          id: 'app-demo',
          kind: ComposerDraftItemKind.mention,
          name: 'demo-app',
          path: 'app://demo-app',
          tokenText: '\$demo-app',
        ),
      ],
      onRemoveDraftItem: (id) => removedId = id,
    );

    expect(find.text('\$demo-app'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(removedId, 'app-demo');
  });

  testWidgets('plan label uses the info token when plan mode is active', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            controller: controller,
            textFieldEnabled: true,
            canSend: true,
            canStop: false,
            canChangeModel: true,
            isBusy: false,
            isInterrupting: false,
            activeModelId: 'gpt-5.3-codex',
            availableModels: const <CodexModelOption>[
              CodexModelOption(id: 'gpt-5.3-codex', label: 'GPT-5.3 Codex'),
            ],
            onModelChanged: (_) {},
            activeReasoningEffort: 'high',
            supportedReasoningEfforts: const <String>['low', 'medium', 'high'],
            onReasoningEffortChanged: (_) {},
            onSend: () {},
            onInterrupt: () {},
            planModeEnabled: true,
            onPermissionModeSelected: (_) {},
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Plan'));
    expect(text.style?.color, AleraTokens.info);
  });
}
