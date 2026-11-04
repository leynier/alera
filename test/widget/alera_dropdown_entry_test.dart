import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dropdown entry exposes the expected height and selection match', () {
    const enabled = AleraDropdownEntry<String>(value: 'tokyo', label: 'Tokyo');
    const disabled = AleraDropdownEntry<String>(
      value: 'tokyo',
      label: 'Tokyo',
      enabled: false,
    );

    expect(enabled.height, 36);
    expect(enabled.represents('tokyo'), isTrue);
    expect(disabled.represents('tokyo'), isFalse);
  });

  test('subtitle and description each add their own height', () {
    const subtitle = AleraDropdownEntry<String>(
      value: 'child',
      label: 'Child',
      subtitle: 'feature/child',
    );
    const description = AleraDropdownEntry<String>(
      value: 'full',
      label: 'Full Access',
      description: 'Run commands without asking.',
    );
    const both = AleraDropdownEntry<String>(
      value: 'both',
      label: 'Both',
      subtitle: 'feature/both',
      description: 'Run commands without asking.',
    );

    expect(subtitle.height, 48);
    expect(description.height, AleraTokens.menuRowWithDescriptionHeight);
    expect(
      both.height,
      AleraTokens.menuRowWithDescriptionHeight + AleraTokens.space12,
    );
  });

  testWidgets('label, subtitle and detail stay on one line', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: SizedBox(
            width: 200,
            child: AleraDropdownEntry<String>(
              value: 'child',
              label: 'A workspace name long enough to need ellipsis',
              subtitle: 'feature/a-branch-name-long-enough-to-need-ellipsis',
              detail: 'A detail long enough to need ellipsis as well',
              description:
                  'A description sentence that may wrap onto a second line '
                  'before it ellipsizes.',
            ),
          ),
        ),
      ),
    );

    Text textOf(String prefix) =>
        tester.widget<Text>(find.textContaining(prefix));

    expect(textOf('A workspace name').maxLines, 1);
    expect(textOf('feature/').maxLines, 1);
    expect(textOf('A detail').maxLines, 1);
    expect(textOf('A description').maxLines, 2);
    expect(tester.takeException(), isNull);
  });
}
