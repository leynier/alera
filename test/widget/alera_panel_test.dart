import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('applies an optional max height constraint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AleraPanel(
              maxHeight: 80,
              children: <Widget>[
                SizedBox(height: 32, child: Text('Constrained panel')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Constrained panel'), findsOneWidget);
    expect(
      tester.getSize(find.byType(AleraPanel)).height,
      lessThanOrEqualTo(80),
    );
  });
}
