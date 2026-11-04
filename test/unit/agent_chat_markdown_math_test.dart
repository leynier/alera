import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('turns dollar math into the forms the renderer typesets', () {
    expect(
      agentChatDollarMath(r'Euler: $e^{i\pi} + 1 = 0$.'),
      r'Euler: \(e^{i\pi} + 1 = 0\).',
    );
    expect(
      agentChatDollarMath('Sum:\n\n\$\$\n\\sum_i x_i\n\$\$\n'),
      'Sum:\n\n\\[\n\\sum_i x_i\n\\]\n',
    );
  });

  test('leaves prices, shell variables and escapes alone', () {
    for (final text in <String>[
      r'It costs $5 and $10.',
      r'Copy $HOME/$USER first.',
      r'Run $ ls in the shell.',
      r'A literal \$x\$ stays.',
      r'Unclosed $$ display',
    ]) {
      expect(agentChatDollarMath(text), text, reason: text);
    }
  });

  test('leaves fenced and inline code alone', () {
    const fenced = '```sh\necho \$a\$\n```\nthen \$x\$';
    expect(agentChatDollarMath(fenced), '```sh\necho \$a\$\n```\nthen \\(x\\)');
    expect(agentChatDollarMath(r'Use `$a$` or $b$'), r'Use `$a$` or \(b\)');
  });

  testWidgets('chat Markdown typesets math in Flutter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(
          body: AgentChatMarkdown(data: r'The area is $\pi r^2$, about $5.'),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'Math',
      ),
      findsOneWidget,
    );
  });
}
