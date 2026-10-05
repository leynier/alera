import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpBadge(WidgetTester tester, AleraBadge badge) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(body: Center(child: badge)),
    ),
  );
}

BoxDecoration _decorationOf(WidgetTester tester) =>
    tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byType(AleraBadge),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  const toneColors = <AleraBadgeTone, Color>{
    AleraBadgeTone.neutral: AleraTokens.foregroundMuted,
    AleraBadgeTone.accent: AleraTokens.foreground,
    AleraBadgeTone.attention: AleraTokens.warning,
    AleraBadgeTone.success: AleraTokens.success,
    AleraBadgeTone.error: AleraTokens.error,
    AleraBadgeTone.info: AleraTokens.info,
    AleraBadgeTone.done: AleraTokens.done,
  };

  for (final MapEntry(key: tone, value: color) in toneColors.entries) {
    testWidgets('$tone draws its label in the tone color on a tint', (
      tester,
    ) async {
      await _pumpBadge(tester, AleraBadge(label: 'Label', tone: tone));

      final text = tester.widget<Text>(find.text('Label'));
      expect(text.style?.color, color);
      expect(text.style?.fontWeight, FontWeight.w600);
      final decoration = _decorationOf(tester);
      expect(
        decoration.color,
        tone == .neutral || tone == .accent
            ? AleraTokens.accentSubtle
            : color.withValues(alpha: AleraTokens.statusTintAlpha),
      );
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AleraTokens.radiusSm),
      );
    });
  }

  testWidgets('color overrides win over the tone', (tester) async {
    await _pumpBadge(
      tester,
      const AleraBadge(
        label: 'Custom',
        tone: .error,
        color: AleraTokens.surfaceElevated,
        foregroundColor: AleraTokens.foregroundFaint,
      ),
    );

    expect(
      tester.widget<Text>(find.text('Custom')).style?.color,
      AleraTokens.foregroundFaint,
    );
    expect(_decorationOf(tester).color, AleraTokens.surfaceElevated);
  });

  testWidgets('a leading icon takes the tone color', (tester) async {
    await _pumpBadge(
      tester,
      const AleraBadge(
        label: 'Checks Passing',
        tone: .success,
        icon: AleraIcons.success,
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(AleraIcons.success));
    expect(icon.color, AleraTokens.success);
    expect(icon.size, AleraTokens.iconXs);
  });

  testWidgets('a long label truncates instead of overflowing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              child: AleraBadge(
                label: 'A very long status label',
                tone: .attention,
                dot: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(find.text('A very long status label')).overflow,
      TextOverflow.ellipsis,
    );
  });
}
