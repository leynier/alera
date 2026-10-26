import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_usage_popover.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, AgentChatUsage usage) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Center(child: AgentChatUsageButton(usage: usage)),
        ),
      ),
    );

void main() {
  testWidgets('hidden when the provider reports no usage', (tester) async {
    await _pump(tester, const AgentChatUsage());
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('opens the context window and limits with reset times', (
    tester,
  ) async {
    await _pump(
      tester,
      AgentChatUsage(
        contextTokens: 50000,
        contextWindow: 200000,
        windows: <AgentChatUsageWindow>[
          AgentChatUsageWindow(
            id: 'weekly',
            kind: AgentChatUsageWindowKind.weekly,
            label: 'Weekly Limit',
            usedPercent: 95,
            resetsAt: DateTime(2026, 10, 14, 9, 30),
          ),
          const AgentChatUsageWindow(
            id: 'session',
            kind: AgentChatUsageWindowKind.session,
            label: 'Session',
            usedPercent: 12,
          ),
        ],
      ),
    );
    expect(find.byTooltip('Context 25% Used'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('agent-chat-usage')));
    await tester.pumpAndSettle();

    expect(find.text('Usage'), findsOneWidget);
    expect(find.text('Context Window'), findsOneWidget);
    expect(find.text('25% used, 50,000 of 200,000 tokens'), findsOneWidget);
    expect(find.text('Weekly Limit'), findsOneWidget);
    expect(find.textContaining('95% used, resets Oct 14'), findsOneWidget);
    expect(find.text('12% used'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Weekly Limit'), findsNothing);
  });
}
