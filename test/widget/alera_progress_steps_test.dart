import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_progress_steps.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('draws one glyph per state', (tester) async {
    await _pump(
      tester,
      const AleraProgressSteps(
        steps: <AleraProgressStep>[
          AleraProgressStep(label: 'Authenticate', state: .done),
          AleraProgressStep(
            label: 'Upload runtime',
            state: .active,
            progress: 0.5,
          ),
          AleraProgressStep(label: 'Install runtime'),
          AleraProgressStep(
            label: 'Validate runtime',
            detail: 'checksum mismatch',
            state: .failed,
          ),
          AleraProgressStep(label: 'Restart runtime', state: .skipped),
        ],
      ),
    );

    expect(find.text('Authenticate'), findsOneWidget);
    expect(find.text('checksum mismatch'), findsOneWidget);
    expect(_icon(tester, AleraIcons.check).color, AleraTokens.foregroundMuted);
    expect(_icon(tester, AleraIcons.circle).color, AleraTokens.foregroundFaint);
    expect(_icon(tester, AleraIcons.error).color, AleraTokens.error);
    expect(_icon(tester, AleraIcons.cancel).color, AleraTokens.foregroundFaint);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
    for (final icon in <IconData>[AleraIcons.check, AleraIcons.circle]) {
      expect(_icon(tester, icon).size, AleraTokens.iconMd);
    }
  });

  testWidgets('progress only shows under the active step', (tester) async {
    await _pump(
      tester,
      const AleraProgressSteps(
        dense: true,
        steps: <AleraProgressStep>[
          AleraProgressStep(label: 'Upload runtime', state: .done, progress: 1),
          AleraProgressStep(label: 'Install runtime'),
        ],
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a collapsible settings group toggles from its heading', (
    tester,
  ) async {
    var reverted = 0;
    await _pump(
      tester,
      AleraSettingsGroup(
        title: 'Advanced',
        collapsible: true,
        initiallyExpanded: false,
        trailing: TextButton(
          onPressed: () => reverted++,
          child: const Text('Revert'),
        ),
        children: const <Widget>[
          AleraSettingRow(title: 'Install Directory', child: SizedBox()),
        ],
      ),
    );

    expect(find.text('Install Directory'), findsNothing);
    expect(find.byIcon(AleraIcons.chevronRight), findsOneWidget);

    await tester.tap(find.text('Revert'));
    await tester.pump();
    expect(reverted, 1);
    expect(find.text('Install Directory'), findsNothing);

    await tester.tap(find.text('Advanced'));
    await tester.pump();
    expect(find.text('Install Directory'), findsOneWidget);
    expect(find.byIcon(AleraIcons.chevronDown), findsOneWidget);
  });

  testWidgets('a plain settings group always shows its rows', (tester) async {
    await _pump(
      tester,
      const AleraSettingsGroup(
        title: 'Safety',
        children: <Widget>[
          AleraSettingRow(title: 'Confirm Removal', child: SizedBox()),
        ],
      ),
    );

    expect(find.text('Confirm Removal'), findsOneWidget);
    expect(find.byIcon(AleraIcons.chevronDown), findsNothing);
  });
}

Icon _icon(WidgetTester tester, IconData data) =>
    tester.widget<Icon>(find.byIcon(data));

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: child,
        ),
      ),
    ),
  );
}
