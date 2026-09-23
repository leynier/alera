part of 'create_workspace_prompt_attachment_test.dart';

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
  bool supportsSharedCheckoutWorkspaces = true,
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
          supportsSharedCheckoutWorkspaces: supportsSharedCheckoutWorkspaces,
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

Future<void> _showAttachmentSheet(WidgetTester tester) async {
  final addAttachment = find.text('Add Attachment');
  await tester.scrollUntilVisible(
    addAttachment,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(addAttachment);
  await tester.pumpAndSettle();
}

/// Opens the attachment sheet and taps one source.
Future<void> _openAttachmentSource(WidgetTester tester, String source) async {
  await _showAttachmentSheet(tester);
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
