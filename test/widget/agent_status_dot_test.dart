import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_status_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('projects working, waiting, and done states to status dots', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Row(
          children: <Widget>[
            AgentStatusDot(status: _entry(AgentStatusState.working)),
            AgentStatusDot(status: _entry(AgentStatusState.waiting)),
            AgentStatusDot(status: _entry(AgentStatusState.done)),
          ],
        ),
      ),
    );

    final dots = tester.widgetList<AleraStatusDot>(find.byType(AleraStatusDot));

    expect(dots.map((dot) => dot.color), <Color>[
      AleraTokens.info,
      AleraTokens.warning,
      AleraTokens.success,
    ]);
    expect(find.byType(Tooltip), findsNWidgets(3));
  });
}

AgentStatusEntry _entry(AgentStatusState state) {
  return AgentStatusEntry(
    terminalSessionId: 'session-$state',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: AgentType.codex,
    state: state,
    prompt: '',
    updatedAt: DateTime.utc(2026, 5, 26),
    stateStartedAt: DateTime.utc(2026, 5, 26),
  );
}
