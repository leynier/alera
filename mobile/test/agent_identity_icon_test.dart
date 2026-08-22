import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders local icon assets for every supported agent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: <Widget>[
            AgentIdentityIcon(agentType: 'codex'),
            AgentIdentityIcon(agentType: 'claude'),
            AgentIdentityIcon(agentType: 'copilot'),
            AgentIdentityIcon(agentType: 'cursor'),
            AgentIdentityIcon(agentType: 'agy'),
            AgentIdentityIcon(agentType: 'opencode'),
            AgentIdentityIcon(agentType: 'pi'),
            AgentIdentityIcon(agentType: 'amp'),
            AgentIdentityIcon(agentType: 'grok'),
            AgentIdentityIcon(agentType: 'fx'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SvgPicture), findsNWidgets(6));
    expect(find.byType(Image), findsNWidgets(4));
    expect(find.byTooltip('fx'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
