import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapDialog({
  required ValueChanged<bool?> onResult,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: FilledButton(
            onPressed: () async {
              onResult(
                await showDialog<bool>(
                  context: context,
                  builder: (_) => AleraConfirmDialog(
                    title: 'Delete Workspace',
                    message: 'This Action Cannot Be Undone.',
                    confirmLabel: confirmLabel,
                    cancelLabel: cancelLabel,
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
  testWidgets('cancel closes the confirm dialog with false', (tester) async {
    bool? result;

    await tester.pumpWidget(_wrapDialog(onResult: (value) => result = value));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('confirm closes the dialog with true', (tester) async {
    bool? result;

    await tester.pumpWidget(_wrapDialog(onResult: (value) => result = value));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('footer actions have equal widths', (tester) async {
    await tester.pumpWidget(_wrapDialog(onResult: (_) {}));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final cancelSize = tester.getSize(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    final confirmSize = tester.getSize(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    expect(cancelSize.width, confirmSize.width);
  });

  testWidgets('long footer labels remain responsive on a narrow surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrapDialog(
        onResult: (_) {},
        cancelLabel: 'Keep Pull Request Linked',
        confirmLabel: 'Unlink Pull Request',
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final cancel = find.widgetWithText(TextButton, 'Keep Pull Request Linked');
    final confirm = find.widgetWithText(FilledButton, 'Unlink Pull Request');
    expect(cancel, findsOneWidget);
    expect(confirm, findsOneWidget);
    expect(tester.getSize(cancel).width, tester.getSize(confirm).width);
    expect(tester.takeException(), isNull);
  });
}
