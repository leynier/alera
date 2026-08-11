import 'package:alera/src/app/app.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/runtime_host/presentation/runtime_host_quit_gate_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders alera shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AleraApp()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AleraShellPage), findsOneWidget);
  });

  testWidgets('places the runtime quit gate below the navigator', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AleraApp()));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.ancestor(
        of: find.byType(RuntimeHostQuitGateScope),
        matching: find.byType(Navigator),
      ),
      findsOneWidget,
    );
  });
}
