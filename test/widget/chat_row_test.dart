import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/presentation/widgets/chat_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat row uses click cursor and rounded row surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(
        child: ChatRow(
          chat: _chat(),
          worktree: null,
          isActive: false,
          isPinned: false,
          onTap: () {},
          onTogglePin: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InkWell && widget.mouseCursor == SystemMouseCursors.click,
      ),
      findsOneWidget,
    );

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(
      decoration.borderRadius,
      BorderRadius.circular(AleraTokens.radiusMd),
    );
  });

  testWidgets('hidden actions do not receive taps', (tester) async {
    var rowTaps = 0;
    var pinTaps = 0;
    var deleteTaps = 0;

    await tester.pumpWidget(
      _Host(
        child: ChatRow(
          chat: _chat(),
          worktree: null,
          isActive: false,
          isPinned: false,
          onTap: () => rowTaps++,
          onTogglePin: () => pinTaps++,
          onDelete: () => deleteTaps++,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);

    expect(rowTaps, 1);
    expect(pinTaps, 0);
    expect(deleteTaps, 0);
  });

  testWidgets('visible actions still receive taps', (tester) async {
    var rowTaps = 0;
    var deleteTaps = 0;

    await tester.pumpWidget(
      _Host(
        child: ChatRow(
          chat: _chat(),
          worktree: null,
          isActive: true,
          isPinned: false,
          onTap: () => rowTaps++,
          onTogglePin: () {},
          onDelete: () => deleteTaps++,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));

    expect(rowTaps, 0);
    expect(deleteTaps, 1);
  });
}

ChatSummary _chat() {
  final now = DateTime(2026, 5, 16);
  return ChatSummary(
    id: 'chat-1',
    projectId: 'project-1',
    title: 'Sidebar polish',
    model: 'gpt-test',
    createdAt: now,
    updatedAt: now,
  );
}

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, child: child)),
      ),
    );
  }
}
