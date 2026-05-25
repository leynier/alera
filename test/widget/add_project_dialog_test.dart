import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submits a local folder project', (tester) async {
    AddProjectResult? result;

    await _pumpDialogLauncher(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Project path'),
      '/projects/notes',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add project'));
    await tester.pumpAndSettle();

    expect(result, isA<AddLocalProjectResult>());
    final local = result! as AddLocalProjectResult;
    expect(local.path, '/projects/notes');
    expect(local.name, 'notes');
  });

  testWidgets('submits a clone-from-URL project', (tester) async {
    AddProjectResult? result;

    await _pumpDialogLauncher(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Git URL'),
      'https://github.com/acme/alera.git',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Destination folder'),
      '/projects/alera',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add project'));
    await tester.pumpAndSettle();

    expect(result, isA<CloneProjectResult>());
    final clone = result! as CloneProjectResult;
    expect(clone.gitUrl, 'https://github.com/acme/alera.git');
    expect(clone.destinationPath, '/projects/alera');
    expect(clone.name, 'alera');
  });
}

Future<void> _pumpDialogLauncher(
  WidgetTester tester, {
  required ValueChanged<AddProjectResult?> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  onResult(
                    await showDialog<AddProjectResult>(
                      context: context,
                      builder: (_) => const AddProjectDialog(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    ),
  );
}
