import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  testWidgets('hides Add Images when the host lacks the capability', (
    tester,
  ) async {
    final client = FakeTerminalClient();
    addTearDown(client.dispose);

    await _pumpCreateScreen(tester, client: client);

    expect(find.text('Add Images'), findsNothing);
  });

  testWidgets('inserts multiple uploaded paths at the prompt selection', (
    tester,
  ) async {
    final client = FakeTerminalClient();
    final picker = _FakePromptImagePicker(<PromptImageFile>[
      _image('first.png'),
      _image('second.jpeg'),
    ]);
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      picker: picker,
      supportsPromptImageUpload: true,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Build now',
    );
    final prompt = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!;
    prompt.selection = const TextSelection.collapsed(offset: 5);

    await tester.tap(find.text('Add Images'));
    await _waitFor(
      tester,
      () =>
          client.calls
              .where((call) => call.startsWith('uploadPromptImage'))
              .length ==
          2,
    );

    expect(
      prompt.text,
      'Build\n/runtime/prompt-images/upload-1.png\n'
      '/runtime/prompt-images/upload-2.jpeg\n now',
    );
  });

  testWidgets('picker cancellation leaves the prompt unchanged', (
    tester,
  ) async {
    final client = FakeTerminalClient();
    final picker = _FakePromptImagePicker(const <PromptImageFile>[]);
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      picker: picker,
      supportsPromptImageUpload: true,
    );
    final prompt = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!;
    prompt.text = 'Keep this prompt';
    prompt.selection = TextSelection.collapsed(offset: prompt.text.length);

    await tester.tap(find.text('Add Images'));
    await tester.pumpAndSettle();

    expect(prompt.text, 'Keep this prompt');
  });

  testWidgets('keeps earlier paths when a later upload fails', (tester) async {
    final client = FakeTerminalClient()
      ..failPromptImageUploadAt = 2
      ..promptImageUploadError = StateError('host rejected image');
    final picker = _FakePromptImagePicker(<PromptImageFile>[
      _image('first.png'),
      _image('second.png'),
    ]);
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      picker: picker,
      supportsPromptImageUpload: true,
    );
    final prompt = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!;
    prompt.text = 'Build this';
    prompt.selection = TextSelection.collapsed(offset: prompt.text.length);

    await tester.tap(find.text('Add Images'));
    await _waitFor(
      tester,
      () =>
          client.calls
              .where((call) => call.startsWith('uploadPromptImage'))
              .length ==
          2,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(prompt.text, contains('/runtime/prompt-images/upload-1.png'));
    expect(prompt.text, isNot(contains('upload-2.png')));
    expect(find.textContaining('Could not add images:'), findsOneWidget);
  });

  testWidgets('disables Add Images while uploads are active', (tester) async {
    final client = FakeTerminalClient();
    final picker = _FakePromptImagePicker(<PromptImageFile>[
      _image('first.png'),
    ]);
    final pickerStarted = Completer<void>();
    picker.result = () async {
      pickerStarted.complete();
      await picker.release.future;
      return <PromptImageFile>[_image('first.png')];
    };
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      picker: picker,
      supportsPromptImageUpload: true,
    );

    await tester.tap(find.text('Add Images'));
    await pickerStarted.future;
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Add Images'),
    );
    expect(button.onPressed, isNull);
    picker.release.complete();
    await tester.pumpAndSettle();
  });
}

PromptImageFile _image(String name) {
  return PromptImageFile(
    name: name,
    sizeBytes: 8,
    openRead: () => Stream<List<int>>.value(List<int>.filled(8, 1)),
  );
}

Future<void> _pumpCreateScreen(
  WidgetTester tester, {
  required FakeTerminalClient client,
  PromptImagePicker? picker,
  bool supportsPromptImageUpload = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        home: CreateWorkspaceScreen(
          hostId: 'host-1',
          projects: const <ProjectSummary>[
            ProjectSummary(
              id: 'project-1',
              name: 'Alera',
              repoPath: '/repo/alera',
            ),
          ],
          workspaces: const [],
          promptImagePicker: picker,
          supportsPromptImageUpload: supportsPromptImageUpload,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('condition did not become true');
}

class _FakePromptImagePicker implements PromptImagePicker {
  _FakePromptImagePicker(this.images);

  final List<PromptImageFile> images;
  final Completer<void> release = Completer<void>();
  Future<List<PromptImageFile>> Function()? result;

  @override
  Future<List<PromptImageFile>> pickImages() async {
    final callback = result;
    return callback == null ? images : callback();
  }
}
