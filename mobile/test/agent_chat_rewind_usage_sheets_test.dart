import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_native_history_rewind_sheet.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_usage_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/phone_modal_harness.dart';

const AgentChatRewindOptions _allKinds = AgentChatRewindOptions(
  transcript: true,
  conversation: true,
  files: true,
);

Future<List<AgentChatRewindKind?>> _openRewind(
  WidgetTester tester, {
  double scale = 1,
}) async {
  final answers = <AgentChatRewindKind?>[];
  await openFromPhone(
    tester,
    textScale: scale,
    open: (context) async => answers.add(
      await showAgentChatRewindSheet(context, options: _allKinds),
    ),
  );
  return answers;
}

final AgentChatUsageButton _usage = AgentChatUsageButton(
  usage: AgentChatUsage(
    contextTokens: 123456,
    contextWindow: 200000,
    windows: <AgentChatUsageWindow>[
      AgentChatUsageWindow(
        id: 'session',
        kind: AgentChatUsageWindowKind.session,
        label: '5 Hour Limit',
        usedPercent: 42,
        resetsAt: DateTime.utc(2026, 10, 13, 18),
      ),
      AgentChatUsageWindow(
        id: 'weekly',
        kind: AgentChatUsageWindowKind.weekly,
        label: 'Weekly Limit',
        usedPercent: 12,
        resetsAt: DateTime.utc(2026, 10, 18, 9),
      ),
    ],
  ),
);

Finder _rewindRow(AgentChatRewindKind kind) =>
    find.byKey(ValueKey<String>('agent-chat-rewind-${kind.name}'));

void main() {
  setUpAll(loadShippedInter);

  group('rewind chooser', () {
    testWidgets('a short phone at 200% scrolls to every kind', (tester) async {
      usePhone(tester, size: const Size(320, 568));
      final answers = await _openRewind(tester, scale: 2);
      expect(tester.takeException(), isNull);

      final files = _rewindRow(AgentChatRewindKind.files);
      await tester.scrollUntilVisible(
        files,
        48,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(files);
      await tester.pumpAndSettle();
      expect(tester.getRect(files).bottom, lessThanOrEqualTo(568));
      await tester.tap(files);
      await tester.pumpAndSettle();

      // Picking only leads to the confirmation; nothing runs before it.
      expect(answers, isEmpty);
      expect(find.text('Rewind Files?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Rewind Files'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(answers, <AgentChatRewindKind?>[AgentChatRewindKind.files]);
    });

    testWidgets('the last kind clears the home indicator', (tester) async {
      usePhone(tester, size: const Size(390, 844), homeIndicator: 34);
      final answers = await _openRewind(tester);

      final files = _rewindRow(AgentChatRewindKind.files);
      expect(tester.getRect(files).bottom, lessThanOrEqualTo(844 - 34));
      await tester.tap(_rewindRow(AgentChatRewindKind.transcript));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(answers, <AgentChatRewindKind?>[null]);
    });
  });

  group('usage sheet', () {
    testWidgets('a short phone at 200% scrolls to every limit', (tester) async {
      usePhone(tester, size: const Size(320, 568));
      await openFromPhone(tester, trigger: _usage, textScale: 2);
      expect(tester.takeException(), isNull);

      final weekly = find.text('Weekly Limit');
      await tester.ensureVisible(weekly);
      await tester.pumpAndSettle();
      expect(tester.getRect(weekly).bottom, lessThanOrEqualTo(568));
      expect(tester.getRect(weekly).top, greaterThanOrEqualTo(0));
    });

    testWidgets('the last limit clears the home indicator', (tester) async {
      usePhone(tester, size: const Size(390, 844), homeIndicator: 34);
      await openFromPhone(tester, trigger: _usage);
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.textContaining('12% used')).bottom,
        lessThanOrEqualTo(844 - 34),
      );
    });
  });
}
