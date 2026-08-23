import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  testWidgets('renders local icon assets for every supported agent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: <Widget>[
            AgentIdentityIcon(agentType: AgentType.codex),
            AgentIdentityIcon(agentType: AgentType.claude),
            AgentIdentityIcon(agentType: AgentType.copilot),
            AgentIdentityIcon(agentType: AgentType.cursor),
            AgentIdentityIcon(agentType: AgentType.agy),
            AgentIdentityIcon(agentType: AgentType.opencode),
            AgentIdentityIcon(agentType: AgentType.pi),
            AgentIdentityIcon(agentType: AgentType.amp),
            AgentIdentityIcon(agentType: AgentType.grok),
            AgentIdentityIcon(agentType: AgentType.fx),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SvgPicture), findsNWidgets(6));
    expect(find.byType(Image), findsNWidgets(4));
    expect(find.byTooltip('Codex'), findsOneWidget);
    expect(find.byTooltip('Claude Code'), findsOneWidget);
    expect(find.byTooltip('GitHub Copilot'), findsOneWidget);
    expect(find.byTooltip('Cursor'), findsOneWidget);
    expect(find.byTooltip('Antigravity'), findsOneWidget);
    expect(find.byTooltip('OpenCode'), findsOneWidget);
    expect(find.byTooltip('Pi'), findsOneWidget);
    expect(find.byTooltip('Amp'), findsOneWidget);
    expect(find.byTooltip('Grok Build'), findsOneWidget);
    expect(find.byTooltip('fx'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
