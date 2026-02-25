import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/session/presentation/widgets/approval_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('approval card description is scrollable for long content', (
    tester,
  ) async {
    final longDescription = List<String>.generate(
      120,
      (index) => 'line $index: long content for approval card',
    ).join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovalCard(
            approval: PendingApproval(
              requestId: 'req-1',
              method: 'functions.exec_command',
              description: longDescription,
            ),
            onApprove: () {},
            onApproveForSession: () {},
            onDecline: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('approval-description-scroll')),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Allow once'), findsOneWidget);
    expect(find.text('Allow for session'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });
}
