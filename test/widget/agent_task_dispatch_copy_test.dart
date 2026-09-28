import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_dialog.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messages = <AleraToastData>[];
  final copied = <String>[];
  var failClipboard = false;
  Completer<void>? pendingCopy;
  late StreamSubscription<AleraToastData> subscription;

  setUp(() {
    messages.clear();
    copied.clear();
    failClipboard = false;
    pendingCopy = null;
    subscription = AleraToast.stream.listen(messages.add);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (failClipboard) throw PlatformException(code: 'unavailable');
          await pendingCopy?.future;
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
  });

  tearDown(() async {
    await subscription.cancel();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Future<void> openPicker(
    WidgetTester tester, {
    String prompt = '  Fix the checks.\n\nKeep the español context.\n  ',
    AgentTaskDispatchCatalog catalog = const AgentTaskDispatchCatalog(),
    ValueChanged<AgentTaskDispatchSelection?>? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showAgentTaskDispatchPicker(
                  context,
                  request: AgentTaskDispatchRequest(
                    workspaceId: 'workspace-1',
                    prompt: prompt,
                  ),
                  catalog: catalog,
                );
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('copies the dispatch prompt even without agents', (tester) async {
    var completed = false;
    await openPicker(tester, onResult: (_) => completed = true);
    expect(find.text('No Agents Available'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy Prompt'));
    await tester.pumpAndSettle();

    expect(copied, ['Fix the checks.\n\nKeep the español context.']);
    expect(messages.single.message, 'Prompt copied.');
    expect(messages.single.tone, AleraToastTone.success);
    expect(completed, isFalse);
    expect(find.byType(AgentTaskDispatchDialog), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets('copying still allows selecting a new agent afterward', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 28);
    AgentTaskDispatchSelection? selected;
    await openPicker(
      tester,
      catalog: AgentTaskDispatchCatalog(
        profiles: [
          AgentProfile(
            id: 'profile-1',
            name: 'Codex Builder',
            agentType: 'codex',
            command: 'codex',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
      onResult: (result) => selected = result,
    );
    await tester.tap(find.byTooltip('Copy Prompt'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Codex Builder'));
    await tester.pumpAndSettle();
    expect(
      selected,
      isA<AgentTaskDispatchNewTabSelection>().having(
        (selection) => selection.profileId,
        'profileId',
        'profile-1',
      ),
    );
    expect(copied, hasLength(1));
  });

  testWidgets('hides copy for a picker without a prompt', (tester) async {
    await openPicker(tester, prompt: ' \n ');
    expect(find.byTooltip('Copy Prompt'), findsNothing);
    expect(copied, isEmpty);
  });

  testWidgets('clipboard failure reports an error and allows retry', (
    tester,
  ) async {
    failClipboard = true;
    await openPicker(tester);
    await tester.tap(find.byTooltip('Copy Prompt'));
    await tester.pumpAndSettle();
    expect(copied, isEmpty);
    expect(messages.single.tone, AleraToastTone.error);
    expect(messages.single.message, 'Could not copy the prompt. Try again.');
    expect(find.byType(AgentTaskDispatchDialog), findsOneWidget);

    failClipboard = false;
    await tester.tap(find.byTooltip('Copy Prompt'));
    await tester.pumpAndSettle();
    expect(copied, hasLength(1));
    expect(messages.last.tone, AleraToastTone.success);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing while clipboard is pending does not show a stale toast',
    (tester) async {
      pendingCopy = Completer<void>();
      await openPicker(tester);
      await tester.tap(find.byTooltip('Copy Prompt'));
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      pendingCopy!.complete();
      await tester.pumpAndSettle();
      expect(copied, hasLength(1));
      expect(messages, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
