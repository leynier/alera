import 'package:alera/src/features/chat_tasks/presentation/chat_task_dock_view.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _at = DateTime.utc(2026, 11);

AgentChatTask _task(String id, String title, {int minutes = 0}) =>
    AgentChatTask(
      id: id,
      status: AgentChatTaskStatus.running,
      title: title,
      createdAt: _at,
      updatedAt: _at.add(Duration(minutes: minutes)),
    );

Future<void> _pump(
  WidgetTester tester,
  List<AgentChatTask> tasks, {
  required bool waiting,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ChatTaskDockView(
        tasks: tasks,
        expanded: false,
        onExpandedChanged: (_) {},
        now: () => _at,
        placeOf: (_) => 'Alera / main',
        actions: ChatTaskDockActions(onView: (_) {}),
        waiting: waiting,
      ),
    ),
  ),
);

void main() {
  testWidgets('one running task is named in the collapsed line', (
    tester,
  ) async {
    await _pump(tester, <AgentChatTask>[
      _task('a', 'Fix the parser'),
    ], waiting: false);
    expect(find.text('Running Fix the parser'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('chatTaskDockDetail')),
      findsNothing,
    );
  });

  testWidgets('a waiting chat counts its tasks and shows the newest', (
    tester,
  ) async {
    await _pump(tester, <AgentChatTask>[
      _task('a', 'Fix the parser'),
      _task('b', 'Write the tests', minutes: 1),
    ], waiting: true);
    expect(find.text('Waiting on 2 tasks · 2 running'), findsOneWidget);
    expect(find.text('Write the tests'), findsOneWidget);
  });
}
