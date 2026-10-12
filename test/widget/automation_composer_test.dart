import 'package:alera/src/design_system/chips/alera_property_chip.dart';
import 'package:alera/src/design_system/forms/alera_duration_field.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_dialog.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_prompt_editor.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';

const Set<String> _withReuse = <String>{
  automationsAuthoringCapability,
  automationTerminalObserveCapability,
  automationReuseCapability,
};

typedef _Composer = ({
  ProviderContainer container,
  FakeAutomationRuntime runtime,
});

/// Context with one resumable agent conversation in Workflow Delivery.
AutomationWorkbenchContext _withConversation() {
  final base = automationTestContext();
  final now = DateTime.utc(2026);
  return AutomationWorkbenchContext(
    projects: base.projects,
    workspaces: base.workspaces,
    profiles: base.profiles,
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      ...base.tabsByWorkspace,
      'ws-1': <WorkspaceTabRecord>[
        WorkspaceTabRecord(
          id: 'agent-tab',
          workspaceId: 'ws-1',
          title: 'Codex Review',
          createdAt: now,
          updatedAt: now,
          payload: const <String, Object?>{'agentNativeSessionId': 'conv-1'},
        ),
      ],
    },
  );
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<_Composer> open(
    WidgetTester tester, {
    AutomationAuthoringRequest request = const AutomationAuthoringRequest(
      originWorkspaceId: 'ws-1',
    ),
    Set<String>? capabilities,
    AutomationWorkbenchContext? context,
    List<Map<String, Object?>> automations = const <Map<String, Object?>>[],
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = FakeAutomationRuntime(
      capabilities:
          capabilities ??
          const <String>{
            automationsAuthoringCapability,
            automationTerminalObserveCapability,
          },
    )..automations = automations;
    final container = automationContainer(runtime, context: context);
    addTearDown(container.dispose);
    addTearDown(runtime.dispose);
    await tester.pumpWidget(AutomationsTestApp(container: container));
    container.read(activityNavigationProvider.notifier).openAutomations();
    await settle(tester);
    container.read(activityNavigationProvider.notifier).startAuthoring(request);
    await settle(tester);
    expect(find.byType(AutomationComposerDialog), findsOneWidget);
    return (container: container, runtime: runtime);
  }

  Finder promptField() => find.descendant(
    of: find.byType(AutomationPromptEditor),
    matching: find.byType(TextField),
  );

  Future<void> typePrompt(WidgetTester tester, String text) async {
    await tester.enterText(promptField(), text);
    await settle(tester);
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  AleraPropertyChip chip(WidgetTester tester, String value) =>
      tester.widget<AleraPropertyChip>(
        find.ancestor(
          of: find.text(value),
          matching: find.byType(AleraPropertyChip),
        ),
      );

  Map<String, Object?> created(FakeAutomationRuntime runtime) =>
      runtime.requestsOf('automation.create').single.payload['automation']!
          as Map<String, Object?>;

  testWidgets('a workspace context seeds the destination, Create activates', (
    tester,
  ) async {
    final f = await open(tester);
    expect(find.text('New Automation'), findsWidgets);
    expect(chip(tester, 'New tab in Workflow Delivery').fromContext, isTrue);
    await typePrompt(tester, 'Review open work');
    await tapButton(tester, 'Create And Activate');
    final sent = created(f.runtime);
    expect(sent.containsKey('state'), isFalse);
    expect(sent.containsKey('reusePolicy'), isFalse);
    expect(sent['originWorkspaceId'], 'ws-1');
    expect(sent['target'], <String, Object?>{
      'freshTab': <String, Object?>{
        'workspaceId': 'ws-1',
        'agentProfileId': 'codex',
      },
    });
    expect(find.byType(AutomationComposerDialog), findsNothing);
    expect(
      f.container.read(activityNavigationProvider).automations.selectedId,
      'created',
    );
  });

  testWidgets('Save As Draft sends a draft', (tester) async {
    final f = await open(tester);
    await typePrompt(tester, 'Review open work');
    await tapButton(tester, 'Save As Draft');
    expect(created(f.runtime)['state'], 'draft');
  });

  testWidgets('without context Create is blocked until a destination', (
    tester,
  ) async {
    final f = await open(tester, request: const AutomationAuthoringRequest());
    expect(chip(tester, 'Choose Destination').hasError, isFalse);
    await typePrompt(tester, 'Review open work');
    await tapButton(tester, 'Create And Activate');
    expect(f.runtime.requestsOf('automation.create'), isEmpty);
    expect(chip(tester, 'Choose Destination').hasError, isTrue);
    expect(find.text('Choose where the automation runs.'), findsOneWidget);
  });

  testWidgets('readiness issues disable Create and mark their chip', (
    tester,
  ) async {
    final f = await open(tester);
    f.runtime.readiness = <String, Object?>{
      'ready': false,
      'issues': <Object?>[
        <String, Object?>{
          'code': 'targetUnavailable',
          'message': 'The workspace is gone.',
          'field': 'target',
          'severity': 'error',
        },
      ],
    };
    await typePrompt(tester, 'Review open work');
    expect(f.runtime.requestsOf('automation.readiness'), isNotEmpty);
    expect(find.text('The workspace is gone.'), findsOneWidget);
    expect(chip(tester, 'New tab in Workflow Delivery').hasError, isTrue);
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create And Activate'),
    );
    expect(create.onPressed, isNull);
  });

  testWidgets('Esc closes a clean composer and asks about a dirty one', (
    tester,
  ) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(AutomationComposerDialog), findsNothing);

    await tester.tap(find.text('New Automation'));
    await settle(tester);
    await typePrompt(tester, 'Review open work');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Discard Changes?'), findsOneWidget);
    await tester.tap(find.text('Discard Changes').last);
    await settle(tester);
    expect(find.byType(AutomationComposerDialog), findsNothing);
  });

  testWidgets('Control+Enter submits from the prompt', (tester) async {
    final f = await open(tester);
    await typePrompt(tester, 'Review open work');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(f.runtime.requestsOf('automation.create'), hasLength(1));
  });

  testWidgets('editing preloads the definition and patches its revision', (
    tester,
  ) async {
    final f = await open(
      tester,
      request: const AutomationAuthoringRequest(editId: 'nightly'),
      automations: <Map<String, Object?>>[automationJson()],
    );
    expect(find.text('Edit Automation'), findsOneWidget);
    expect(find.text('Save As Draft'), findsNothing);
    expect(
      tester.widget<TextField>(promptField()).controller!.text,
      'Review open work',
    );
    await typePrompt(tester, 'Review open work twice');
    await tapButton(tester, 'Save Changes');
    final patch = f.runtime.requestsOf('automation.patch').single.payload;
    expect(patch['id'], 'nightly');
    expect(patch['expectedRevision'], 3);
    expect(
      (patch['changes']! as Map<String, Object?>)['promptTemplate'],
      'Review open work twice',
    );
  });

  testWidgets('reuse is offered only by a runtime that supports it', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Reuse'), findsNothing);
  });

  testWidgets('reuse lists the policies that apply and is sent', (
    tester,
  ) async {
    final f = await open(tester, capabilities: _withReuse);
    await typePrompt(tester, 'Review open work');
    await tester.tap(find.text('New Each Run'));
    await settle(tester);
    expect(find.text('Reuse Conversation'), findsOneWidget);
    expect(find.text('Reuse Workspace'), findsNothing);
    await tester.tap(find.text('Reuse Conversation'));
    await settle(tester);
    await tapButton(tester, 'Create And Activate');
    expect(created(f.runtime)['reusePolicy'], 'reuseConversation');
  });

  testWidgets('a conversation destination continues it, read-only', (
    tester,
  ) async {
    await open(tester, capabilities: _withReuse, context: _withConversation());
    await tester.tap(find.text('New tab in Workflow Delivery'));
    await settle(tester);
    await tester.tap(find.text('Codex Review'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Codex Daily'), findsNothing);
    await tester.tap(find.text(automationContinuesConversationLabel));
    await settle(tester);
    expect(find.textContaining('Every run continues'), findsOneWidget);
    expect(find.text('New Each Run'), findsNothing);
  });

  testWidgets('options show only what applies to the destination', (
    tester,
  ) async {
    await open(tester, capabilities: _withReuse);
    await tester.tap(find.widgetWithText(AleraPropertyChip, 'Options'));
    await settle(tester);
    expect(find.text('When Runs Overlap'), findsOneWidget);
    expect(find.text('Workspace Setup'), findsNothing);
    await tester.tap(find.text('New tab in Workflow Delivery'));
    await settle(tester);
    await tester.tap(find.text('From a branch of the project').first);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Workspace Setup'), findsOneWidget);
    expect(find.text('Cleanup'), findsOneWidget);
    await tester.tap(find.text('New Each Run'));
    await settle(tester);
    await tester.tap(find.text('Reuse Workspace'));
    await settle(tester);
    expect(find.text('Cleanup'), findsNothing);
  });

  testWidgets('a duration is edited in hours and sent in seconds', (
    tester,
  ) async {
    final f = await open(tester);
    await typePrompt(tester, 'Review open work');
    await tester.tap(find.widgetWithText(AleraPropertyChip, 'Options'));
    await settle(tester);
    final inactivity = find.descendant(
      of: find.byType(AleraDurationField),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(inactivity.first);
    await tester.enterText(inactivity.first, '3');
    await settle(tester);
    await tapButton(tester, 'Create And Activate');
    expect(created(f.runtime)['inactivityTimeoutSeconds'], 10800);
  });
}
