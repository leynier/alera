import 'package:alera/src/design_system/layout/alera_choice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Choice { leave, force }

Widget _wrapDialog({required ValueChanged<_Choice?> onResult}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: FilledButton(
            onPressed: () async {
              onResult(
                await showDialog<_Choice>(
                  context: context,
                  builder: (_) => const AleraChoiceDialog<_Choice>(
                    title: 'Runtime Still Has Work',
                    message: 'The runtime has 1 open agent(s).',
                    primaryLabel: 'Quit And Leave Runtime Open',
                    primaryValue: .leave,
                    secondaryLabel: 'Force Stop And Quit',
                    secondaryValue: .force,
                    destructiveSecondary: true,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        );
      },
    ),
  );
}

void main() {
  testWidgets('cancel closes the choice dialog with null', (tester) async {
    _Choice? result = .leave;

    await tester.pumpWidget(_wrapDialog(onResult: (value) => result = value));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('primary returns leave-open', (tester) async {
    _Choice? result;

    await tester.pumpWidget(_wrapDialog(onResult: (value) => result = value));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quit And Leave Runtime Open'));
    await tester.pumpAndSettle();

    expect(result, _Choice.leave);
  });

  testWidgets('secondary returns force-stop', (tester) async {
    _Choice? result;

    await tester.pumpWidget(_wrapDialog(onResult: (value) => result = value));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force Stop And Quit'));
    await tester.pumpAndSettle();

    expect(result, _Choice.force);
  });

  testWidgets('stacked orders primary, secondary, then cancel', (tester) async {
    _Choice? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showDialog<_Choice>(
                    context: context,
                    builder: (_) => const AleraChoiceDialog<_Choice>(
                      title: 'Ship Changes?',
                      message: 'Pick a scope.',
                      primaryLabel: 'Ship Staged Changes',
                      primaryValue: .leave,
                      secondaryLabel: 'Ship All Changes',
                      secondaryValue: .force,
                      stackedActions: true,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final primaryTop = tester.getTopLeft(find.text('Ship Staged Changes'));
    final secondaryTop = tester.getTopLeft(find.text('Ship All Changes'));
    final cancelTop = tester.getTopLeft(find.text('Cancel'));
    expect(primaryTop.dy, lessThan(secondaryTop.dy));
    expect(secondaryTop.dy, lessThan(cancelTop.dy));

    await tester.tap(find.text('Ship All Changes'));
    await tester.pumpAndSettle();

    expect(result, _Choice.force);
  });
}
