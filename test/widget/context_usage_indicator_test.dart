import 'dart:ui';

import 'package:alera/src/features/session/domain/context_usage.dart';
import 'package:alera/src/features/session/domain/token_usage.dart';
import 'package:alera/src/features/session/presentation/widgets/context_usage_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpIndicator(
  WidgetTester tester, {
  required ContextUsage usage,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: ContextUsageIndicator(contextUsage: usage, onCompact: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('popover shows current context and session usage semantics', (
    tester,
  ) async {
    const usage = ContextUsage(
      tokenUsageInfo: TokenUsageInfo(
        totalTokenUsage: TokenUsage(
          inputTokens: 220000,
          cachedInputTokens: 20000,
          outputTokens: 5000,
          totalTokens: 205000,
        ),
        lastTokenUsage: TokenUsage(totalTokens: 12000),
        modelContextWindow: 128000,
      ),
    );
    await _pumpIndicator(tester, usage: usage);

    final indicator = find.byType(ContextUsageIndicator);
    expect(indicator, findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(indicator));
    await tester.pumpAndSettle();

    expect(find.text('Context window:'), findsOneWidget);
    expect(find.text('12K / 128K tokens in current context'), findsOneWidget);
    expect(find.text('205K session tokens used'), findsOneWidget);

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator).first,
    );
    expect(progress.value, closeTo(12000 / 128000, 0.0001));
  });
}
