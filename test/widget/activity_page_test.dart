import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/activity/presentation/activity_attention_control.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/automations/presentation/automations_section.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/inbox/presentation/questions_section.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_detail_tab.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/presentation/run_detail_page.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';
import '../support/chat_task_fakes.dart';
import '../support/inbox_test_client.dart';
import '../support/runs_fake_repository.dart';
import '../support/runs_fixtures.dart';
import '../support/runs_harness.dart';

typedef _Fixture = ({
  ProviderContainer container,
  FakeRunRepository board,
  InboxTestClient inbox,
  FakeAutomationRuntime automations,
});

_Fixture _fixture({bool realAttention = false}) {
  final board = FakeRunRepository();
  final inbox = InboxTestClient()
    ..respond('inbox.summary', <String, Object?>{
      'items': [
        {'inbox': 'ext:user', 'threadCount': 2, 'unreadReplyCount': 2},
      ],
      'revision': 1,
    })
    ..respond('inbox.threads', const <String, Object?>{'items': <Object?>[]});
  final chatTasks = FakeChatTaskTransport();
  final automations = FakeAutomationRuntime()
    ..automations = <Map<String, Object?>>[
      automationJson(),
      automationJson(id: 'blocked', name: 'Blocked Sync', state: 'blocked'),
    ];
  final overrides = [
    runRepositoryProvider.overrideWithValue(board),
    runClockProvider.overrideWithValue(() => runsTestNow),
    appForegroundProvider.overrideWithValue(const AlwaysForeground()),
    ...inboxClientOverrides(inbox),
    chatTaskRepositoryProvider.overrideWithValue(
      RuntimeAgentChatOrchestrationRepository(chatTasks),
    ),
  ];
  final container = realAttention
      ? ProviderContainer(
          overrides: [
            ...overrides,
            automationRepositoryProvider.overrideWithValue(
              RuntimeAutomationRepository(automations),
            ),
          ],
        )
      : automationContainer(automations, overrides: overrides);
  addTearDown(container.dispose);
  addTearDown(board.dispose);
  addTearDown(inbox.events.close);
  addTearDown(automations.dispose);
  addTearDown(chatTasks.dispose);
  return (
    container: container,
    board: board,
    inbox: inbox,
    automations: automations,
  );
}

Future<void> _pumpActivity(WidgetTester tester, _Fixture f) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  f.container
      .read(activityNavigationProvider.notifier)
      .open(ActivitySection.runs);
  await tester.pumpWidget(RunsTestApp(container: f.container));
  await tester.pumpAndSettle();
}

Finder _rail(String label) => find.descendant(
  of: find.byKey(const ValueKey<String>('activityRail')),
  matching: find.text(label),
);

void main() {
  testWidgets('the rail switches sections and keeps each selection', (
    tester,
  ) async {
    final f = _fixture();
    await _pumpActivity(tester, f);
    final workspaceBefore = f.container
        .read(workbenchControllerProvider)
        .activeWorkspaceId;

    await tester.tap(find.text('Add OAuth login to the settings page'));
    await tester.pumpAndSettle();
    expect(find.byType(RunDetailPage), findsOneWidget);
    expect(find.text('New Run'), findsOneWidget);

    await tester.tap(_rail('Automations'));
    await tester.pumpAndSettle();
    expect(find.byType(AutomationsSection), findsOneWidget);
    expect(find.text('New Automation'), findsOneWidget);
    await tester.tap(find.text('Blocked Sync').first);
    await tester.pumpAndSettle();

    await tester.tap(_rail('Questions'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestionsSection), findsOneWidget);
    expect(find.text('Ask Agent'), findsOneWidget);

    await tester.tap(_rail('Runs'));
    await tester.pumpAndSettle();
    expect(find.byType(RunDetailPage), findsOneWidget);
    final location = f.container.read(activityNavigationProvider);
    expect(location.runs.runId, 'run-1');
    expect(location.automations.selectedId, 'blocked');
    expect(
      f.container.read(workbenchControllerProvider).activeWorkspaceId,
      workspaceBefore,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rail items are reachable with Tab and activate with Enter', (
    tester,
  ) async {
    final f = _fixture();
    await _pumpActivity(tester, f);
    var reached = false;
    for (var step = 0; step < 40 && !reached; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      reached =
          focused != null &&
          find
              .descendant(
                of: find.byWidget(focused.widget),
                matching: find.text('Questions'),
              )
              .evaluate()
              .isNotEmpty;
    }
    expect(reached, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      f.container.read(activityNavigationProvider).section,
      ActivitySection.questions,
    );
  });

  testWidgets('Esc clears and leaves a focused field before closing', (
    tester,
  ) async {
    final f = _fixture();
    await _pumpActivity(tester, f);
    final search = find.byType(TextField).first;
    await tester.tap(search);
    await tester.enterText(search, 'contract');
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      f.container.read(activityNavigationProvider).runs.search,
      'contract',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(f.container.read(activityNavigationProvider).visible, isTrue);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(f.container.read(activityNavigationProvider).runs.search, isEmpty);

    // The search field's own Esc then leaves the field for the page.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(f.container.read(activityNavigationProvider).visible, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(f.container.read(activityNavigationProvider).visible, isFalse);
    expect(find.text('Open Activity'), findsOneWidget);
  });

  testWidgets('the chip totals every available section and deep-links', (
    tester,
  ) async {
    final f = _fixture(realAttention: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ActivityAttentionControl(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(f.container.read(activityAttentionProvider).total, 5);
    expect(find.text('5'), findsOneWidget);
    expect(
      find.byTooltip('Open Activity · 5 items need attention'),
      findsOneWidget,
    );

    f.board.error = const RunsUpdateRequired();
    f.board.changed();
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('?'), findsNothing);
    expect(
      find.byTooltip(
        'Open Activity · 3 items need attention · Runs unavailable',
      ),
      findsOneWidget,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('activityAttentionChip')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable on this host'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('activityAttention:automations')),
    );
    await tester.pumpAndSettle();
    final location = f.container.read(activityNavigationProvider);
    expect(location.visible, isTrue);
    expect(location.section, ActivitySection.automations);
    expect(
      location.automations.filters.bucket,
      AutomationBucket.needsAttention,
    );

    f.container.read(activityNavigationProvider.notifier).close();
    await tester.tap(
      find.byKey(const ValueKey<String>('activityAttentionChip')),
    );
    await tester.pump();
    expect(f.container.read(activityNavigationProvider).visible, isTrue);
  });

  testWidgets('the hover card lists runs and opens the waiting gate', (
    tester,
  ) async {
    final f = _fixture(realAttention: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ActivityAttentionControl(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('activityAttentionChip')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Add OAuth login to the settings page'), findsOneWidget);
    expect(find.text('Stage gate · 2h ago'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('activityAttentionRun:run-1')),
    );
    await tester.pumpAndSettle();
    final runs = f.container.read(activityNavigationProvider).runs;
    expect(f.container.read(activityNavigationProvider).visible, isTrue);
    expect(runs.runId, 'run-1');
    expect(runs.tab, RunDetailTab.overview);
    expect(runs.gateId, 'gate-stage');
    expect(f.board.calls.map((call) => call.$1), contains('runs.gates'));
  });

  testWidgets('a hover card row that names its gate opens it directly', (
    tester,
  ) async {
    final f = _fixture(realAttention: true);
    f.board.board = runsBoardPage(
      items: <RunSummary>[
        runSummary(
          pendingGates: const <Map<String, Object?>>[
            <String, Object?>{'id': 'gate-named', 'kind': 'stage'},
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ActivityAttentionControl(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('activityAttentionChip')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('activityAttentionRun:run-1')),
    );
    await tester.pumpAndSettle();
    expect(
      f.container.read(activityNavigationProvider).runs.gateId,
      'gate-named',
    );
    expect(f.board.calls.map((call) => call.$1), isNot(contains('runs.gates')));
  });
}
