import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera/src/design_system/configuration/alera_configuration_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'conflicts disable apply and show the named target and both values',
    (tester) async {
      final local = ConfigurationDocument.empty().withBlocks({
        'desktop': {'fontSize': 12},
      });
      final remote = ConfigurationDocument.empty().withBlocks({
        'desktop': {'fontSize': 16},
      });
      final review = ConfigurationReview(
        ConfigurationLocalSnapshot(document: local, fingerprint: local.digest),
        null,
        null,
        ConfigurationMerge(local: local, remote: remote),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AleraConfigurationReview(
                target: 'Work Laptop',
                state: ConfigurationScreenState(review: review),
                onRefresh: () {},
                onHistory: () {},
                onRestore: (_) {},
                onChoice: (_, _) {},
                onRename: (_, _) {},
                onChooseAll: (_) {},
                onApply: (_) => fail('Unresolved conflicts must not apply'),
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Target: Work Laptop'), findsOneWidget);
      expect(find.text('Local: 12'), findsOneWidget);
      expect(find.text('Remote: 16'), findsOneWidget);
      final apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply To Device'),
      );
      expect(apply.onPressed, isNull);
    },
  );
}
