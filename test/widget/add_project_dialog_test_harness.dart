part of 'add_project_dialog_test.dart';

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

class _FakeFileSelectorPlatform extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelectorPlatform(this.responses);

  final List<Object?> responses;
  final List<_DirectoryRequest> requests = <_DirectoryRequest>[];

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) async {
    requests.add(
      _DirectoryRequest(
        initialDirectory: options.initialDirectory,
        confirmButtonText: options.confirmButtonText,
        canCreateDirectories: options.canCreateDirectories,
      ),
    );
    if (responses.isEmpty) {
      return null;
    }
    final next = responses.removeAt(0);
    if (next is Object && next is! String) {
      throw next;
    }
    return next as String?;
  }
}

class _DirectoryRequest {
  const _DirectoryRequest({
    required this.initialDirectory,
    required this.confirmButtonText,
    required this.canCreateDirectories,
  });

  final String? initialDirectory;
  final String? confirmButtonText;
  final bool? canCreateDirectories;
}
