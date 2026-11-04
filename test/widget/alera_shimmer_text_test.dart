import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildAleraDarkTheme(),
  home: Scaffold(body: Center(child: child)),
);

const Key _scopeChild = ValueKey<String>('shimmer-scope-child');

/// A scope whose content the test can swap without replacing the scope.
Widget _scoped(ValueNotifier<Widget> content) => _app(
  AleraShimmerScope(
    child: KeyedSubtree(
      key: _scopeChild,
      child: ValueListenableBuilder<Widget>(
        valueListenable: content,
        builder: (context, child, _) => child,
      ),
    ),
  ),
);

bool _scopeAnimating(WidgetTester tester) =>
    AleraShimmerScope.isAnimating(tester.element(find.byKey(_scopeChild)));

void main() {
  testWidgets('renders static muted text without a scope', (tester) async {
    await tester.pumpWidget(_app(const AleraShimmerText(text: 'Thinking')));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text('Thinking'));
    expect(text.style?.color, AleraTokens.foregroundMuted);
    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);

    await tester.binding.delayed(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('animates inside a scope and goes idle once unmounted', (
    tester,
  ) async {
    final content = ValueNotifier<Widget>(
      const AleraShimmerText(text: 'Working', style: TextStyle(fontSize: 12)),
    );
    addTearDown(content.dispose);
    await tester.pumpWidget(_scoped(content));

    expect(find.text('Working'), findsOneWidget);
    expect(_scopeAnimating(tester), isTrue);
    expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(1));

    // The paced phase requests repaints without a pump of its own.
    await tester.binding.delayed(const Duration(milliseconds: 120));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();

    content.value = const SizedBox.shrink();
    await tester.pump();
    expect(find.text('Working'), findsNothing);
    expect(_scopeAnimating(tester), isFalse);

    await tester.binding.delayed(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('pauses under a disabled ticker mode or a hidden window', (
    tester,
  ) async {
    final content = ValueNotifier<Widget>(
      const TickerMode(
        enabled: false,
        child: AleraShimmerText(text: 'Streaming…'),
      ),
    );
    addTearDown(content.dispose);
    await tester.pumpWidget(_scoped(content));

    expect(find.text('Streaming…'), findsOneWidget);
    expect(_scopeAnimating(tester), isFalse);

    content.value = const AleraShimmerText(text: 'Streaming…');
    await tester.pump();
    expect(_scopeAnimating(tester), isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(_scopeAnimating(tester), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(_scopeAnimating(tester), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(_scopeAnimating(tester), isTrue);
  });
}
