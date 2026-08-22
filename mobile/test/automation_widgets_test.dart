import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Run Now exposes precheck, overlap, and revision choices', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MobileRunChoiceDialog()));

    expect(find.text('Run Now'), findsOneWidget);
    expect(find.text('Run Precheck'), findsOneWidget);
    expect(find.text('Audited Draft Test'), findsOneWidget);
    expect(find.text('Approve Exact Revision'), findsOneWidget);
    expect(find.text('Overlap'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Run Latest Once'), findsOneWidget);
    expect(find.text('Force Parallel'), findsOneWidget);
  });

  testWidgets('pause exposes the active-run decision', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MobilePauseChoiceDialog()));

    expect(find.text('Continue Active'), findsOneWidget);
    expect(find.text('Cancel Active'), findsOneWidget);
  });
}
