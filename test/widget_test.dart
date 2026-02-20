import 'package:alera/src/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders alera shell', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: AleraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alera'), findsOneWidget);
  });
}
