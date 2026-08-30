import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_attachment_providers.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_file_picker.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  testWidgets('hides Add Attachment when the host offers no source', (
    tester,
  ) async {
    final client = FakeTerminalClient();
    addTearDown(client.dispose);

    await _pumpCreateScreen(tester, client: client);

    expect(find.text('Add Attachment'), findsNothing);
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

    await _openAttachmentSource(tester, 'Photo Library');
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

    await _openAttachmentSource(tester, 'Photo Library');
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

    await _openAttachmentSource(tester, 'Photo Library');
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
    expect(
      find.textContaining('Could not add the attachment:'),
      findsOneWidget,
    );
  });

  testWidgets('disables Add Attachment while uploads are active', (
    tester,
  ) async {
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

    await _openAttachmentSource(tester, 'Photo Library');
    await pickerStarted.future;
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Add Attachment'),
    );
    expect(button.onPressed, isNull);
    picker.release.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('uploads a device file and inserts its host path', (
    tester,
  ) async {
    final client = FakeTerminalClient()..promptFileUploadSupported = true;
    final filePicker = _FakePromptFilePicker(
      PromptFile(
        name: 'notes.pdf',
        sizeBytes: 4,
        openRead: () => Stream<List<int>>.value(<int>[1, 2, 3, 4]),
      ),
    );
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      filePicker: filePicker,
      supportsPromptFileUpload: true,
    );
    final prompt = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!;
    prompt.text = 'Review this';
    prompt.selection = TextSelection.collapsed(offset: prompt.text.length);

    await _openAttachmentSource(tester, 'Files');
    await _waitFor(
      tester,
      () => client.calls.any((call) => call.startsWith('uploadPromptFile')),
    );
    await tester.pumpAndSettle();

    expect(filePicker.pickCount, 1);
    expect(
      prompt.text,
      'Review this\n/runtime/prompt-files/upload-1-notes.pdf',
    );
  });

  testWidgets('a dismissed file picker leaves the prompt unchanged', (
    tester,
  ) async {
    final client = FakeTerminalClient()..promptFileUploadSupported = true;
    final filePicker = _FakePromptFilePicker(null);
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      filePicker: filePicker,
      supportsPromptFileUpload: true,
    );
    final prompt = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!;
    prompt.text = 'Keep this prompt';

    await _openAttachmentSource(tester, 'Files');
    await tester.pumpAndSettle();

    expect(filePicker.pickCount, 1);
    expect(prompt.text, 'Keep this prompt');
    expect(
      client.calls.any((call) => call.startsWith('uploadPromptFile')),
      isFalse,
    );
  });

  testWidgets('workspace files insert a relative path from a sibling', (
    tester,
  ) async {
    // The workspace being created has no worktree yet, so Quick Open runs
    // against a sibling of the same project and answers with a relative path
    // that stays valid in the new one.
    final client = FakeTerminalClient()
      ..workspaceFiles = const <String>['lib/src/main.dart'];
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      supportsWorkspaceFiles: true,
      workspaces: <WorkspaceSummary>[
        _workspace(id: 'workspace-main', isMain: true),
        _workspace(id: 'workspace-feature'),
      ],
    );
    final prompt = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!;
    prompt.text = 'Change';
    prompt.selection = TextSelection.collapsed(offset: prompt.text.length);

    await _openAttachmentSource(tester, 'Workspace File');
    await tester.pumpAndSettle();
    await tester.tap(find.text('lib/src/main.dart'));
    await tester.pumpAndSettle();

    expect(client.calls, contains('startWorkspaceQuickOpen workspace-main'));
    expect(prompt.text, 'Change\nlib/src/main.dart');
    expect(client.stoppedQuickOpenSessions, hasLength(1));
  });

  testWidgets('workspace files follow the chosen parent workspace', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..workspaceFiles = const <String>['lib/src/main.dart'];
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      supportsWorkspaceFiles: true,
      workspaces: <WorkspaceSummary>[
        _workspace(id: 'workspace-main', isMain: true),
        _workspace(id: 'workspace-feature'),
      ],
    );

    await tester.tap(find.text('Alera / workspace-main'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alera / workspace-feature').last);
    await tester.pumpAndSettle();

    await _openAttachmentSource(tester, 'Workspace File');
    await tester.pumpAndSettle();

    expect(client.calls, contains('startWorkspaceQuickOpen workspace-feature'));
  });

  testWidgets('a parent from another project does not index its files', (
    tester,
  ) async {
    // Quick Open answers with paths relative to the worktree it indexed, so a
    // parent outside the project being branched would hand back paths that do
    // not exist in the new workspace.
    final client = FakeTerminalClient()
      ..workspaceFiles = const <String>['lib/src/main.dart'];
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      supportsWorkspaceFiles: true,
      workspaces: <WorkspaceSummary>[
        _workspace(id: 'workspace-main', isMain: true),
        _workspace(id: 'other-project-workspace', projectId: 'project-2'),
      ],
    );

    await tester.tap(find.text('Alera / workspace-main'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('project-2 / other-project-workspace').last);
    await tester.pumpAndSettle();

    await _openAttachmentSource(tester, 'Workspace File');
    await tester.pumpAndSettle();

    expect(client.calls, contains('startWorkspaceQuickOpen workspace-main'));
    expect(
      client.calls.any((call) => call.contains('other-project-workspace')),
      isFalse,
    );
  });

  testWidgets('offers only the sources the host supports', (tester) async {
    final client = FakeTerminalClient()..promptFileUploadSupported = true;
    addTearDown(client.dispose);

    await _pumpCreateScreen(
      tester,
      client: client,
      supportsPromptFileUpload: true,
    );

    await tester.tap(find.text('Add Attachment'));
    await tester.pumpAndSettle();

    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Photo Library'), findsNothing);
    expect(find.text('Workspace File'), findsNothing);
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
  PromptFilePicker? filePicker,
  bool supportsPromptImageUpload = false,
  bool supportsPromptFileUpload = false,
  bool supportsWorkspaceFiles = false,
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        if (picker != null) promptImagePickerProvider.overrideWithValue(picker),
        if (filePicker != null)
          promptFilePickerProvider.overrideWithValue(filePicker),
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
          workspaces: workspaces,
          supportsPromptImageUpload: supportsPromptImageUpload,
          supportsPromptFileUpload: supportsPromptFileUpload,
          supportsWorkspaceFiles: supportsWorkspaceFiles,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the attachment sheet and taps one source.
Future<void> _openAttachmentSource(WidgetTester tester, String source) async {
  await tester.tap(find.text('Add Attachment'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(source));
  await tester.pump();
}

WorkspaceSummary _workspace({
  required String id,
  String projectId = 'project-1',
  bool isMain = false,
}) => WorkspaceSummary(
  id: id,
  projectId: projectId,
  name: id,
  path: '/repo/$id',
  kind: isMain ? 'main' : 'linked',
);

class _FakePromptFilePicker(final PromptFile? file)
    implements PromptFilePicker {
  var pickCount = 0;

  @override
  Future<PromptFile?> pickFile() async {
    pickCount += 1;
    return file;
  }
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

class _FakePromptImagePicker(final List<PromptImageFile> images)
    implements PromptImagePicker {
  final Completer<void> release = Completer<void>();
  Future<List<PromptImageFile>> Function()? result;

  @override
  Future<List<PromptImageFile>> pickImages() async {
    final callback = result;
    return callback == null ? images : callback();
  }
}
