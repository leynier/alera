import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/chat_tasks/presentation/delegate_chat_task_agent_fields.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const AgentChatOrchestrationCapabilities _catalog =
    AgentChatOrchestrationCapabilities(
      providers: <AgentChatProviderInstance>[
        AgentChatProviderInstance(
          id: 'codex',
          provider: 'codex',
          label: 'Codex',
          models: <AgentChatModelOption>[
            AgentChatModelOption(id: 'gpt-6-sol', label: 'GPT-6-Sol'),
            AgentChatModelOption(id: 'gpt-6-luna-2026', label: 'GPT-6-Luna'),
          ],
        ),
      ],
    );

final Finder _picker = find.byKey(const ValueKey<String>('delegateAgent'));

Future<void> _pump(WidgetTester tester, AgentChatDelegateDraft draft) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: AleraTokens.dialogWidth,
            child: DelegateChatTaskAgentFields(
              catalog: _catalog,
              draft: draft,
              onEdit: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a draft without a model names the provider default', (
    tester,
  ) async {
    await _pump(
      tester,
      const AgentChatDelegateDraft(providerInstanceId: 'codex'),
    );
    expect(
      find.descendant(
        of: _picker,
        matching: find.text('Codex · $agentChatProviderDefaultLabel'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a restyled model id is hidden but still searchable', (
    tester,
  ) async {
    await _pump(
      tester,
      const AgentChatDelegateDraft(
        providerInstanceId: 'codex',
        model: 'gpt-6-luna-2026',
      ),
    );
    expect(
      find.descendant(of: _picker, matching: find.text('Codex · GPT-6-Luna')),
      findsOneWidget,
    );
    await tester.tap(_picker);
    await tester.pumpAndSettle();
    expect(find.text('gpt-6-sol'), findsNothing);
    expect(find.text('gpt-6-luna-2026'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gpt-6-sol');
    await tester.pump();
    expect(find.text('GPT-6-Sol'), findsOneWidget);
    expect(find.text('GPT-6-Luna'), findsNothing);
  });
}
